package handlers

import (
	"fmt"
	"html"
	"log"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type PaymentHandler struct {
	paymentService *services.PaymentService
}

func NewPaymentHandler() *PaymentHandler {
	return &PaymentHandler{paymentService: &services.PaymentService{}}
}

type SubscribeRequest struct {
	PlanID      uint   `json:"plan_id" binding:"required"`
	PaymentType string `json:"payment_type" binding:"required"`
}

type ZeroDropRequest struct {
	Amount      float64 `json:"amount" binding:"required,gt=0"`
	PaymentType string  `json:"payment_type" binding:"required"`
}

func (h *PaymentHandler) GetPlans(c *gin.Context) {
	plans := services.ListSubscriptionPlans()

	var result []gin.H
	for _, p := range plans {
		if p.Status != 1 {
			continue
		}
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

func (h *PaymentHandler) Subscribe(c *gin.Context) {
	if !isProviderActive("easypay") {
		utils.BadRequest(c, utils.T(c, "err.payment.provider_not_easypay"))
		return
	}

	var req SubscribeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	validTypes := map[string]bool{"alipay": true, "wxpay": true, "qqpay": true, "tenpay": true}
	if !validTypes[req.PaymentType] {
		utils.BadRequest(c, utils.T(c, "err.payment.type_unsupported"))
		return
	}

	userID := c.GetUint("user_id")
	username := ""
	if u, err := services.FindUserByID(userID); err == nil && u != nil {
		username = u.Username
	}

	orderNo, payURL, amount, name, pid, sign, err := h.paymentService.CreateSubscribeOrder(userID, username, req.PlanID, req.PaymentType)
	if err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	utils.Success(c, gin.H{
		"order_no":     orderNo,
		"pay_url":      payURL,
		"amount":       fmt.Sprintf("%.2f", amount),
		"name":         name,
		"pid":          pid,
		"payment_type": req.PaymentType,
		"sign":         sign,
	})
}

func (h *PaymentHandler) ZeroDrop(c *gin.Context) {
	utils.BadRequest(c, utils.T(c, "err.payment.topup_offline"))
	return
}

func (h *PaymentHandler) Notify(c *gin.Context) {
	params := make(map[string]string)
	for k, v := range c.Request.URL.Query() {
		params[k] = v[0]
	}
	if len(params) == 0 {
		c.Request.ParseForm()
		for k, v := range c.Request.PostForm {
			params[k] = v[0]
		}
	}

	if err := h.paymentService.HandleNotify(params); err != nil {
		log.Printf("[支付] 回调处理失败: %v", err)
		c.String(200, "fail")
		return
	}

	c.String(200, "success")
}

func (h *PaymentHandler) Return(c *gin.Context) {
	params := make(map[string]string)
	for k, v := range c.Request.URL.Query() {
		params[k] = v[0]
	}

	tradeStatus := params["trade_status"]
	// 用户可控参数必须 HTML 转义后再拼接，防止反射型 XSS
	orderNo := html.EscapeString(params["out_trade_no"])
	money := html.EscapeString(params["money"])
	name := html.EscapeString(params["name"])

	statusIcon := "&#10060;"
	statusText := utils.T(c, "ok.payment.failed")
	statusColor := "#e74c3c"
	guideText := utils.T(c, "ok.payment.failed_guide")

	if tradeStatus == "TRADE_SUCCESS" {
		statusIcon = "&#9989;"
		statusText = utils.T(c, "ok.payment.success")
		statusColor = "#27ae60"
		guideText = utils.T(c, "ok.payment.success_guide")
	}

	pageLang := utils.ResolveLang(c)
	closeText := utils.T(c, "ok.payment.close_page")
	orderLabel := utils.T(c, "ok.payment.order_label")
	goodsLabel := utils.T(c, "ok.payment.goods_label")
	amountLabel := utils.T(c, "ok.payment.amount_label")
	titleText := utils.T(c, "ok.payment.page_title")

	page := fmt.Sprintf(`<!DOCTYPE html>
<html lang="%s">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s - AIchat</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f5f7;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#fff;border-radius:16px;box-shadow:0 2px 20px rgba(0,0,0,.08);padding:40px 32px;text-align:center;max-width:380px;width:90%%}
.icon{font-size:48px;margin-bottom:16px}
.status{font-size:22px;font-weight:700;margin-bottom:8px;color:%s}
.detail{font-size:14px;color:#666;line-height:1.8;margin-bottom:20px}
.detail span{color:#333;font-weight:500}
.btn{display:inline-block;background:#4A6CF7;color:#fff;border:none;padding:12px 32px;border-radius:8px;font-size:15px;cursor:pointer;text-decoration:none}
.btn:hover{background:#3b5de7}
</style>
</head>
<body>
<div class="card">
<div class="icon">%s</div>
<div class="status">%s</div>
<div class="detail">
	%s: <span>%s</span><br>
	%s: <span>%s</span><br>
	%s: <span>&yen;%s</span>
</div>
<p style="font-size:13px;color:#999;margin-bottom:20px">%s</p>
<a class="btn" href="javascript:window.close()">%s</a>
</div>
</body>
</html>`, pageLang, titleText, statusColor, statusIcon, statusText, orderLabel, orderNo, goodsLabel, name, amountLabel, money, guideText, closeText)

	c.Header("Content-Type", "text/html; charset=utf-8")
	// 页面无脚本需求：CSP 禁一切脚本/外部资源，仅允许内联样式，兜底防 XSS
	c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
	c.String(200, page)
}

func (h *PaymentHandler) GetOrderStatus(c *gin.Context) {
	orderNo := c.Param("orderNo")

	order, err := services.FindPaymentOrderByOrderNo(orderNo)
	if err != nil || order == nil {
		utils.BadRequest(c, utils.T(c, "err.payment.order_not_found"))
		return
	}

	userID := c.GetUint("user_id")
	if order.UserID != userID {
		utils.Forbidden(c, utils.T(c, "err.payment.order_forbidden"))
		return
	}

	if order.Status == "pending" {
		if err := h.paymentService.CheckAndActivateOrder(orderNo); err != nil {
			log.Printf("[支付] 主动确认订单 %s 失败: %v", orderNo, err)
		}
		// Re-read to get updated status
		if refreshed, err := services.FindPaymentOrderByOrderNo(orderNo); err == nil && refreshed != nil {
			order = refreshed
		}
	}

	var paidAt string
	if order.PaidAt != nil {
		paidAt = order.PaidAt.Format(time.RFC3339)
	}

	utils.Success(c, gin.H{
		"order_no":  order.OrderNo,
		"type":      order.Type,
		"status":    order.Status,
		"amount":    order.Amount,
		"plan_name": order.PlanName,
		"paid_at":   paidAt,
		"trade_no":  order.TradeNo,
	})
}

func (h *PaymentHandler) GetUserSubscription(c *gin.Context) {
	userID := c.GetUint("user_id")
	today := utils.TodayCN()

	activeSubscriptions := services.ActiveSubscriptionsForUser(userID)
	planMap := make(map[uint]models.SubscriptionPlan, len(activeSubscriptions))
	for _, subscription := range activeSubscriptions {
		if _, loaded := planMap[subscription.PlanID]; loaded {
			continue
		}
		if plan, err := services.FindSubscriptionPlanByID(subscription.PlanID); err == nil && plan != nil {
			planMap[subscription.PlanID] = *plan
		}
	}

	var user models.User
	if u, err := services.FindUserByID(userID); err == nil && u != nil {
		user = *u
	}

	subUsed := user.SubscriptionQuotaUsed
	if user.QuotaResetDate != today {
		subUsed = 0
	}
	totalSubQuota := 0.0
	for _, subscription := range activeSubscriptions {
		totalSubQuota += subscription.DailyQuota
	}
	totalQuotaLeft := totalSubQuota - subUsed
	if totalQuotaLeft < 0 {
		totalQuotaLeft = 0
	}

	var active []gin.H
	for _, s := range activeSubscriptions {
		plan, hasPlan := planMap[s.PlanID]

		active = append(active, gin.H{
			"id":          s.ID,
			"plan_id":     s.PlanID,
			"plan_name":   s.PlanName,
			"daily_quota": s.DailyQuota,
			"started_at":  s.StartedAt,
			"expires_at":  s.ExpiresAt,
			"allow_sync":  hasPlan && plan.AllowSync,
		})
	}

	utils.Success(c, gin.H{
		"subscriptions":    active,
		"total_quota_left": totalQuotaLeft,
	})
}

func isProviderActive(expected string) bool {
	sc, err := services.FindSystemConfig("payment_provider")
	if err == nil && sc != nil {
		return sc.Value == expected
	}
	return expected == "easypay"
}
