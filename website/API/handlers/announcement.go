package handlers

import (
	"strconv"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

// AnnouncementHandler 弹窗公告：用户端拉取当前生效公告，管理端维护公告 CRUD
type AnnouncementHandler struct{}

type announcementRequest struct {
	Title     string `json:"title"`
	Content   string `json:"content"`
	Frequency string `json:"frequency"`
	Audience  string `json:"audience"`
	StartAt   string `json:"start_at"`
	EndAt     string `json:"end_at"`
	Enabled   *bool  `json:"enabled"`
}

// ListActive 用户端点：返回当前生效的公告列表（按 ID 倒序）。
// frequency 的展示节奏由客户端自行控制，本端点不做过滤。
func (h *AnnouncementHandler) ListActive(c *gin.Context) {
	active := services.ListActiveAnnouncements(time.Now())
	result := make([]gin.H, 0, len(active))
	for _, a := range active {
		result = append(result, gin.H{
			"id":         a.ID,
			"title":      a.Title,
			"content":    a.Content,
			"frequency":  a.Frequency,
			"audience":   a.Audience,
			"start_at":   a.StartAt,
			"end_at":     a.EndAt,
			"updated_at": a.UpdatedAt,
		})
	}
	utils.Success(c, result)
}

// AdminList 管理端点：全部公告（按 ID 倒序）
func (h *AnnouncementHandler) AdminList(c *gin.Context) {
	utils.Success(c, services.ListAnnouncements())
}

// Create 管理端点：创建公告（默认启用）
func (h *AnnouncementHandler) Create(c *gin.Context) {
	var req announcementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if _, _, err := services.ValidateAnnouncement(req.Title, req.Content, req.Frequency, req.Audience, req.StartAt, req.EndAt); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	a := models.Announcement{
		Title:     req.Title,
		Content:   req.Content,
		Frequency: req.Frequency,
		Audience:  req.Audience,
		StartAt:   req.StartAt,
		EndAt:     req.EndAt,
		Enabled:   enabled,
	}
	if err := services.CreateAnnouncement(&a); err != nil {
		utils.Internal(c, "创建失败")
		return
	}
	utils.Success(c, a)
}

// Update 管理端点：全量更新公告（校验规则与创建一致）
func (h *AnnouncementHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if _, ok := services.GetAnnouncement(uint(id)); !ok {
		utils.NotFound(c, "公告不存在")
		return
	}
	var req announcementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if _, _, err := services.ValidateAnnouncement(req.Title, req.Content, req.Frequency, req.Audience, req.StartAt, req.EndAt); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	if err := services.UpdateAnnouncement(&models.Announcement{
		ID:        uint(id),
		Title:     req.Title,
		Content:   req.Content,
		Frequency: req.Frequency,
		Audience:  req.Audience,
		StartAt:   req.StartAt,
		EndAt:     req.EndAt,
		Enabled:   enabled,
	}); err != nil {
		utils.Internal(c, "更新失败")
		return
	}
	utils.SuccessMsg(c, "更新成功")
}

// Delete 管理端点：删除公告
func (h *AnnouncementHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	services.DeleteAnnouncement(uint(id))
	utils.SuccessMsg(c, "删除成功")
}
