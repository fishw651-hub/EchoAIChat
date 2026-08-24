package services

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/url"
	"sort"
	"strings"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

type PaymentService struct{}

var activateLocks = utils.NewStripedLock()

type PaymentConfig struct {
	PID       string
	Key       string
	NotifyURL string
	ReturnURL string
	Sitename  string
}

func (s *PaymentService) getPaymentConfig() PaymentConfig {
	db := database.Get()
	cfg := runtimeEasyPay()

	pid := getConfigValueMigrate(db, "easypay_pid", "xiaoshiguang_pid", cfg.PID)
	sitename := getConfigValueMigrate(db, "easypay_sitename", "xiaoshiguang_sitename", cfg.Sitename)

	key := ""
	var sc models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", "easypay_key"), &sc) ||
		db.Register("SystemConfig").FindOne(database.FilterEq("Key", "xiaoshiguang_key"), &sc) {
		dec, err := DecryptWithConfiguredKeys(sc.Value)
		if err == nil {
			key = dec
		}
	}
	if key == "" {
		key = cfg.Key
	}

	serverURL := getConfigValueMigrate(db, "server_url", "site_url", runtimeServerURL())
	if serverURL == "" && runtimeServerURL() != "" {
		serverURL = runtimeServerURL()
	}
	serverURL = EnsureHTTP(serverURL)

	notifyURL := ""
	returnURL := ""
	if serverURL != "" {
		serverURL = strings.TrimRight(serverURL, "/")
		notifyURL = serverURL + "/api/v1/payment/notify"
		returnURL = serverURL + "/api/v1/payment/return"
	}

	return PaymentConfig{PID: pid, Key: key, NotifyURL: notifyURL, ReturnURL: returnURL, Sitename: sitename}
}

func getConfigValue(db *database.DB, key, fallback string) string {
	var sc models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", key), &sc) && sc.Value != "" {
		return sc.Value
	}
	return fallback
}

func getConfigValueMigrate(db *database.DB, newKey, oldKey, fallback string) string {
	var sc models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", newKey), &sc) && sc.Value != "" {
		return sc.Value
	}
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", oldKey), &sc) && sc.Value != "" {
		return sc.Value
	}
	return fallback
}

func EnsureHTTP(raw string) string {
	if raw == "" {
		return raw
	}
	if !strings.HasPrefix(raw, "http://") && !strings.HasPrefix(raw, "https://") {
		return "http://" + raw
	}
	return raw
}

func (s *PaymentService) BuildSign(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for k := range params {
		if k == "sign" || k == "sign_type" {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var builder strings.Builder
	for i, k := range keys {
		if i > 0 {
			builder.WriteString("&")
		}
		builder.WriteString(fmt.Sprintf("%s=%s", k, params[k]))
	}
	builder.WriteString(s.getPaymentConfig().Key)

	hash := md5.Sum([]byte(builder.String()))
	return fmt.Sprintf("%x", hash)
}

func (s *PaymentService) VerifySign(params map[string]string, sign string) bool {
	calcSign := s.BuildSign(params)
	return calcSign == sign
}

func (s *PaymentService) CreateSubscribeOrder(userID uint, username string, planID uint, paymentType string) (orderNo, payURL string, amount float64, name, pid, sign string, err error) {
	tbl := database.Get().Register("SubscriptionPlan")

	var plan models.SubscriptionPlan
	if !tbl.FindByID(planID, &plan) {
		return "", "", 0, "", "", "", fmt.Errorf("订阅计划不存在")
	}
	if plan.Status != 1 {
		return "", "", 0, "", "", "", fmt.Errorf("订阅计划已下架")
	}

	orderNo = GenerateOrderNo("SUB")
	amount = s.applyActivityPrice(plan.Price, "subscribe")
	order := models.PaymentOrder{
		UserID:      userID,
		Username:    username,
		OrderNo:     orderNo,
		Type:        "subscribe",
		PlanID:      &planID,
		PlanName:    plan.Name,
		Amount:      amount,
		Status:      "pending",
		PaymentType: paymentType,
	}
	if err = database.Get().Register("PaymentOrder").Insert(&order); err != nil {
		return "", "", 0, "", "", "", fmt.Errorf("创建订单失败")
	}

	pc := s.getPaymentConfig()
	paramJSON := fmt.Sprintf(`{"plan_id":%d}`, planID)
	_, payURL = s.buildPayParams(orderNo, amount, plan.Name, paymentType, paramJSON)
	return orderNo, payURL, amount, plan.Name, pc.PID, "", nil
}

func (s *PaymentService) CreateZeroDropOrder(userID uint, username string, amount float64, paymentType string) (orderNo, payURL string, finalAmount float64, name, pid, sign string, err error) {
	return "", "", 0, "", "", "", fmt.Errorf("余额充值已下线，请购买订阅")
}

func (s *PaymentService) applyActivityPrice(original float64, scope string) float64 {
	today := time.Now().Format("2006-01-02")

	var activities []models.Activity
	database.Get().Register("Activity").FindAll(&activities, nil, "", 0, 0)

	for _, a := range activities {
		if a.Status == 1 && a.ApplyScope == scope && a.Type != "bonus" && a.StartedAt <= today && a.EndedAt >= today {
			return math.Round(original*a.Discount*100) / 100
		}
	}
	return original
}

func (s *PaymentService) getActiveActivityForScope(scope string) *models.Activity {
	today := time.Now().Format("2006-01-02")
	var activities []models.Activity
	database.Get().Register("Activity").FindAll(&activities, nil, "", 0, 0)
	for _, a := range activities {
		if a.Status == 1 && a.ApplyScope == scope && a.StartedAt <= today && a.EndedAt >= today {
			return &a
		}
	}
	return nil
}

func (s *PaymentService) buildPayParams(orderNo string, amount float64, name, paymentType, param string) (map[string]string, string) {
	pc := s.getPaymentConfig()

	params := map[string]string{
		"pid":          pc.PID,
		"type":         paymentType,
		"out_trade_no": orderNo,
		"money":        fmt.Sprintf("%.2f", amount),
		"name":         name,
		"notify_url":   pc.NotifyURL,
		"return_url":   pc.ReturnURL,
	}

	if param != "" {
		params["param"] = param
	}

	if pc.Sitename != "" {
		params["sitename"] = pc.Sitename
	}

	sign := s.BuildSign(params)
	params["sign"] = sign
	params["sign_type"] = "MD5"

	queryOrder := []string{"pid", "type", "out_trade_no", "notify_url", "return_url", "name", "money"}
	if param != "" {
		queryOrder = append(queryOrder, "param")
	}
	if pc.Sitename != "" {
		queryOrder = append(queryOrder, "sitename")
	}
	queryOrder = append(queryOrder, "sign", "sign_type")

	var parts []string
	for _, k := range queryOrder {
		parts = append(parts, fmt.Sprintf("%s=%s", k, url.QueryEscape(params[k])))
	}
	query := strings.Join(parts, "&")

	return params, s.getPaymentAPIURL() + "?" + query
}

func (s *PaymentService) buildPayURL(orderNo string, amount float64, name, paymentType string) string {
	_, payURL := s.buildPayParams(orderNo, amount, name, paymentType, "")
	return payURL
}

func (s *PaymentService) getPaymentAPIURL() string {
	var sc models.SystemConfig
	if database.Get().Register("SystemConfig").FindOne(database.FilterEq("Key", "payment_api_url"), &sc) && sc.Value != "" {
		urlStr := EnsureHTTP(sc.Value)
		// 迁移旧域名 old.example.com → pay.example.com
		urlStr = strings.Replace(urlStr, "old.example.com", "pay.example.com", 1)
		// 确保使用 submit.php（页面跳转支付）
		urlStr = strings.Replace(urlStr, "/mapi.php", "/submit.php", 1)
		// 如果地址只有域名没有路径，追加 /submit.php
		u, err := url.Parse(urlStr)
		if err == nil && (u.Path == "" || u.Path == "/") {
			urlStr = strings.TrimRight(urlStr, "/") + "/submit.php"
		}
		return urlStr
	}
	return "https://pay.example.com/submit"
}

func (s *PaymentService) getPaymentQueryURL() string {
	var sc models.SystemConfig
	if database.Get().Register("SystemConfig").FindOne(database.FilterEq("Key", "payment_query_url"), &sc) && sc.Value != "" {
		urlStr := EnsureHTTP(sc.Value)
		// 迁移旧域名 old.example.com → pay.example.com
		urlStr = strings.Replace(urlStr, "old.example.com", "pay.example.com", 1)
		return urlStr
	}
	return "https://pay.example.com/api"
}

func (s *PaymentService) QueryOrder(outTradeNo string) (map[string]interface{}, error) {
	pc := s.getPaymentConfig()

	params := fmt.Sprintf("act=order&pid=%s&key=%s&out_trade_no=%s",
		url.QueryEscape(pc.PID),
		url.QueryEscape(pc.Key),
		url.QueryEscape(outTradeNo),
	)

	// 用带 30s 超时的共享 client：http.DefaultClient 无超时，网关挂死会泄漏 goroutine
	resp, err := getUpstreamClients().metadata.Get(s.getPaymentQueryURL() + "?" + params)
	if err != nil {
		return nil, fmt.Errorf("查询订单失败: %w", err)
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("解析订单查询结果失败: %w", err)
	}

	return result, nil
}

func (s *PaymentService) HandleNotify(params map[string]string) error {
	tradeStatus, ok := params["trade_status"]
	if !ok || tradeStatus != "TRADE_SUCCESS" {
		return fmt.Errorf("交易状态不是TRADE_SUCCESS")
	}

	sign, ok := params["sign"]
	if !ok {
		return fmt.Errorf("缺少签名参数")
	}

	if !s.VerifySign(params, sign) {
		return fmt.Errorf("签名验证失败")
	}

	orderNo := params["out_trade_no"]
	tradeNo := params["trade_no"]
	actualMoney := params["money"]

	var actualAmount float64
	fmt.Sscanf(actualMoney, "%f", &actualAmount)

	orders := database.Get().Register("PaymentOrder")

	// 先查找订单，校验回调金额与订单金额是否匹配；
	// 区分"订单不存在"与"DB 故障"——后者返回错误让网关重试，而非误判订单缺失
	var existingOrder models.PaymentOrder
	found, err := orders.FindOneE(database.FilterEq("OrderNo", orderNo), &existingOrder)
	if err != nil {
		return fmt.Errorf("查询订单失败: %w", err)
	}
	if !found {
		return fmt.Errorf("订单不存在")
	}
	if math.Abs(actualAmount-existingOrder.Amount) > 0.01 {
		log.Printf("⚠️ 支付金额不匹配: 订单 %s 应付 %.2f 实付 %.2f", orderNo, existingOrder.Amount, actualAmount)
		return fmt.Errorf("支付金额不匹配")
	}

	// 原子状态转换：只有 status=pending 时才更新；updated==0 表示并发回调
	// 已抢先完成转换——本次直接退出，后续发放由 activateSubscription 的
	// OrderNo 幂等兜底（不能靠"重新读到的状态"判输赢：两个并发回调都会看到 paid）
	updated, err := orders.UpdateWhereCount(
		database.FilterAnd(
			database.FilterEq("OrderNo", orderNo),
			database.FilterEq("Status", "pending"),
		),
		map[string]interface{}{
			"TradeNo":      tradeNo,
			"ActualAmount": actualAmount,
			"Status":       "paid",
			"PaidAt":       time.Now(),
		},
	)
	if err != nil {
		return fmt.Errorf("更新订单状态失败: %w", err)
	}
	if updated == 0 {
		return nil
	}

	var order models.PaymentOrder
	if !orders.FindOne(database.FilterEq("OrderNo", orderNo), &order) {
		return nil
	}
	order.ActualAmount = actualAmount

	// 从回调 param 中提取业务参数（下单时传入的 plan_id）
	if paramStr, ok := params["param"]; ok && paramStr != "" && order.Type == "subscribe" {
		var extra map[string]interface{}
		if json.Unmarshal([]byte(paramStr), &extra) == nil {
			if pf, ok := extra["plan_id"].(float64); ok && pf > 0 {
				pid := uint(pf)
				order.PlanID = &pid
			}
		}
	}

	switch order.Type {
	case "subscribe":
		return s.activateSubscription(order)
	case "zero_drop":
		return nil
	}

	return nil
}

func (s *PaymentService) CheckAndActivateOrder(orderNo string) error {
	orders := database.Get().Register("PaymentOrder")

	result, err := s.QueryOrder(orderNo)
	if err != nil {
		return fmt.Errorf("查询支付网关失败: %w", err)
	}

	status := fmt.Sprintf("%v", result["status"])
	if status != "1" {
		return fmt.Errorf("订单未支付")
	}

	tradeNo, _ := result["trade_no"].(string)
	actualMoney, _ := result["money"].(string)

	var actualAmount float64
	fmt.Sscanf(actualMoney, "%f", &actualAmount)

	// 先查找订单，校验查询返回的金额与订单金额是否匹配
	var existingOrder models.PaymentOrder
	if !orders.FindOne(database.FilterEq("OrderNo", orderNo), &existingOrder) {
		return fmt.Errorf("订单不存在")
	}
	if math.Abs(actualAmount-existingOrder.Amount) > 0.01 {
		log.Printf("⚠️ 支付金额不匹配: 订单 %s 应付 %.2f 实付 %.2f", orderNo, existingOrder.Amount, actualAmount)
		return fmt.Errorf("支付金额不匹配")
	}

	// 原子状态转换
	if err := orders.UpdateWhere(
		database.FilterAnd(
			database.FilterEq("OrderNo", orderNo),
			database.FilterEq("Status", "pending"),
		),
		map[string]interface{}{
			"TradeNo":      tradeNo,
			"ActualAmount": actualAmount,
			"Status":       "paid",
			"PaidAt":       time.Now(),
		},
	); err != nil {
		return fmt.Errorf("更新订单状态失败: %w", err)
	}

	var order models.PaymentOrder
	if !orders.FindOne(database.FilterEq("OrderNo", orderNo), &order) || order.Status != "paid" {
		return fmt.Errorf("订单处理失败")
	}

	switch order.Type {
	case "subscribe":
		return s.activateSubscription(order)
	case "zero_drop":
		return nil
	}

	return nil
}

func (s *PaymentService) activateSubscription(order models.PaymentOrder) error {
	unlock := activateLocks.LockUint(order.UserID)
	defer unlock()

	if order.PlanID == nil {
		return fmt.Errorf("订阅订单缺少计划ID")
	}

	var plan models.SubscriptionPlan
	if !database.Get().Register("SubscriptionPlan").FindByID(*order.PlanID, &plan) {
		return fmt.Errorf("订阅计划不存在")
	}

	// 幂等性检查：防止并发重复激活
	var existingSub models.UserSubscription
	if database.Get().Register("UserSubscription").FindOne(database.FilterEq("OrderNo", order.OrderNo), &existingSub) {
		return nil
	}

	now := time.Now()
	today := now.Format("2006-01-02")
	subs := database.Get().Register("UserSubscription")

	var active models.UserSubscription
	if subs.FindOne(
		database.FilterAll(
			database.FilterEq("UserID", order.UserID),
			database.FilterEq("PlanID", plan.ID),
			database.FilterEq("Status", 1),
			database.FilterGte("ExpiresAt", today),
		),
		&active,
	) {
		expiry, err := time.Parse("2006-01-02", active.ExpiresAt)
		if err != nil {
			expiry = now
		}
		newExpiry := expiry.AddDate(0, 0, plan.DurationDays)
		subs.UpdateWhere(database.FilterEq("ID", active.ID), map[string]interface{}{
			"ExpiresAt": newExpiry.Format("2006-01-02"),
		})
		PublishSubscriptionChanged(order.UserID)
		PublishQuotaChanged(order.UserID)
		return nil
	}

	sub := models.UserSubscription{
		UserID:     order.UserID,
		PlanID:     plan.ID,
		PlanName:   plan.Name,
		DailyQuota: plan.DailyQuota,
		StartedAt:  today,
		ExpiresAt:  now.AddDate(0, 0, plan.DurationDays).Format("2006-01-02"),
		Status:     1,
		OrderNo:    order.OrderNo,
	}

	if err := subs.Insert(&sub); err != nil {
		return err
	}
	PublishSubscriptionChanged(order.UserID)
	PublishQuotaChanged(order.UserID)
	return nil
}
