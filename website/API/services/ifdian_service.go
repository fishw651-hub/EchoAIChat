package services

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

type IfdianService struct{}

var verifyGrantLocks = utils.NewStripedLock()

// ifdianVerifyMaxFailuresPerHour 单用户订单验证失败次数上限（滑动 1 小时窗口），
// 超过后拒绝继续验证，封死枚举 out_trade_no 冒领的试错空间。
const ifdianVerifyMaxFailuresPerHour = 5

// queryOrderFn 上游订单查询，抽成包级变量以便测试替换。
var queryOrderFn = (*IfdianService).QueryOrder

// verifyFailureTracker 记录每个用户的验证失败时间戳（内存滑动窗口）。
type verifyFailureTracker struct {
	mu       sync.Mutex
	failures map[uint][]time.Time
}

var verifyFailures = newVerifyFailureTracker()

func newVerifyFailureTracker() *verifyFailureTracker {
	return &verifyFailureTracker{failures: make(map[uint][]time.Time)}
}

func (t *verifyFailureTracker) limited(userID uint, now time.Time) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.pruneLocked(userID, now)
	return len(t.failures[userID]) >= ifdianVerifyMaxFailuresPerHour
}

func (t *verifyFailureTracker) record(userID uint, now time.Time) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.pruneLocked(userID, now)
	t.failures[userID] = append(t.failures[userID], now)
}

func (t *verifyFailureTracker) pruneLocked(userID uint, now time.Time) {
	cutoff := now.Add(-time.Hour)
	kept := t.failures[userID][:0]
	for _, ts := range t.failures[userID] {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	t.failures[userID] = kept
}

type IfdianPlanRaw struct {
	PlanID    string  `json:"plan_id"`
	Name      string  `json:"name"`
	Price     float64 `json:"price"`
	PlanType  string  `json:"plan_type"`
	PayAmount float64 `json:"pay_amount"`
	Status    int     `json:"status"`
}

type IfdianQueryPlanResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    struct {
		PlanID    string  `json:"plan_id"`
		Name      string  `json:"name"`
		Price     float64 `json:"price"`
		PlanType  string  `json:"plan_type"`
		PayAmount float64 `json:"pay_amount"`
		SkuList   []struct {
			SkuID string  `json:"sku_id"`
			Name  string  `json:"name"`
			Price float64 `json:"price"`
		} `json:"sku_list"`
	} `json:"data"`
}

type IfdianQueryOrderResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    []struct {
		OutTradeNo  string  `json:"out_trade_no"`
		PlanID      string  `json:"plan_id"`
		TotalAmount float64 `json:"total_amount"`
		Status      int     `json:"status"`
		UserID      string  `json:"user_id"`
	} `json:"data"`
}

func (s *IfdianService) getConfig() (userID, token string) {
	db := database.Get()

	var sc1, sc2 models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", "ifdian_user_id"), &sc1) {
		userID = sc1.Value
	}
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", "ifdian_token"), &sc2) {
		dec, err := DecryptWithConfiguredKeys(sc2.Value)
		if err == nil {
			token = dec
		}
	}
	return
}

func (s *IfdianService) BuildSign(paramsJSON string, ts int64) string {
	userID, token := s.getConfig()
	raw := token + "params" + paramsJSON + "ts" + strconv.FormatInt(ts, 10) + "user_id" + userID
	return fmt.Sprintf("%x", md5.Sum([]byte(raw)))
}

func (s *IfdianService) callAPI(path string, paramsJSON string) ([]byte, error) {
	userID, _ := s.getConfig()
	ts := time.Now().Unix()
	sign := s.BuildSign(paramsJSON, ts)

	apiURL := "https://ifdian.net/api/open" + path
	reqURL := fmt.Sprintf("%s?user_id=%s&params=%s&ts=%d&sign=%s",
		apiURL, url.QueryEscape(userID), url.QueryEscape(paramsJSON), ts, url.QueryEscape(sign))

	// 用带 30s 超时的共享 client：http.DefaultClient 无超时，爱发电挂死会泄漏 goroutine
	//（VerifyAndGrant 在持有订单级互斥锁期间调用本函数，无超时会堵死同订单并发）
	resp, err := getUpstreamClients().metadata.Get(reqURL)
	if err != nil {
		return nil, fmt.Errorf("请求爱发电失败: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("爱发电返回错误(%d): %s", resp.StatusCode, string(body))
	}
	return body, nil
}

func (s *IfdianService) FetchPlan(planID string) (*IfdianPlanRaw, error) {
	params, _ := json.Marshal(map[string]string{"plan_id": planID})
	body, err := s.callAPI("/query-plan", string(params))
	if err != nil {
		return nil, err
	}

	var resp IfdianQueryPlanResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("解析方案失败: %w", err)
	}
	if resp.Code != 0 {
		return nil, fmt.Errorf("爱发电错误: %s", resp.Message)
	}

	d := resp.Data
	return &IfdianPlanRaw{
		PlanID:    d.PlanID,
		Name:      d.Name,
		Price:     d.Price,
		PlanType:  d.PlanType,
		PayAmount: d.PayAmount,
		Status:    1,
	}, nil
}

func (s *IfdianService) SyncPlansToDB() error {
	var sc models.SystemConfig
	db := database.Get()
	if !db.Register("SystemConfig").FindOne(database.FilterEq("Key", "ifdian_plan_ids"), &sc) || sc.Value == "" {
		return fmt.Errorf("请先在爱发电配置中填写方案ID列表")
	}

	planIDs := strings.Split(sc.Value, ",")
	tbl := db.Register("IfdianPlan")
	count := 0

	for _, pid := range planIDs {
		pid = strings.TrimSpace(pid)
		if pid == "" {
			continue
		}

		plan, err := s.FetchPlan(pid)
		if err != nil {
			log.Printf("获取方案 %s 失败: %v", pid, err)
			continue
		}

		var existing models.IfdianPlan
		if !tbl.FindOne(database.FilterEq("IfdianPlanID", pid), &existing) {
			tbl.Insert(&models.IfdianPlan{
				IfdianPlanID: pid,
				Name:         plan.Name,
				Price:        plan.Price,
				PlanType:     plan.PlanType,
				Status:       1,
			})
		}
		count++
	}

	log.Printf("爱发电方案同步完成，共处理 %d 个方案", count)
	return nil
}

func (s *IfdianService) QueryOrder(outTradeNo string) (*IfdianQueryOrderResponse, error) {
	params, _ := json.Marshal(map[string]string{"out_trade_no": outTradeNo})
	body, err := s.callAPI("/query-order", string(params))
	if err != nil {
		return nil, err
	}

	var resp IfdianQueryOrderResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("解析订单失败: %w", err)
	}
	return &resp, nil
}

func (s *IfdianService) VerifyAndGrant(userID uint, outTradeNo string) (map[string]interface{}, error) {
	unlock := verifyGrantLocks.Lock(outTradeNo)
	defer unlock()

	if verifyFailures.limited(userID, time.Now()) {
		return nil, fmt.Errorf("订单验证失败次数过多，请 1 小时后再试")
	}

	// 订单必须先经由签名校验过的 webhook 落库，否则视为凭空订单号直接拒绝。
	// 爱发电订单不携带可关联本站账号的自定义参数，webhook 记录是唯一可信来源。
	db := database.Get()
	var record models.IfdianRecord
	if !db.Register("IfdianRecord").FindOne(database.FilterEq("OutTradeNo", outTradeNo), &record) {
		verifyFailures.record(userID, time.Now())
		log.Printf("[ifdian] 拒绝未登记的订单号: userID=%d outTradeNo=%s", userID, outTradeNo)
		return nil, fmt.Errorf("订单未登记，请确认支付完成后再试或联系客服")
	}
	// 幂等 + 冒领防护：一个订单只发放一次；已发放给他人时记录冒领嫌疑告警。
	if record.Granted {
		if record.UserID != 0 && record.UserID != userID {
			log.Printf("[ifdian] 冒领嫌疑: userID=%d 尝试领取已发放给 userID=%d 的订单 %s", userID, record.UserID, outTradeNo)
		}
		verifyFailures.record(userID, time.Now())
		return nil, fmt.Errorf("该订单已验证并发放权益")
	}

	orderResp, err := queryOrderFn(s, outTradeNo)
	if err != nil {
		return nil, err
	}
	if len(orderResp.Data) == 0 {
		verifyFailures.record(userID, time.Now())
		return nil, fmt.Errorf("订单不存在: %s", outTradeNo)
	}

	order := orderResp.Data[0]
	if order.Status != 2 {
		verifyFailures.record(userID, time.Now())
		return nil, fmt.Errorf("订单未支付成功，状态: %d", order.Status)
	}

	// 方案信息以 webhook 落库记录为准（签名验证过），不轻信上游返回的 plan_id。
	var plan models.IfdianPlan
	if !db.Register("IfdianPlan").FindOne(database.FilterEq("IfdianPlanID", record.PlanID), &plan) {
		return nil, fmt.Errorf("未配置该方案的映射: %s", record.PlanID)
	}
	if plan.Status != 1 || plan.MappingType == "" {
		return nil, fmt.Errorf("该方案未启用或未配置映射")
	}
	if plan.MappingType == "zero_drop" {
		return nil, fmt.Errorf("余额充值已下线，请购买订阅")
	}

	// 认领 webhook 记录：绑定到当前用户。订单级字符串锁保证检查-认领串行，
	// Granted=false 过滤条件兜底并发场景。
	db.Register("IfdianRecord").UpdateWhere(
		database.FilterAll(
			database.FilterEq("ID", record.ID),
			database.FilterEq("Granted", false),
		),
		map[string]interface{}{
			"Granted": true,
			"UserID":  userID,
		},
	)

	switch plan.MappingType {
	case "subscribe":
		duration := plan.DurationDays
		if duration <= 0 {
			duration = 30
		}
		quota := plan.DailyQuota
		if quota <= 0 {
			var localPlan models.SubscriptionPlan
			if db.Register("SubscriptionPlan").FindByID(plan.LocalPlanID, &localPlan) {
				quota = localPlan.DailyQuota
				if duration <= 0 {
					duration = localPlan.DurationDays
				}
			}
		}
		sub := models.UserSubscription{
			UserID:     userID,
			PlanID:     plan.LocalPlanID,
			PlanName:   plan.Name,
			DailyQuota: quota,
			StartedAt:  time.Now().Format("2006-01-02"),
			ExpiresAt:  time.Now().AddDate(0, 0, duration).Format("2006-01-02"),
			Status:     1,
			OrderNo:    outTradeNo,
		}
		db.Register("UserSubscription").Insert(&sub)
		PublishSubscriptionChanged(userID)
		PublishQuotaChanged(userID)
	}

	return map[string]interface{}{
		"granted":      true,
		"mapping_type": plan.MappingType,
		"plan_name":    plan.Name,
		"amount":       order.TotalAmount,
	}, nil
}
