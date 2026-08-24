package handlers

import (
	"strconv"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type NetworkAdminHandler struct{}

var netAdminAudit = services.NewAuditService()

// countByStatusAgents 统计 NetworkAgent 各状态记录数。
func countByStatusAgents() (gin.H, error) {
	counts, err := services.NetworkAgentStatusCounts()
	if err != nil {
		return nil, err
	}
	return gin.H{
		"pending":    counts["pending"],
		"approved":   counts["approved"],
		"rejected":   counts["rejected"],
		"taken_down": counts["taken_down"],
	}, nil
}

// countByStatusGroups 统计 NetworkGroup 各状态记录数。
func countByStatusGroups() (gin.H, error) {
	counts, err := services.NetworkGroupStatusCounts()
	if err != nil {
		return nil, err
	}
	return gin.H{
		"pending":    counts["pending"],
		"approved":   counts["approved"],
		"rejected":   counts["rejected"],
		"taken_down": counts["taken_down"],
	}, nil
}

// GET /api/v1/admin/network/agents — 管理端智能体列表（所有状态）
func (h *NetworkAdminHandler) ListAgents(c *gin.Context) {
	status := strings.TrimSpace(c.Query("status"))
	q := strings.TrimSpace(c.Query("q"))
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	offset := (page - 1) * pageSize
	agents, total, err := services.AdminSearchNetworkAgents(status, q, offset, pageSize)
	if err != nil {
		utils.Internal(c, "查询智能体列表失败")
		return
	}

	counts, err := countByStatusAgents()
	if err != nil {
		utils.Internal(c, "统计智能体状态失败")
		return
	}

	list := make([]gin.H, 0, len(agents))
	for _, a := range agents {
		list = append(list, agentDetail(a))
	}

	utils.Success(c, gin.H{
		"list":   list,
		"total":  total,
		"counts": counts,
	})
}

// GET /api/v1/admin/network/agents/:id — 管理端详情
func (h *NetworkAdminHandler) AdminGetAgent(c *gin.Context) {
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

	utils.Success(c, agentDetail(*agent))
}

// POST /api/v1/admin/network/agents/:id/approve — 通过审核
func (h *NetworkAdminHandler) ApproveAgent(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint("user_id")
	now := time.Now()

	old := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		old = *a
	}

	services.UpdateNetworkAgentByID(uint(id), map[string]interface{}{
		"Status":       "approved",
		"RejectReason": "",
		"ReviewedAt":   now,
		"ReviewerID":   userID,
	})

	updated := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		updated = *a
	}
	netAdminAudit.Log(c, services.AuditActionApprove, services.AuditTargetAgent, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "agent", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, now,
	)

	utils.SuccessMsg(c, "已通过审核")
}

// POST /api/v1/admin/network/agents/:id/reject — 拒绝审核
func (h *NetworkAdminHandler) RejectAgent(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "拒绝原因必填")
		return
	}

	userID := c.GetUint("user_id")
	now := time.Now()

	old := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		old = *a
	}

	services.UpdateNetworkAgentByID(uint(id), map[string]interface{}{
		"Status":       "rejected",
		"RejectReason": req.Reason,
		"ReviewedAt":   now,
		"ReviewerID":   userID,
	})

	updated := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		updated = *a
	}
	netAdminAudit.Log(c, services.AuditActionReject, services.AuditTargetAgent, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "agent", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, now,
	)

	utils.SuccessMsg(c, "已拒绝")
}

// PUT /api/v1/admin/network/agents/:id — 管理员编辑（不可改核心内容）
func (h *NetworkAdminHandler) AdminEditAgent(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	var req struct {
		Name          *string   `json:"name"`
		Description   *string   `json:"description"`
		Tags          *[]string `json:"tags"`
		ForceTakeDown *bool     `json:"force_take_down"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		updates["Name"] = *req.Name
	}
	if req.Description != nil {
		updates["Description"] = *req.Description
	}
	if req.Tags != nil {
		tmp := models.NetworkAgent{}
		tmp.SetTags(*req.Tags)
		updates["Tags"] = tmp.Tags
	}
	if req.ForceTakeDown != nil && *req.ForceTakeDown {
		updates["Status"] = "taken_down"
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "没有需要更新的字段")
		return
	}

	old := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		old = *a
	}

	services.UpdateNetworkAgentByID(uint(id), updates)

	updated := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		updated = *a
	}

	action := services.AuditActionUpdate
	if req.ForceTakeDown != nil && *req.ForceTakeDown {
		action = services.AuditActionTakeDown
	}
	netAdminAudit.Log(c, action, services.AuditTargetAgent, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "agent", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, time.Now(),
	)

	utils.SuccessMsg(c, "更新成功")
}

// DELETE /api/v1/admin/network/agents/:id — 物理删除
func (h *NetworkAdminHandler) AdminDeleteAgent(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	old := models.NetworkAgent{}
	if a, err := services.FindNetworkAgentByID(uint(id)); err == nil && a != nil {
		old = *a
	}

	services.DeleteNetworkAgentByID(uint(id))
	netAdminAudit.Log(c, services.AuditActionDelete, services.AuditTargetAgent, strconv.FormatUint(id, 10), old, nil)
	services.PublishNetworkReviewStatus(
		old.UploaderID, "agent", old.ID, "deleted", "",
		old.Version, old.Status, time.Now(),
	)

	utils.SuccessMsg(c, "已删除")
}

// GET /api/v1/admin/network/groups — 管理端群聊列表（所有状态）
func (h *NetworkAdminHandler) ListGroups(c *gin.Context) {
	status := strings.TrimSpace(c.Query("status"))
	q := strings.TrimSpace(c.Query("q"))
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	offset := (page - 1) * pageSize
	groups, total, err := services.AdminSearchNetworkGroups(status, q, offset, pageSize)
	if err != nil {
		utils.Internal(c, "查询群聊列表失败")
		return
	}

	counts, err := countByStatusGroups()
	if err != nil {
		utils.Internal(c, "统计群聊状态失败")
		return
	}

	list := make([]gin.H, 0, len(groups))
	for _, g := range groups {
		list = append(list, groupDetail(g))
	}

	utils.Success(c, gin.H{
		"list":   list,
		"total":  total,
		"counts": counts,
	})
}

// GET /api/v1/admin/network/groups/:id — 管理端群聊详情
func (h *NetworkAdminHandler) AdminGetGroup(c *gin.Context) {
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

	utils.Success(c, groupDetail(*group))
}

// POST /api/v1/admin/network/groups/:id/approve — 通过群聊审核
func (h *NetworkAdminHandler) ApproveGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint("user_id")
	now := time.Now()

	old := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		old = *g
	}

	services.UpdateNetworkGroupByID(uint(id), map[string]interface{}{
		"Status":       "approved",
		"RejectReason": "",
		"ReviewedAt":   now,
		"ReviewerID":   userID,
	})

	updated := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		updated = *g
	}
	netAdminAudit.Log(c, services.AuditActionApprove, services.AuditTargetGroup, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "group", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, now,
	)

	utils.SuccessMsg(c, "已通过审核")
}

// POST /api/v1/admin/network/groups/:id/reject — 拒绝群聊审核
func (h *NetworkAdminHandler) RejectGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "拒绝原因必填")
		return
	}

	userID := c.GetUint("user_id")
	now := time.Now()

	old := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		old = *g
	}

	services.UpdateNetworkGroupByID(uint(id), map[string]interface{}{
		"Status":       "rejected",
		"RejectReason": req.Reason,
		"ReviewedAt":   now,
		"ReviewerID":   userID,
	})

	updated := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		updated = *g
	}
	netAdminAudit.Log(c, services.AuditActionReject, services.AuditTargetGroup, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "group", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, now,
	)

	utils.SuccessMsg(c, "已拒绝")
}

// PUT /api/v1/admin/network/groups/:id — 管理员编辑群聊
func (h *NetworkAdminHandler) AdminEditGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	var req struct {
		Name          *string   `json:"name"`
		Description   *string   `json:"description"`
		Tags          *[]string `json:"tags"`
		ForceTakeDown *bool     `json:"force_take_down"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		updates["Name"] = *req.Name
	}
	if req.Description != nil {
		updates["Description"] = *req.Description
	}
	if req.Tags != nil {
		tmp := models.NetworkGroup{}
		tmp.SetTags(*req.Tags)
		updates["Tags"] = tmp.Tags
	}
	if req.ForceTakeDown != nil && *req.ForceTakeDown {
		updates["Status"] = "taken_down"
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "没有需要更新的字段")
		return
	}

	old := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		old = *g
	}

	services.UpdateNetworkGroupByID(uint(id), updates)

	updated := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		updated = *g
	}

	action := services.AuditActionUpdate
	if req.ForceTakeDown != nil && *req.ForceTakeDown {
		action = services.AuditActionTakeDown
	}
	netAdminAudit.Log(c, action, services.AuditTargetGroup, strconv.FormatUint(id, 10), old, updated)
	services.PublishNetworkReviewStatus(
		updated.UploaderID, "group", updated.ID, updated.Status,
		updated.RejectReason, updated.Version, old.Status, time.Now(),
	)

	utils.SuccessMsg(c, "更新成功")
}

// DELETE /api/v1/admin/network/groups/:id — 物理删除群聊
func (h *NetworkAdminHandler) AdminDeleteGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	old := models.NetworkGroup{}
	if g, err := services.FindNetworkGroupByID(uint(id)); err == nil && g != nil {
		old = *g
	}

	services.DeleteNetworkGroupByID(uint(id))
	netAdminAudit.Log(c, services.AuditActionDelete, services.AuditTargetGroup, strconv.FormatUint(id, 10), old, nil)
	services.PublishNetworkReviewStatus(
		old.UploaderID, "group", old.ID, "deleted", "",
		old.Version, old.Status, time.Now(),
	)

	utils.SuccessMsg(c, "已删除")
}

// GET /api/v1/admin/network/preset-tags — 获取预设标签
func (h *NetworkAdminHandler) GetPresetTags(c *gin.Context) {
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

// PUT /api/v1/admin/network/preset-tags — 更新预设标签
func (h *NetworkAdminHandler) UpdatePresetTags(c *gin.Context) {
	var req struct {
		Tags []string `json:"tags"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	_ = services.SaveSystemConfig("network_preset_tags", strings.Join(req.Tags, ","), "网络市场预设标签")
	utils.SuccessMsg(c, "标签保存成功")
}
