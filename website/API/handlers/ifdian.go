package handlers

import (
	"encoding/json"
	"strconv"

	"aichat-api/config"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type IfdianHandler struct {
	svc *services.IfdianService
}

func NewIfdianHandler() *IfdianHandler {
	return &IfdianHandler{svc: &services.IfdianService{}}
}

// ======== 管理接口 ========

func (h *IfdianHandler) GetConfig(c *gin.Context) {
	getVal := func(key string) string {
		if sc, err := services.FindSystemConfig(key); err == nil && sc != nil {
			return sc.Value
		}
		return ""
	}

	utils.Success(c, gin.H{
		"user_id":   getVal("ifdian_user_id"),
		"has_token": getVal("ifdian_token") != "",
		"plan_ids":  getVal("ifdian_plan_ids"),
	})
}

func (h *IfdianHandler) SaveConfig(c *gin.Context) {
	var req struct {
		UserID  string `json:"user_id"`
		Token   string `json:"token"`
		PlanIDs string `json:"plan_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	encKeyStr := config.AppConfig.Encryption.Key
	if len(encKeyStr) < 32 {
		encKeyStr = encKeyStr + "00000000000000000000000000000000"
	}
	encBytes := []byte(encKeyStr[:32])

	if req.UserID != "" {
		services.SaveSystemConfig("ifdian_user_id", req.UserID, "爱发电开发者ID")
	}
	if req.Token != "" {
		encToken, err := services.Encrypt(req.Token, encBytes)
		if err != nil {
			utils.Internal(c, "Token加密失败")
			return
		}
		services.SaveSystemConfig("ifdian_token", encToken, "爱发电API Token(已加密)")
	}
	if req.PlanIDs != "" {
		services.SaveSystemConfig("ifdian_plan_ids", req.PlanIDs, "爱发电方案ID列表")
	}

	utils.SuccessMsg(c, "爱发电配置保存成功")
}

func (h *IfdianHandler) SyncPlans(c *gin.Context) {
	if err := h.svc.SyncPlansToDB(); err != nil {
		utils.Internal(c, "同步失败: "+err.Error())
		return
	}
	utils.SuccessMsg(c, "方案同步成功")
}

func (h *IfdianHandler) ListPlans(c *gin.Context) {
	plans := services.ListIfdianPlans()
	utils.Success(c, plans)
}

func (h *IfdianHandler) UpdateMapping(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		MappingType  string  `json:"mapping_type"`
		LocalPlanID  uint    `json:"local_plan_id"`
		Amount       float64 `json:"amount"`
		DailyQuota   float64 `json:"daily_quota"`
		DurationDays int     `json:"duration_days"`
		Status       *int    `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.MappingType != "" {
		updates["MappingType"] = req.MappingType
	}
	updates["LocalPlanID"] = req.LocalPlanID
	updates["Amount"] = req.Amount
	updates["DailyQuota"] = req.DailyQuota
	updates["DurationDays"] = req.DurationDays
	if req.Status != nil {
		updates["Status"] = *req.Status
	}

	services.UpdateIfdianPlanByID(uint(id), updates)
	utils.SuccessMsg(c, "映射更新成功")
}

func (h *IfdianHandler) ListRecords(c *gin.Context) {
	records := services.ListIfdianRecords()
	utils.Success(c, records)
}

// ======== 用户接口 ========

func (h *IfdianHandler) PublicPlans(c *gin.Context) {
	plans := services.ListIfdianPlans()

	var result []gin.H
	for _, p := range plans {
		if p.Status == 1 {
			result = append(result, gin.H{
				"ifdian_plan_id": p.IfdianPlanID,
				"name":           p.Name,
				"price":          p.Price,
				"plan_type":      p.PlanType,
				"mapping_type":   p.MappingType,
			})
		}
	}
	utils.Success(c, result)
}

func (h *IfdianHandler) Verify(c *gin.Context) {
	if !isProviderActive("ifdian") {
		utils.BadRequest(c, "当前支付渠道非爱发电，请在后台切换")
		return
	}

	var req struct {
		OutTradeNo string `json:"out_trade_no" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint("user_id")
	result, err := h.svc.VerifyAndGrant(userID, req.OutTradeNo)
	if err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	utils.Success(c, result)
}

func (h *IfdianHandler) Webhook(c *gin.Context) {
	// 爱发电 webhook 格式：外层包含 user_id / params(JSON 字符串) / ts / sign
	var req struct {
		UserID string `json:"user_id"`
		Params string `json:"params"`
		Ts     int64  `json:"ts"`
		Sign   string `json:"sign"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.String(200, "fail")
		return
	}

	// 签名校验：防止伪造请求注入垃圾数据
	if req.Sign == "" || req.Ts == 0 {
		c.String(400, "missing sign or ts")
		return
	}
	expectedSign := h.svc.BuildSign(req.Params, req.Ts)
	if expectedSign != req.Sign {
		c.String(400, "sign error")
		return
	}

	// 解析 params JSON 获取订单数据
	var orderData struct {
		OutTradeNo  string  `json:"out_trade_no"`
		PlanID      string  `json:"plan_id"`
		TotalAmount float64 `json:"total_amount"`
		Status      int     `json:"status"`
		UserID      string  `json:"user_id"`
	}
	if err := json.Unmarshal([]byte(req.Params), &orderData); err != nil {
		c.String(200, "fail")
		return
	}

	if orderData.Status != 2 {
		c.String(200, "ok")
		return
	}

	// 幂等性检查：使用 FindOne 替代遍历 FindAll，精确匹配已发放记录
	if existing, err := services.FindIfdianRecordByOutTradeNo(orderData.OutTradeNo); err != nil || existing != nil {
		c.String(200, "ok")
		return
	}

	plan, err := services.FindIfdianPlanByPlanID(orderData.PlanID)
	if err != nil || plan == nil || plan.MappingType == "" {
		c.String(200, "ok")
		return
	}

	record := models.IfdianRecord{
		IfdianUserID: orderData.UserID,
		OutTradeNo:   orderData.OutTradeNo,
		PlanID:       orderData.PlanID,
		PlanName:     plan.Name,
		Amount:       orderData.TotalAmount,
		MappingType:  plan.MappingType,
		Granted:      false,
	}
	services.InsertIfdianRecord(&record)

	c.String(200, "success")
}
