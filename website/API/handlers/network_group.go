package handlers

import (
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type NetworkGroupHandler struct{}

var editGroupLocks = utils.NewStripedLock()

// groupSummary 返回精简视图（不含加密字段 GroupPersona/WorldSetting/MembersJSON）。
func groupSummary(g models.NetworkGroup) gin.H {
	return gin.H{
		"id":                g.ID,
		"uploader_name":     g.UploaderName,
		"name":              g.Name,
		"description":       g.Description,
		"speech_mode":       g.SpeechMode,
		"is_simulator_mode": g.IsSimulatorMode,
		"avatar_color":      g.AvatarColor,
		"tags":              g.GetTags(),
		"status":            g.Status,
		"version":           g.Version,
		"download_count":    g.DownloadCount,
		"created_at":        g.CreatedAt,
		"updated_at":        g.UpdatedAt,
	}
}

// groupDetail 返回完整视图，并解密成员设定供详情页和下载页使用。
func groupDetail(g models.NetworkGroup) gin.H {
	// 模拟器群聊的开场角色固定是旁白。旧记录在缺少该字段时会被
	// encoding/json 反序列化为 0，不能把这个零值误当成首位成员。
	openingSpeakerIndex := g.OpeningSpeakerIndex
	if g.IsSimulatorMode {
		openingSpeakerIndex = -1
	}
	return gin.H{
		"id":                    g.ID,
		"uploader_id":           g.UploaderID,
		"uploader_name":         g.UploaderName,
		"name":                  g.Name,
		"description":           g.Description,
		"group_persona":         decryptField(g.GroupPersona),
		"opening_line":          decryptField(g.OpeningLine),
		"opening_speaker_index": openingSpeakerIndex,
		"world_setting":         decryptField(g.WorldSetting),
		"speech_mode":           g.SpeechMode,
		"is_simulator_mode":     g.IsSimulatorMode,
		"avatar_color":          g.AvatarColor,
		"tags":                  g.GetTags(),
		"status":                g.Status,
		"reject_reason":         g.RejectReason,
		"version":               g.Version,
		"download_count":        g.DownloadCount,
		"created_at":            g.CreatedAt,
		"updated_at":            g.UpdatedAt,
		"reviewed_at":           g.ReviewedAt,
		"reviewer_id":           g.ReviewerID,
		"ai_review_status":      g.AiReviewStatus,
		"ai_review_reason":      g.AiReviewReason,
		"ai_reviewed_at":        g.AiReviewedAt,
		"members":               groupMembers(g),
	}
}

// groupMembers 解密并解析 MembersJSON 字段为成员数组。
func groupMembers(g models.NetworkGroup) []models.NetworkMemberPayload {
	decrypted := decryptField(g.MembersJSON)
	if decrypted == "" {
		return []models.NetworkMemberPayload{}
	}
	var members []models.NetworkMemberPayload
	if err := json.Unmarshal([]byte(decrypted), &members); err != nil {
		return []models.NetworkMemberPayload{}
	}
	return members
}

// GET /api/v1/network/groups — 公开群聊列表（仅 approved）
func (h *NetworkGroupHandler) ListGroups(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	q := strings.TrimSpace(c.Query("q"))
	tagsParam := strings.TrimSpace(c.Query("tags"))
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")
	sort := c.DefaultQuery("sort", "newest")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var tags []string
	if tagsParam != "" {
		for _, t := range strings.Split(tagsParam, ",") {
			t = strings.TrimSpace(t)
			if t == "" {
				continue
			}
			tags = append(tags, t)
		}
	}

	order := "CreatedAt desc"
	if sort == "popular" {
		order = "DownloadCount desc"
	}

	offset := (page - 1) * pageSize
	groups, total, err := services.PublicSearchNetworkGroups(q, tags, order, offset, pageSize)
	if err != nil {
		utils.Internal(c, "查询群聊列表失败")
		return
	}

	list := make([]gin.H, 0, len(groups))
	for _, g := range groups {
		list = append(list, groupSummary(g))
	}

	utils.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GET /api/v1/network/groups/:id — 详情（不增加下载量）
func (h *NetworkGroupHandler) GetGroupDetail(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	group, err := services.FindNetworkGroupByID(uint(id))
	if err != nil || group == nil {
		utils.NotFound(c, "群聊不存在")
		return
	}

	if group.Status != "approved" {
		utils.NotFound(c, "群聊不存在")
		return
	}

	utils.Success(c, groupDetail(*group))
}

// POST /api/v1/network/groups/:id/download — 下载（原子增加下载量）
func (h *NetworkGroupHandler) DownloadGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	group, err := services.FindNetworkGroupByID(uint(id))
	if err != nil || group == nil {
		utils.NotFound(c, "群聊不存在")
		return
	}

	if group.Status != "approved" {
		utils.NotFound(c, "群聊不存在")
		return
	}

	// 原子自增，避免旧代码 read-modify-write 竞态
	services.IncrementNetworkGroupDownloads(uint(id))

	utils.Success(c, gin.H{
		"type":    "group",
		"version": group.Version,
		"group":   groupDetail(*group),
		"members": groupMembers(*group),
	})
}

// GET /api/v1/network/my/groups — 我上传的群聊（全部状态）
func (h *NetworkGroupHandler) ListMyGroups(c *gin.Context) {
	userID := c.GetUint("user_id")

	groups := services.ListNetworkGroupsByUploader(userID)

	list := make([]gin.H, 0, len(groups))
	for _, g := range groups {
		list = append(list, groupDetail(g))
	}

	utils.Success(c, list)
}

// POST /api/v1/network/groups — 上传新群聊
func (h *NetworkGroupHandler) UploadGroup(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req struct {
		Name                string                        `json:"name" binding:"required"`
		Description         string                        `json:"description"`
		GroupPersona        string                        `json:"group_persona"`
		OpeningLine         string                        `json:"opening_line"`
		OpeningSpeakerIndex *int                          `json:"opening_speaker_index"`
		WorldSetting        string                        `json:"world_setting"`
		SpeechMode          string                        `json:"speech_mode"`
		IsSimulatorMode     bool                          `json:"is_simulator_mode"`
		AvatarColor         int                           `json:"avatar_color"`
		Tags                []string                      `json:"tags"`
		Members             []models.NetworkMemberPayload `json:"members"`
		SourceKind          string                        `json:"source_kind"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	// 来源校验必须最先执行：下载的作品一律不能上传，
	// 否则其他字段校验会抢先返回 400，掩盖 403 语义。
	if req.SourceKind == "downloaded" {
		utils.Forbidden(c, "下载的作品不能上传")
		return
	}
	if strings.TrimSpace(req.OpeningLine) == "" {
		utils.BadRequest(c, "开场白是必须书写的")
		return
	}
	if !req.IsSimulatorMode && (req.OpeningSpeakerIndex == nil || *req.OpeningSpeakerIndex < 0 || *req.OpeningSpeakerIndex >= len(req.Members)) {
		utils.BadRequest(c, "普通群聊必须选择开场发言成员")
		return
	}

	// 查上传者用户名
	uploaderName := ""
	if uploader, err := services.FindUserByID(userID); err == nil && uploader != nil {
		uploaderName = uploader.Username
	}

	// 序列化 members 后加密
	membersJSON := "[]"
	if len(req.Members) > 0 {
		for i := range req.Members {
			req.Members[i].MaxResponseLength = normalizeAgentResponseLength(
				req.Members[i].MaxResponseLength,
			)
		}
		if data, err := json.Marshal(req.Members); err == nil {
			membersJSON = string(data)
		}
	}

	speechMode := req.SpeechMode
	if speechMode == "" {
		speechMode = "free"
	}

	group := models.NetworkGroup{
		UploaderID:   userID,
		UploaderName: uploaderName,
		Name:         req.Name,
		Description:  req.Description,
		GroupPersona: encryptField(req.GroupPersona),
		OpeningLine:  encryptField(req.OpeningLine),
		OpeningSpeakerIndex: func() int {
			if req.OpeningSpeakerIndex == nil {
				return -1
			}
			return *req.OpeningSpeakerIndex
		}(),
		WorldSetting:    encryptField(req.WorldSetting),
		SpeechMode:      speechMode,
		IsSimulatorMode: req.IsSimulatorMode,
		AvatarColor:     req.AvatarColor,
		MembersJSON:     encryptField(membersJSON),
		Status:          "pending",
		Version:         1,
	}
	group.SetTags(req.Tags)

	if err := services.InsertNetworkGroup(&group); err != nil {
		utils.Internal(c, "上传失败")
		return
	}
	services.PublishNetworkReviewStatus(
		group.UploaderID, "group", group.ID, group.Status, "",
		group.Version, "", time.Now(),
	)

	TriggerAutoAiReviewGroup(group.ID)

	utils.Success(c, groupDetail(group))
}

// PUT /api/v1/network/groups/:id — 编辑（Status 重置为 pending，Version+1）
func (h *NetworkGroupHandler) EditGroup(c *gin.Context) {
	userID := c.GetUint("user_id")
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 加锁保护"读取Version → 计算Version+1 → 写入"流程，防止并发编辑导致 Version lost update
	unlock := editGroupLocks.LockUint(uint(id))
	defer unlock()

	group, err := services.FindNetworkGroupByID(uint(id))
	if err != nil || group == nil {
		utils.NotFound(c, "群聊不存在")
		return
	}

	if group.UploaderID != userID {
		utils.Forbidden(c, "无权修改该群聊")
		return
	}

	// 已下架内容不可编辑，需重新上传
	if group.Status == "taken_down" {
		utils.BadRequest(c, "已下架内容不可编辑，请重新上传")
		return
	}

	var req struct {
		Name                *string                        `json:"name"`
		Description         *string                        `json:"description"`
		GroupPersona        *string                        `json:"group_persona"`
		OpeningLine         *string                        `json:"opening_line"`
		OpeningSpeakerIndex *int                           `json:"opening_speaker_index"`
		WorldSetting        *string                        `json:"world_setting"`
		SpeechMode          *string                        `json:"speech_mode"`
		IsSimulatorMode     *bool                          `json:"is_simulator_mode"`
		AvatarColor         *int                           `json:"avatar_color"`
		Tags                *[]string                      `json:"tags"`
		Members             *[]models.NetworkMemberPayload `json:"members"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if req.OpeningLine == nil || strings.TrimSpace(*req.OpeningLine) == "" {
		utils.BadRequest(c, "开场白是必须书写的")
		return
	}
	if req.OpeningSpeakerIndex == nil {
		utils.BadRequest(c, "必须提供开场发言成员")
		return
	}
	memberCount := len(groupMembers(*group))
	if req.Members != nil {
		memberCount = len(*req.Members)
	}
	isSimulator := group.IsSimulatorMode
	if req.IsSimulatorMode != nil {
		isSimulator = *req.IsSimulatorMode
	}
	if !isSimulator && (*req.OpeningSpeakerIndex < 0 || *req.OpeningSpeakerIndex >= memberCount) {
		utils.BadRequest(c, "普通群聊必须选择开场发言成员")
		return
	}

	updates := map[string]interface{}{
		"Status":  "pending",
		"Version": group.Version + 1,
	}
	if req.Name != nil {
		updates["Name"] = *req.Name
	}
	if req.Description != nil {
		updates["Description"] = *req.Description
	}
	if req.GroupPersona != nil {
		updates["GroupPersona"] = encryptField(*req.GroupPersona)
	}
	updates["OpeningLine"] = encryptField(*req.OpeningLine)
	updates["OpeningSpeakerIndex"] = *req.OpeningSpeakerIndex
	if req.WorldSetting != nil {
		updates["WorldSetting"] = encryptField(*req.WorldSetting)
	}
	if req.SpeechMode != nil {
		updates["SpeechMode"] = *req.SpeechMode
	}
	if req.IsSimulatorMode != nil {
		updates["IsSimulatorMode"] = *req.IsSimulatorMode
	}
	if req.AvatarColor != nil {
		updates["AvatarColor"] = *req.AvatarColor
	}
	if req.Tags != nil {
		tmp := models.NetworkGroup{}
		tmp.SetTags(*req.Tags)
		updates["Tags"] = tmp.Tags
	}
	if req.Members != nil {
		membersJSON := "[]"
		if len(*req.Members) > 0 {
			for i := range *req.Members {
				(*req.Members)[i].MaxResponseLength = normalizeAgentResponseLength(
					(*req.Members)[i].MaxResponseLength,
				)
			}
			if data, err := json.Marshal(*req.Members); err == nil {
				membersJSON = string(data)
			}
		}
		updates["MembersJSON"] = encryptField(membersJSON)
	}

	services.UpdateNetworkGroupByID(uint(id), updates)

	TriggerAutoAiReviewGroup(uint(id))

	updated, err := services.FindNetworkGroupByID(uint(id))
	if err != nil || updated == nil {
		utils.Internal(c, "读取更新结果失败")
		return
	}
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "group", updated.ID, updated.Status, "",
		updated.Version, group.Status, time.Now(),
	)
	utils.Success(c, groupDetail(*updated))
}

// DELETE /api/v1/network/groups/:id — 下架（软删除，Status=taken_down）
func (h *NetworkGroupHandler) TakeDownGroup(c *gin.Context) {
	userID := c.GetUint("user_id")
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	group, err := services.FindNetworkGroupByID(uint(id))
	if err != nil || group == nil {
		utils.NotFound(c, "群聊不存在")
		return
	}

	if group.UploaderID != userID {
		utils.Forbidden(c, "无权下架该群聊")
		return
	}

	services.UpdateNetworkGroupByID(uint(id), map[string]interface{}{
		"Status": "taken_down",
	})
	services.PublishNetworkReviewStatus(
		group.UploaderID, "group", group.ID, "taken_down", "",
		group.Version, group.Status, time.Now(),
	)
	utils.SuccessMsg(c, "已下架")
}
