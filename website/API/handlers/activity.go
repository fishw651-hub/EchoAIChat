package handlers

import (
	"strconv"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type ActivityHandler struct{}

func (h *ActivityHandler) ListActive(c *gin.Context) {
	today := time.Now().Format("2006-01-02")

	all := services.ListActivities("")

	var result []gin.H
	for _, a := range all {
		if a.Status == 1 && a.StartedAt <= today && a.EndedAt >= today {
			result = append(result, gin.H{
				"id":          a.ID,
				"name":        a.Name,
				"description": a.Description,
				"type":        a.Type,
				"apply_scope": a.ApplyScope,
				"discount":    a.Discount,
				"started_at":  a.StartedAt,
				"ended_at":    a.EndedAt,
			})
		}
	}

	utils.Success(c, result)
}

func (h *ActivityHandler) AdminList(c *gin.Context) {
	all := services.ListActivities("ID desc")
	utils.Success(c, all)
}

func (h *ActivityHandler) Create(c *gin.Context) {
	var req struct {
		Name        string  `json:"name" binding:"required"`
		Description string  `json:"description"`
		Type        string  `json:"type" binding:"required"`
		ApplyScope  string  `json:"apply_scope" binding:"required"`
		Discount    float64 `json:"discount" binding:"required"`
		StartedAt   string  `json:"started_at" binding:"required"`
		EndedAt     string  `json:"ended_at" binding:"required"`
		Rules       []struct {
			ModelID                  string  `json:"model_id"`
			InputDiscount            float64 `json:"input_discount"`
			CacheHitDiscount         float64 `json:"cache_hit_discount"`
			OutputDiscount           float64 `json:"output_discount"`
			ThinkingInputDiscount    float64 `json:"thinking_input_discount"`
			ThinkingCacheHitDiscount float64 `json:"thinking_cache_hit_discount"`
			ThinkingOutputDiscount   float64 `json:"thinking_output_discount"`
		} `json:"rules"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	activity := models.Activity{
		Name:        req.Name,
		Description: req.Description,
		Type:        req.Type,
		ApplyScope:  req.ApplyScope,
		Discount:    req.Discount,
		StartedAt:   req.StartedAt,
		EndedAt:     req.EndedAt,
		Status:      1,
	}
	// 先插入新活动，失败不影响已有活动
	if err := services.InsertActivity(&activity); err != nil {
		utils.Internal(c, "创建失败")
		return
	}

	// 插入成功后再禁用同范围的其他已上架活动（排除新创建的）
	_ = services.DisableOtherActivitiesInScope(req.ApplyScope, activity.ID)

	if req.ApplyScope == "chat" && len(req.Rules) > 0 {
		for _, r := range req.Rules {
			services.InsertActivityModelRule(&models.ActivityModelRule{
				ActivityID:               activity.ID,
				ModelID:                  r.ModelID,
				InputDiscount:            r.InputDiscount,
				CacheHitDiscount:         r.CacheHitDiscount,
				OutputDiscount:           r.OutputDiscount,
				ThinkingInputDiscount:    r.ThinkingInputDiscount,
				ThinkingCacheHitDiscount: r.ThinkingCacheHitDiscount,
				ThinkingOutputDiscount:   r.ThinkingOutputDiscount,
			})
		}
	}

	utils.Success(c, activity)
}

func (h *ActivityHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		Name        string  `json:"name"`
		Description string  `json:"description"`
		Type        string  `json:"type"`
		ApplyScope  string  `json:"apply_scope"`
		Discount    float64 `json:"discount"`
		StartedAt   string  `json:"started_at"`
		EndedAt     string  `json:"ended_at"`
		Status      *int    `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != "" {
		updates["Name"] = req.Name
	}
	if req.Description != "" {
		updates["Description"] = req.Description
	}
	if req.Type != "" {
		updates["Type"] = req.Type
	}
	if req.ApplyScope != "" {
		updates["ApplyScope"] = req.ApplyScope
	}
	if req.Discount > 0 {
		updates["Discount"] = req.Discount
	}
	if req.StartedAt != "" {
		updates["StartedAt"] = req.StartedAt
	}
	if req.EndedAt != "" {
		updates["EndedAt"] = req.EndedAt
	}
	if req.Status != nil {
		updates["Status"] = *req.Status
	}

	if len(updates) > 0 {
		services.UpdateActivityByID(uint(id), updates)
	}

	utils.SuccessMsg(c, "更新成功")
}

func (h *ActivityHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	// 先删除关联的模型规则，避免产生孤儿记录
	for _, r := range services.ListActivityModelRules(uint(id)) {
		services.DeleteActivityModelRuleByID(r.ID)
	}
	services.DeleteActivityByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}

func (h *ActivityHandler) GetRules(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	rules := services.ListActivityModelRules(uint(id))

	var result []models.ActivityModelRule
	for _, r := range rules {
		if r.ActivityID == uint(id) {
			result = append(result, r)
		}
	}

	utils.Success(c, result)
}

func (h *ActivityHandler) UpdateRules(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req []struct {
		ModelID                  string  `json:"model_id"`
		InputDiscount            float64 `json:"input_discount"`
		CacheHitDiscount         float64 `json:"cache_hit_discount"`
		OutputDiscount           float64 `json:"output_discount"`
		ThinkingInputDiscount    float64 `json:"thinking_input_discount"`
		ThinkingCacheHitDiscount float64 `json:"thinking_cache_hit_discount"`
		ThinkingOutputDiscount   float64 `json:"thinking_output_discount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	for _, r := range services.ListActivityModelRules(uint(id)) {
		services.DeleteActivityModelRuleByID(r.ID)
	}

	for _, r := range req {
		services.InsertActivityModelRule(&models.ActivityModelRule{
			ActivityID:               uint(id),
			ModelID:                  r.ModelID,
			InputDiscount:            r.InputDiscount,
			CacheHitDiscount:         r.CacheHitDiscount,
			OutputDiscount:           r.OutputDiscount,
			ThinkingInputDiscount:    r.ThinkingInputDiscount,
			ThinkingCacheHitDiscount: r.ThinkingCacheHitDiscount,
			ThinkingOutputDiscount:   r.ThinkingOutputDiscount,
		})
	}

	utils.SuccessMsg(c, "规则更新成功")
}
