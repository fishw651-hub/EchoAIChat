package handlers

import (
	"strconv"
	"strings"

	"aichat-api/config"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type PlanHandler struct{}

func (h *PlanHandler) ListPlans(c *gin.Context) {
	plans := services.ListSubscriptionPlans()

	var result []gin.H
	for _, p := range plans {
		result = append(result, gin.H{
			"id":                     p.ID,
			"name":                   p.Name,
			"description":            p.Description,
			"price":                  p.Price,
			"daily_quota":            p.DailyQuota,
			"duration_days":          p.DurationDays,
			"ocr_daily_quota":        p.OcrDailyQuota,
			"real_reply_daily_quota": p.RealReplyDailyQuota,
			"allow_sync":             p.AllowSync,
			"status":                 p.Status,
			"sort_order":             p.SortOrder,
		})
	}

	utils.Success(c, result)
}

func (h *PlanHandler) CreatePlan(c *gin.Context) {
	var req struct {
		Name                string  `json:"name" binding:"required"`
		Description         string  `json:"description"`
		Price               float64 `json:"price" binding:"required"`
		DailyQuota          float64 `json:"daily_quota"`
		DurationDays        int     `json:"duration_days"`
		SortOrder           int     `json:"sort_order"`
		OcrDailyQuota       int     `json:"ocr_daily_quota"`
		RealReplyDailyQuota int     `json:"real_reply_daily_quota"`
		AllowSync           bool    `json:"allow_sync"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	if req.DurationDays <= 0 {
		req.DurationDays = 30
	}

	plan := models.SubscriptionPlan{
		Name:                req.Name,
		Description:         req.Description,
		Price:               req.Price,
		DailyQuota:          req.DailyQuota,
		DurationDays:        req.DurationDays,
		SortOrder:           req.SortOrder,
		OcrDailyQuota:       req.OcrDailyQuota,
		RealReplyDailyQuota: req.RealReplyDailyQuota,
		AllowSync:           req.AllowSync,
		Status:              1,
	}

	if err := services.InsertSubscriptionPlan(&plan); err != nil {
		utils.Internal(c, "创建失败")
		return
	}

	utils.Success(c, plan)
}

func (h *PlanHandler) UpdatePlan(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		Name                string  `json:"name"`
		Description         string  `json:"description"`
		Price               float64 `json:"price"`
		DailyQuota          float64 `json:"daily_quota"`
		DurationDays        int     `json:"duration_days"`
		SortOrder           int     `json:"sort_order"`
		OcrDailyQuota       *int    `json:"ocr_daily_quota"`
		RealReplyDailyQuota *int    `json:"real_reply_daily_quota"`
		AllowSync           *bool   `json:"allow_sync"`
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
	if req.Price > 0 {
		updates["Price"] = req.Price
	}
	if req.DailyQuota > 0 {
		updates["DailyQuota"] = req.DailyQuota
	}
	if req.DurationDays > 0 {
		updates["DurationDays"] = req.DurationDays
	}
	updates["SortOrder"] = req.SortOrder
	if req.OcrDailyQuota != nil {
		updates["OcrDailyQuota"] = *req.OcrDailyQuota
	}
	if req.RealReplyDailyQuota != nil {
		updates["RealReplyDailyQuota"] = *req.RealReplyDailyQuota
	}
	if req.AllowSync != nil {
		updates["AllowSync"] = *req.AllowSync
	}

	if len(updates) > 0 {
		services.UpdateSubscriptionPlanByID(uint(id), updates)
	}

	utils.SuccessMsg(c, "更新成功")
}

func (h *PlanHandler) DeletePlan(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	services.DeleteSubscriptionPlanByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}

func (h *PlanHandler) GetSystemConfig(c *gin.Context) {
	configs := services.ListSystemConfigs()

	result := gin.H{}
	for _, cfg := range configs {
		if cfg.Key == "easypay_key" || cfg.Key == "xiaoshiguang_key" {
			result[cfg.Key] = "****（已加密，请通过支付配置管理）"
			continue
		}
		result[cfg.Key] = cfg.Value
	}

	utils.Success(c, result)
}

func (h *PlanHandler) UpdateSystemConfig(c *gin.Context) {
	var req struct {
		Key   string `json:"key" binding:"required"`
		Value string `json:"value" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	if err := services.SaveSystemConfig(req.Key, req.Value, ""); err != nil {
		utils.Internal(c, "配置更新失败")
		return
	}

	utils.SuccessMsg(c, "配置更新成功")
}

func (h *PlanHandler) ListOrders(c *gin.Context) {
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")
	status := c.Query("status")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	allOrders := services.ListPaymentOrders()

	var filtered []models.PaymentOrder
	for _, o := range allOrders {
		if status != "" && o.Status != status {
			continue
		}
		filtered = append(filtered, o)
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

	utils.Success(c, gin.H{
		"total":     total,
		"page":      page,
		"page_size": pageSize,
		"records":   filtered[offset:end],
	})
}

// ======== 小时光支付配置 ========
func (h *PlanHandler) GetPaymentConfig(c *gin.Context) {
	pc := getPaymentConfigFromDB()
	utils.Success(c, pc)
}

func (h *PlanHandler) UpdatePaymentConfig(c *gin.Context) {
	var req struct {
		PID       string `json:"pid"`
		Key       string `json:"key"`
		APIURL    string `json:"api_url"`
		Sitename  string `json:"sitename"`
		ServerURL string `json:"server_url"`
		Provider  string `json:"provider"`
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

	if req.PID != "" {
		services.SaveSystemConfig("easypay_pid", req.PID, "易支付商户ID")
	}
	if req.Sitename != "" {
		services.SaveSystemConfig("easypay_sitename", req.Sitename, "易支付站点名称")
	}
	if req.ServerURL != "" {
		services.SaveSystemConfig("server_url", req.ServerURL, "服务器地址")
	}
	if req.APIURL != "" {
		services.SaveSystemConfig("payment_api_url", req.APIURL, "支付接口地址")
	}
	if req.Provider != "" {
		services.SaveSystemConfig("payment_provider", req.Provider, "支付渠道")
	}

	if req.Key != "" {
		encKey, err := services.Encrypt(req.Key, encBytes)
		if err != nil {
			utils.Internal(c, "密钥加密失败")
			return
		}
		services.SaveSystemConfig("easypay_key", encKey, "易支付商户密钥(已加密)")
	}

	utils.SuccessMsg(c, "支付配置保存成功")
}

func getPaymentConfigFromDB() gin.H {
	getVal := func(key string) string {
		if sc, err := services.FindSystemConfig(key); err == nil && sc != nil {
			return sc.Value
		}
		return ""
	}

	keyDisplay := "未配置"
	if getVal("easypay_key") != "" {
		keyDisplay = "****（已加密存储）"
	}

	serverURL := getVal("server_url")
	notifyURL := ""
	returnURL := ""
	if serverURL != "" {
		serverURL = strings.TrimRight(services.EnsureHTTP(serverURL), "/")
		notifyURL = serverURL + "/api/v1/payment/notify"
		returnURL = serverURL + "/api/v1/payment/return"
	}

	return gin.H{
		"pid":        getVal("easypay_pid"),
		"key":        keyDisplay,
		"has_key":    getVal("easypay_key") != "",
		"sitename":   getVal("easypay_sitename"),
		"server_url": getVal("server_url"),
		"notify_url": notifyURL,
		"return_url": returnURL,
		"api_url":    services.EnsureHTTP(getVal("payment_api_url")),
		"provider":   getVal("payment_provider"),
	}
}
