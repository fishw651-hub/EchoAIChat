package services

import (
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

func SaveAvatar(file io.Reader, originalFilename string) (string, error) {
	ext := filepath.Ext(originalFilename)
	if ext == "" {
		ext = ".png"
	}

	filename := uuid.New().String() + ext

	uploadDir := "uploads/avatars"
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		return "", fmt.Errorf("创建上传目录失败: %w", err)
	}

	filePath := filepath.Join(uploadDir, filename)
	out, err := os.Create(filePath)
	if err != nil {
		return "", fmt.Errorf("创建文件失败: %w", err)
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		return "", fmt.Errorf("保存文件失败: %w", err)
	}

	return "/" + filepath.ToSlash(filePath), nil
}

// SaveBase64Image 保存 data:image/...;base64,... 格式的图片到指定子目录，
// 返回可被 /uploads 静态服务访问的相对路径（如 /uploads/network_agents/xxx.png）。
// 若 base64Data 非法或为空，返回空字符串和 nil error（调用方按需忽略）。
func SaveBase64Image(base64Data, subdir string) (string, error) {
	if !strings.HasPrefix(base64Data, "data:image/") {
		return "", nil
	}
	parts := strings.SplitN(base64Data, ";base64,", 2)
	if len(parts) != 2 {
		return "", nil
	}
	mime := strings.TrimPrefix(parts[0], "data:")
	ext := ".jpg"
	if strings.Contains(mime, "png") {
		ext = ".png"
	}

	filename := uuid.New().String() + ext
	uploadDir := filepath.Join("uploads", subdir)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		return "", fmt.Errorf("创建上传目录失败: %w", err)
	}

	data, err := base64.StdEncoding.DecodeString(parts[1])
	if err != nil {
		return "", fmt.Errorf("base64 解码失败: %w", err)
	}

	filePath := filepath.Join(uploadDir, filename)
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return "", fmt.Errorf("保存文件失败: %w", err)
	}

	return "/" + filepath.ToSlash(filePath), nil
}

func GenerateOrderNo(prefix string) string {
	return fmt.Sprintf("%s%s", prefix, time.Now().Format("20060102150405")+uuid.New().String()[:8])
}
