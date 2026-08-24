package handlers

import (
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"
)

type FeedbackHandler struct{}

// 反馈分类白名单
var feedbackCategories = map[string]bool{
	"feature":        true, // 新功能建议
	"feature_tweak":  true, // 功能修改建议
	"bug":            true, // BUG/漏洞
	"ui":             true, // 美化建议
	"pricing":        true, // 订阅付费调整建议
	"other":          true, // 其他建议
}

// Create 用户提交反馈
func (h *FeedbackHandler) Create(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req struct {
		Category string `json:"category" binding:"required"`
		Content  string `json:"content" binding:"required"`
		Contact  string `json:"contact" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "请填写完整信息")
		return
	}

	req.Category = strings.TrimSpace(req.Category)
	req.Content = strings.TrimSpace(req.Content)
	req.Contact = strings.TrimSpace(req.Contact)

	if !feedbackCategories[req.Category] {
		utils.BadRequest(c, "无效的反馈种类")
		return
	}
	if len(req.Content) < 5 {
		utils.BadRequest(c, "反馈内容至少 5 个字")
		return
	}
	if len(req.Content) > 2000 {
		utils.BadRequest(c, "反馈内容过长（最多 2000 字）")
		return
	}
	if len(req.Contact) > 100 {
		utils.BadRequest(c, "联系方式过长")
		return
	}

	// 取用户名（用于管理员后台显示）
	username := ""
	if user, err := services.FindUserByID(userID); err == nil && user != nil {
		username = user.Username
	}

	if err := services.InsertFeedback(&models.Feedback{
		UserID:   userID,
		Username: username,
		Category: req.Category,
		Content:  req.Content,
		Contact:  req.Contact,
		Status:   0,
	}); err != nil {
		utils.Internal(c, "提交失败")
		return
	}

	utils.SuccessMsg(c, "反馈已提交，感谢您的支持")
}

// ListMine 用户查看自己的反馈列表
func (h *FeedbackHandler) ListMine(c *gin.Context) {
	userID := c.GetUint("user_id")

	all := services.ListFeedback()

	var mine []models.Feedback
	for _, f := range all {
		if f.UserID == userID {
			mine = append(mine, f)
		}
	}
	utils.Success(c, mine)
}

// AdminList 管理员查看所有反馈（支持按分类/状态筛选 + 分页）
func (h *FeedbackHandler) AdminList(c *gin.Context) {
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")
	category := c.Query("category")
	statusStr := c.Query("status")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	all := services.ListFeedback()

	// 内存过滤
	var filtered []models.Feedback
	for _, f := range all {
		if category != "" && f.Category != category {
			continue
		}
		if statusStr != "" {
			if s, err := strconv.Atoi(statusStr); err == nil && f.Status != s {
				continue
			}
		}
		filtered = append(filtered, f)
	}

	total := len(filtered)
	offset := (page - 1) * pageSize
	end := offset + pageSize
	if offset > len(filtered) {
		offset = len(filtered)
	}
	if end > len(filtered) {
		end = len(filtered)
	}

	records := filtered[offset:end]
	if records == nil {
		records = []models.Feedback{}
	}

	utils.Success(c, gin.H{
		"total":     total,
		"page":      page,
		"page_size": pageSize,
		"records":   records,
	})
}

// AdminReply 管理员回复反馈（同时把状态置为已回复）
func (h *FeedbackHandler) AdminReply(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "无效的反馈 ID")
		return
	}

	var req struct {
		Reply  string `json:"reply" binding:"required"`
		Status *int   `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "请填写回复内容")
		return
	}
	if len(req.Reply) > 2000 {
		utils.BadRequest(c, "回复内容过长")
		return
	}

	updates := map[string]interface{}{
		"Reply":  strings.TrimSpace(req.Reply),
		"Status": 2, // 默认置为已回复
	}
	if req.Status != nil && *req.Status >= 0 && *req.Status <= 3 {
		updates["Status"] = *req.Status
	}

	services.UpdateFeedbackByID(uint(id), updates)
	utils.SuccessMsg(c, "回复成功")
}

// AdminDelete 管理员删除反馈
func (h *FeedbackHandler) AdminDelete(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "无效的反馈 ID")
		return
	}
	deleted, err := services.DeleteFeedbackByID(uint(id))
	if err != nil || !deleted {
		utils.NotFound(c, "反馈不存在")
		return
	}
	utils.SuccessMsg(c, "删除成功")
}
