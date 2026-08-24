package handlers

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type UpdateHandler struct{}

// ======== 公开接口 ========

func (h *UpdateHandler) CheckUpdate(c *gin.Context) {
	platform := c.Query("platform")
	codeStr := c.Query("version_code")

	if platform == "" || codeStr == "" {
		utils.BadRequest(c, "缺少 platform 或 version_code 参数")
		return
	}

	versionCode, err := strconv.Atoi(codeStr)
	if err != nil {
		utils.BadRequest(c, "version_code 必须是整数")
		return
	}

	all := services.ListAppVersions("VersionCode desc")

	var latest *models.AppVersion
	for i := range all {
		if all[i].Platform == platform && all[i].Status == 1 {
			latest = &all[i]
			break
		}
	}

	if latest == nil || latest.VersionCode <= versionCode {
		utils.Success(c, gin.H{"has_update": false})
		return
	}

	utils.Success(c, gin.H{
		"has_update":    true,
		"version":       latest.Version,
		"version_code":  latest.VersionCode,
		"file_size":     latest.FileSize,
		"release_notes": latest.ReleaseNotes,
		"is_force":      latest.IsForce,
		"download_url":  fmt.Sprintf("/api/v1/update/download/%d", latest.ID),
	})
}

func (h *UpdateHandler) Download(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	v, err := services.FindAppVersionByID(uint(id))
	if err != nil || v == nil || v.Status != 1 {
		utils.NotFound(c, "版本不存在或已下架")
		return
	}

	// 优先走外部直链（节省主服务器流量），否则走本地文件
	if v.DownloadURL != "" {
		if !isSafeDownloadURL(v.DownloadURL) {
			log.Printf("⚠️ 拒绝不安全的外部下载链接: 版本 %d URL=%s", id, v.DownloadURL)
			utils.BadRequest(c, "下载链接不安全")
			return
		}
		services.UpdateAppVersionByID(uint(id), map[string]interface{}{"DownloadCount": v.DownloadCount + 1})
		c.Redirect(302, v.DownloadURL)
		return
	}

	if _, err := os.Stat(v.FilePath); os.IsNotExist(err) {
		utils.NotFound(c, "安装包文件不存在")
		return
	}

	services.UpdateAppVersionByID(uint(id), map[string]interface{}{"DownloadCount": v.DownloadCount + 1})

	serveFileWithRange(c, v.FilePath, v.Platform, v.Version)
}

// serveFileWithRange 手动实现 Range 响应，使用 256KB 大 buffer 提升 IO 吞吐
// 相比 http.ServeContent 的 32KB buffer，可显著提升下载速度（尤其大文件）
func serveFileWithRange(c *gin.Context, filePath, platform, version string) {
	stat, err := os.Stat(filePath)
	if err != nil {
		utils.NotFound(c, "安装包文件不存在")
		return
	}
	fileSize := stat.Size()

	filename := fmt.Sprintf("%s-v%s-%s%s", platform, version, "update", filepath.Ext(filePath))
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Accept-Ranges", "bytes")
	c.Header("Content-Type", "application/octet-stream")

	// 解析 Range 头
	rangeHeader := c.GetHeader("Range")
	if rangeHeader == "" {
		// 无 Range：完整文件下载
		c.Header("Content-Length", strconv.FormatInt(fileSize, 10))
		c.Status(http.StatusOK)
		streamFile(c.Writer, filePath, fileSize)
		return
	}

	// 处理 bytes=start-end 格式
	const prefix = "bytes="
	if !strings.HasPrefix(rangeHeader, prefix) {
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}
	rangeSpec := strings.TrimPrefix(rangeHeader, prefix)
	parts := strings.Split(rangeSpec, "-")
	if len(parts) != 2 {
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}

	var start, end int64
	if parts[0] == "" {
		// bytes=-N：最后 N 字节
		n, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil || n <= 0 {
			c.Status(http.StatusRequestedRangeNotSatisfiable)
			return
		}
		if n > fileSize {
			n = fileSize
		}
		start = fileSize - n
		end = fileSize - 1
	} else {
		s, err := strconv.ParseInt(parts[0], 10, 64)
		if err != nil || s < 0 || s >= fileSize {
			c.Status(http.StatusRequestedRangeNotSatisfiable)
			return
		}
		start = s
		if parts[1] == "" {
			end = fileSize - 1
		} else {
			e, err := strconv.ParseInt(parts[1], 10, 64)
			if err != nil || e >= fileSize {
				end = fileSize - 1
			} else {
				end = e
			}
		}
	}

	if start > end {
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}

	contentLength := end - start + 1
	c.Header("Content-Length", strconv.FormatInt(contentLength, 10))
	c.Header("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, fileSize))
	c.Status(http.StatusPartialContent)
	streamFileRange(c.Writer, filePath, start, contentLength)
}

// streamFile 用 256KB buffer 流式发送整个文件
func streamFile(w http.ResponseWriter, filePath string, fileSize int64) {
	file, err := os.Open(filePath)
	if err != nil {
		return
	}
	defer file.Close()

	// 256KB buffer —— 远大于 http.ServeContent 默认的 32KB
	buf := make([]byte, 256*1024)
	_, _ = io.CopyBuffer(w, file, buf)
}

// streamFileRange 用 256KB buffer 流式发送文件区间
func streamFileRange(w http.ResponseWriter, filePath string, start, length int64) {
	file, err := os.Open(filePath)
	if err != nil {
		return
	}
	defer file.Close()

	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return
	}

	// 256KB buffer
	buf := make([]byte, 256*1024)
	remaining := length
	for remaining > 0 {
		toRead := int64(len(buf))
		if toRead > remaining {
			toRead = remaining
		}
		n, err := file.Read(buf[:toRead])
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return
			}
			remaining -= int64(n)
		}
		if err != nil {
			return
		}
	}
}

func (h *UpdateHandler) ListVersions(c *gin.Context) {
	platform := c.Query("platform")

	all := services.ListAppVersions("VersionCode desc")

	var result []gin.H
	for _, v := range all {
		if platform != "" && v.Platform != platform {
			continue
		}
		if v.Status != 1 {
			continue
		}
		result = append(result, gin.H{
			"id":            v.ID,
			"platform":      v.Platform,
			"version":       v.Version,
			"version_code":  v.VersionCode,
			"file_size":     v.FileSize,
			"release_notes": v.ReleaseNotes,
			"is_force":      v.IsForce,
			"download_url":  fmt.Sprintf("/api/v1/update/download/%d", v.ID),
		})
	}

	utils.Success(c, result)
}

// ======== 管理接口 ========

func (h *UpdateHandler) AdminListVersions(c *gin.Context) {
	all := services.ListAppVersions("ID desc")
	utils.Success(c, all)
}

func (h *UpdateHandler) UploadVersion(c *gin.Context) {
	platform := c.PostForm("platform")
	version := c.PostForm("version")
	codeStr := c.PostForm("version_code")
	notes := c.PostForm("release_notes")
	isForce := c.PostForm("is_force") == "true"
	downloadURL := c.PostForm("download_url")
	versionCode, _ := strconv.Atoi(codeStr)

	file, err := c.FormFile("file")

	// 本地文件与外部直链至少要有一个
	if err != nil && downloadURL == "" {
		utils.BadRequest(c, "请上传安装包文件或填写外部下载直链")
		return
	}

	v := models.AppVersion{
		Platform:     platform,
		Version:      version,
		VersionCode:  versionCode,
		ReleaseNotes: notes,
		IsForce:      isForce,
		DownloadURL:  downloadURL,
		Status:       1,
	}

	// 若提供了本地文件，则保存
	if err == nil {
		dir := "uploads/releases"
		os.MkdirAll(dir, 0755)
		// multipart 文件名客户端可控，可能含 ../ 路径穿越，必须取 Base
		filename := fmt.Sprintf("%s_%s", uuid.New().String(), filepath.Base(file.Filename))
		filePath := filepath.Join(dir, filename)
		if err := c.SaveUploadedFile(file, filePath); err != nil {
			log.Printf("保存文件失败: %v", err)
			utils.Internal(c, "保存文件失败")
			return
		}
		v.FilePath = filePath
		v.FileSize = file.Size
	}

	if err := services.InsertAppVersion(&v); err != nil {
		utils.Internal(c, "保存失败")
		return
	}

	utils.Success(c, v)
}

func (h *UpdateHandler) UpdateVersion(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	platform := c.PostForm("platform")
	version := c.PostForm("version")
	codeStr := c.PostForm("version_code")
	notes := c.PostForm("release_notes")
	isForceStr := c.PostForm("is_force")
	statusStr := c.PostForm("status")

	updates := map[string]interface{}{}
	if platform != "" {
		updates["Platform"] = platform
	}
	if version != "" {
		updates["Version"] = version
	}
	if codeStr != "" {
		code, _ := strconv.Atoi(codeStr)
		updates["VersionCode"] = code
	}
	if notes != "" {
		updates["ReleaseNotes"] = notes
	}
	if isForceStr != "" {
		updates["IsForce"] = isForceStr == "true"
	}
	if statusStr != "" {
		s, _ := strconv.Atoi(statusStr)
		updates["Status"] = s
	}
	// download_url：用 GetPostForm 区分"未传"和"传空串（清空外链）"
	if vals, ok := c.GetPostFormArray("download_url"); ok {
		updates["DownloadURL"] = vals[0]
	}

	file, err := c.FormFile("file")
	if err == nil {
		dir := "uploads/releases"
		os.MkdirAll(dir, 0755)
		// multipart 文件名客户端可控，可能含 ../ 路径穿越，必须取 Base
		filename := fmt.Sprintf("%s_%s", uuid.New().String(), filepath.Base(file.Filename))
		filePath := filepath.Join(dir, filename)
		if err := c.SaveUploadedFile(file, filePath); err != nil {
			log.Printf("更新版本保存文件失败: %v", err)
		} else {
			updates["FilePath"] = filePath
			updates["FileSize"] = file.Size
		}
	}

	if len(updates) > 0 {
		services.UpdateAppVersionByID(uint(id), updates)
	}

	utils.SuccessMsg(c, "更新成功")
}

func (h *UpdateHandler) DeleteVersion(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	if v, err := services.FindAppVersionByID(uint(id)); err == nil && v != nil {
		os.Remove(v.FilePath)
	}

	services.DeleteAppVersionByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}

// isSafeDownloadURL 校验外部下载链接是否安全：
// - 必须是 http/https 协议
// - 主机名不能是内网地址或 localhost（防止 SSRF / 开放重定向到内网）
func isSafeDownloadURL(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return false
	}
	host := u.Hostname()
	if host == "" {
		return false
	}
	// 拒绝 localhost
	if host == "localhost" || host == "::1" {
		return false
	}
	// 解析 IP 地址，检查是否为内网
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
			return false
		}
	}
	return true
}
