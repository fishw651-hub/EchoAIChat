package handlers

import (
	"sort"
	"strconv"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type NetworkAgentHandler struct{}

const (
	minAgentResponseLength     = 50
	maxAgentResponseLength     = 800
	defaultAgentResponseLength = 300
)

func normalizeAgentResponseLength(value int) int {
	if value == 0 {
		return defaultAgentResponseLength
	}
	if value < minAgentResponseLength {
		return minAgentResponseLength
	}
	if value > maxAgentResponseLength {
		return maxAgentResponseLength
	}
	return value
}

type networkReviewStatus struct {
	ResourceType string     `json:"resource_type"`
	ID           uint       `json:"id"`
	Name         string     `json:"name"`
	Status       string     `json:"status"`
	RejectReason string     `json:"reject_reason"`
	Version      int        `json:"version"`
	ReviewedAt   *time.Time `json:"reviewed_at"`
	UpdatedAt    time.Time  `json:"-"`
}

var editAgentLocks = utils.NewStripedLock()

// agentSummary 返回精简视图（不含加密字段 Persona/OpeningLine/Worldview）。
func agentSummary(a models.NetworkAgent) gin.H {
	return gin.H{
		"id":                  a.ID,
		"uploader_name":       a.UploaderName,
		"name":                a.Name,
		"gender":              a.Gender,
		"description":         a.Description,
		"max_response_length": normalizeAgentResponseLength(a.MaxResponseLength),
		"avatar_color":        a.AvatarColor,
		"avatar_path":         a.AvatarPath,
		"chat_background":     a.ChatBackground,
		"tags":                a.GetTags(),
		"status":              a.Status,
		"version":             a.Version,
		"download_count":      a.DownloadCount,
		"created_at":          a.CreatedAt,
		"updated_at":          a.UpdatedAt,
	}
}

// agentDetail 返回完整视图（解密后的 Persona/OpeningLine/Worldview）。
func agentDetail(a models.NetworkAgent) gin.H {
	return gin.H{
		"id":                  a.ID,
		"uploader_id":         a.UploaderID,
		"uploader_name":       a.UploaderName,
		"name":                a.Name,
		"gender":              a.Gender,
		"description":         a.Description,
		"persona":             decryptField(a.Persona),
		"opening_line":        decryptField(a.OpeningLine),
		"worldview":           decryptField(a.Worldview),
		"max_response_length": normalizeAgentResponseLength(a.MaxResponseLength),
		"avatar_color":        a.AvatarColor,
		"avatar_path":         a.AvatarPath,
		"chat_background":     a.ChatBackground,
		"tags":                a.GetTags(),
		"status":              a.Status,
		"reject_reason":       a.RejectReason,
		"version":             a.Version,
		"download_count":      a.DownloadCount,
		"created_at":          a.CreatedAt,
		"updated_at":          a.UpdatedAt,
		"reviewed_at":         a.ReviewedAt,
		"reviewer_id":         a.ReviewerID,
		"ai_review_status":    a.AiReviewStatus,
		"ai_review_reason":    a.AiReviewReason,
		"ai_reviewed_at":      a.AiReviewedAt,
	}
}

// GET /api/v1/network/agents — 公开市场列表（仅 approved）
func (h *NetworkAgentHandler) ListAgents(c *gin.Context) {
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
	agents, total, err := services.PublicSearchNetworkAgents(q, tags, order, offset, pageSize)
	if err != nil {
		utils.Internal(c, "查询智能体列表失败")
		return
	}

	list := make([]gin.H, 0, len(agents))
	for _, a := range agents {
		list = append(list, agentSummary(a))
	}

	utils.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GET /api/v1/network/agents/:id — 详情（不增加下载量）
func (h *NetworkAgentHandler) GetDetail(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	agent, err := services.FindNetworkAgentByID(uint(id))
	if err != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	if agent.Status != "approved" {
		utils.NotFound(c, "智能体不存在")
		return
	}

	utils.Success(c, agentDetail(*agent))
}

// POST /api/v1/network/agents/:id/download — 下载（原子增加下载量）
func (h *NetworkAgentHandler) Download(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	agent, err := services.FindNetworkAgentByID(uint(id))
	if err != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	if agent.Status != "approved" {
		utils.NotFound(c, "智能体不存在")
		return
	}

	// 原子自增，避免旧代码 read-modify-write 竞态
	services.IncrementNetworkAgentDownloads(uint(id))

	utils.Success(c, gin.H{
		"type":    "agent",
		"version": agent.Version,
		"agent":   agentDetail(*agent),
	})
}

// GET /api/v1/network/my/agents — 我上传的智能体（全部状态）
func (h *NetworkAgentHandler) ListMyUploads(c *gin.Context) {
	userID := c.GetUint("user_id")

	agents := services.ListNetworkAgentsByUploader(userID)

	list := make([]gin.H, 0, len(agents))
	for _, a := range agents {
		list = append(list, agentDetail(a))
	}

	utils.Success(c, list)
}

// GET /api/v1/network/my/review-statuses — 当前用户智能体与群聊的精简审核状态。
func (h *NetworkAgentHandler) ListMyReviewStatuses(c *gin.Context) {
	userID := c.GetUint("user_id")
	agents := services.ListNetworkAgentsByUploader(userID)
	groups := services.ListNetworkGroupsByUploader(userID)

	statuses := make([]networkReviewStatus, 0, len(agents)+len(groups))
	for _, agent := range agents {
		statuses = append(statuses, networkReviewStatus{
			ResourceType: "agent",
			ID:           agent.ID,
			Name:         agent.Name,
			Status:       agent.Status,
			RejectReason: agent.RejectReason,
			Version:      agent.Version,
			ReviewedAt:   agent.ReviewedAt,
			UpdatedAt:    agent.UpdatedAt,
		})
	}
	for _, group := range groups {
		statuses = append(statuses, networkReviewStatus{
			ResourceType: "group",
			ID:           group.ID,
			Name:         group.Name,
			Status:       group.Status,
			RejectReason: group.RejectReason,
			Version:      group.Version,
			ReviewedAt:   group.ReviewedAt,
			UpdatedAt:    group.UpdatedAt,
		})
	}
	sort.SliceStable(statuses, func(i, j int) bool {
		return statuses[i].UpdatedAt.After(statuses[j].UpdatedAt)
	})
	utils.Success(c, statuses)
}

// POST /api/v1/network/agents — 上传新智能体
func (h *NetworkAgentHandler) Upload(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req struct {
		Name              string   `json:"name" binding:"required"`
		Gender            string   `json:"gender"`
		Description       string   `json:"description"`
		Persona           string   `json:"persona"`
		OpeningLine       string   `json:"opening_line"`
		Worldview         string   `json:"worldview"`
		MaxResponseLength int      `json:"max_response_length"`
		AvatarColor       int      `json:"avatar_color"`
		AvatarPath        string   `json:"avatar_path"`
		Avatar            string   `json:"avatar"` // data:image/...;base64,... 优先于 avatar_path
		ChatBackground    string   `json:"chat_background"`
		Tags              []string `json:"tags"`
		SourceKind        string   `json:"source_kind"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if strings.TrimSpace(req.OpeningLine) == "" {
		utils.BadRequest(c, "开场白是必须书写的")
		return
	}
	if req.SourceKind == "downloaded" {
		utils.Forbidden(c, "下载的作品不能上传")
		return
	}

	// 查上传者用户名
	uploaderName := ""
	if uploader, err := services.FindUserByID(userID); err == nil && uploader != nil {
		uploaderName = uploader.Username
	}

	// 头像：优先处理 base64（保存为文件得到相对路径），否则用客户端传来的 avatar_path
	avatarPath := req.AvatarPath
	if req.Avatar != "" {
		if saved, err := services.SaveBase64Image(req.Avatar, "network_agents"); err == nil && saved != "" {
			avatarPath = saved
		}
	}

	// chat_background: 若为 base64 也保存为文件
	chatBg := req.ChatBackground
	if strings.HasPrefix(chatBg, "data:image/") {
		if saved, err := services.SaveBase64Image(chatBg, "network_agents_bg"); err == nil && saved != "" {
			chatBg = saved
		}
	}

	agent := models.NetworkAgent{
		UploaderID:        userID,
		UploaderName:      uploaderName,
		Name:              req.Name,
		Gender:            req.Gender,
		Description:       req.Description,
		Persona:           encryptField(req.Persona),
		OpeningLine:       encryptField(req.OpeningLine),
		Worldview:         encryptField(req.Worldview),
		MaxResponseLength: normalizeAgentResponseLength(req.MaxResponseLength),
		AvatarColor:       req.AvatarColor,
		AvatarPath:        avatarPath,
		ChatBackground:    chatBg,
		Status:            "pending",
		Version:           1,
	}
	agent.SetTags(req.Tags)

	if err := services.InsertNetworkAgent(&agent); err != nil {
		utils.Internal(c, "上传失败")
		return
	}
	services.PublishNetworkReviewStatus(
		agent.UploaderID, "agent", agent.ID, agent.Status, "",
		agent.Version, "", time.Now(),
	)

	TriggerAutoAiReviewAgent(agent.ID)

	utils.Success(c, agentDetail(agent))
}

// PUT /api/v1/network/agents/:id — 编辑（Status 重置为 pending，Version+1）
func (h *NetworkAgentHandler) Edit(c *gin.Context) {
	userID := c.GetUint("user_id")
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 加锁保护"读取Version → 计算Version+1 → 写入"流程，防止并发编辑导致 Version lost update
	unlock := editAgentLocks.LockUint(uint(id))
	defer unlock()

	agent, err := services.FindNetworkAgentByID(uint(id))
	if err != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	if agent.UploaderID != userID {
		utils.Forbidden(c, "无权修改该智能体")
		return
	}

	// 已下架内容不可编辑，需重新上传
	if agent.Status == "taken_down" {
		utils.BadRequest(c, "已下架内容不可编辑，请重新上传")
		return
	}

	var req struct {
		Name              *string   `json:"name"`
		Gender            *string   `json:"gender"`
		Description       *string   `json:"description"`
		Persona           *string   `json:"persona"`
		OpeningLine       *string   `json:"opening_line"`
		Worldview         *string   `json:"worldview"`
		MaxResponseLength *int      `json:"max_response_length"`
		AvatarColor       *int      `json:"avatar_color"`
		AvatarPath        *string   `json:"avatar_path"`
		Avatar            *string   `json:"avatar"` // data:image/...;base64,... 非空时保存为新文件
		ChatBackground    *string   `json:"chat_background"`
		Tags              *[]string `json:"tags"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if req.OpeningLine == nil || strings.TrimSpace(*req.OpeningLine) == "" {
		utils.BadRequest(c, "开场白是必须书写的")
		return
	}

	updates := map[string]interface{}{
		"Status":  "pending",
		"Version": agent.Version + 1,
	}
	if req.Name != nil {
		updates["Name"] = *req.Name
	}
	if req.Gender != nil {
		updates["Gender"] = *req.Gender
	}
	if req.Description != nil {
		updates["Description"] = *req.Description
	}
	if req.Persona != nil {
		updates["Persona"] = encryptField(*req.Persona)
	}
	if req.OpeningLine != nil {
		updates["OpeningLine"] = encryptField(*req.OpeningLine)
	}
	if req.Worldview != nil {
		updates["Worldview"] = encryptField(*req.Worldview)
	}
	if req.MaxResponseLength != nil {
		updates["MaxResponseLength"] = normalizeAgentResponseLength(*req.MaxResponseLength)
	}
	if req.AvatarColor != nil {
		updates["AvatarColor"] = *req.AvatarColor
	}
	// Avatar base64 非空时保存为新文件并更新 AvatarPath
	if req.Avatar != nil && *req.Avatar != "" {
		if saved, err := services.SaveBase64Image(*req.Avatar, "network_agents"); err == nil && saved != "" {
			updates["AvatarPath"] = saved
		}
	} else if req.AvatarPath != nil {
		updates["AvatarPath"] = *req.AvatarPath
	}
	if req.ChatBackground != nil {
		bg := *req.ChatBackground
		// 若为 base64 则保存为文件
		if strings.HasPrefix(bg, "data:image/") {
			if saved, err := services.SaveBase64Image(bg, "network_agents_bg"); err == nil && saved != "" {
				bg = saved
			}
		}
		updates["ChatBackground"] = bg
	}
	if req.Tags != nil {
		tmp := models.NetworkAgent{}
		tmp.SetTags(*req.Tags)
		updates["Tags"] = tmp.Tags
	}

	services.UpdateNetworkAgentByID(uint(id), updates)

	TriggerAutoAiReviewAgent(uint(id))

	updated, err := services.FindNetworkAgentByID(uint(id))
	if err != nil || updated == nil {
		utils.Internal(c, "读取更新结果失败")
		return
	}
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "agent", updated.ID, updated.Status, "",
		updated.Version, agent.Status, time.Now(),
	)
	utils.Success(c, agentDetail(*updated))
}

// DELETE /api/v1/network/agents/:id — 下架（软删除，Status=taken_down）
func (h *NetworkAgentHandler) TakeDown(c *gin.Context) {
	userID := c.GetUint("user_id")
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	agent, err := services.FindNetworkAgentByID(uint(id))
	if err != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	if agent.UploaderID != userID {
		utils.Forbidden(c, "无权下架该智能体")
		return
	}

	services.UpdateNetworkAgentByID(uint(id), map[string]interface{}{
		"Status": "taken_down",
	})
	services.PublishNetworkReviewStatus(
		agent.UploaderID, "agent", agent.ID, "taken_down", "",
		agent.Version, agent.Status, time.Now(),
	)
	utils.SuccessMsg(c, "已下架")
}

// GET /api/v1/network/tags — 公开预设标签
func (h *NetworkAgentHandler) GetPublicTags(c *gin.Context) {
	sc, err := services.FindSystemConfig("network_preset_tags")
	if err != nil || sc == nil {
		utils.Success(c, gin.H{"tags": []string{}})
		return
	}

	tags := []string{}
	for _, t := range strings.Split(sc.Value, ",") {
		t = strings.TrimSpace(t)
		if t != "" {
			tags = append(tags, t)
		}
	}
	utils.Success(c, gin.H{"tags": tags})
}
