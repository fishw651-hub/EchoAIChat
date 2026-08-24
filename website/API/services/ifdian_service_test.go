package services

import (
	"strings"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

// stubQueryOrder 替换上游订单查询，called 为 true 表示 VerifyAndGrant 走到了上游查询。
func stubQueryOrder(t *testing.T, fn func(outTradeNo string) (*IfdianQueryOrderResponse, error)) {
	t.Helper()
	orig := queryOrderFn
	queryOrderFn = func(_ *IfdianService, outTradeNo string) (*IfdianQueryOrderResponse, error) {
		return fn(outTradeNo)
	}
	t.Cleanup(func() { queryOrderFn = orig })
}

func paidOrderResponse(outTradeNo, planID string) *IfdianQueryOrderResponse {
	resp := &IfdianQueryOrderResponse{}
	resp.Data = append(resp.Data, struct {
		OutTradeNo  string  `json:"out_trade_no"`
		PlanID      string  `json:"plan_id"`
		TotalAmount float64 `json:"total_amount"`
		Status      int     `json:"status"`
		UserID      string  `json:"user_id"`
	}{OutTradeNo: outTradeNo, PlanID: planID, TotalAmount: 10, Status: 2, UserID: "ifdian-buyer"})
	return resp
}

func insertIfdianPlan(t *testing.T, ifdianPlanID string) {
	t.Helper()
	err := database.Get().Register("IfdianPlan").Insert(&models.IfdianPlan{
		IfdianPlanID: ifdianPlanID,
		Name:         "测试方案",
		MappingType:  "subscribe",
		DailyQuota:   5,
		DurationDays: 30,
		Status:       1,
	})
	if err != nil {
		t.Fatalf("insert ifdian plan: %v", err)
	}
}

// 未出现在 webhook 落库记录中的订单号必须被拒绝（防凭空订单号冒领），
// 且不应触发上游查询。
func TestVerifyAndGrantRejectsUnregisteredOrder(t *testing.T) {
	initReservationTestDatabase(t)
	stubQueryOrder(t, func(outTradeNo string) (*IfdianQueryOrderResponse, error) {
		t.Fatal("upstream query should not be called for unregistered order")
		return nil, nil
	})

	_, err := (&IfdianService{}).VerifyAndGrant(101, "OT-NOT-EXIST")
	if err == nil || !strings.Contains(err.Error(), "未登记") {
		t.Fatalf("err = %v, want 订单未登记", err)
	}
}

// 已发放给他人的订单再次领取必须被拒绝（幂等 + 冒领防护）。
func TestVerifyAndGrantRejectsOrderGrantedToOther(t *testing.T) {
	initReservationTestDatabase(t)
	stubQueryOrder(t, func(outTradeNo string) (*IfdianQueryOrderResponse, error) {
		t.Fatal("upstream query should not be called for granted order")
		return nil, nil
	})

	err := database.Get().Register("IfdianRecord").Insert(&models.IfdianRecord{
		UserID:     201,
		OutTradeNo: "OT-GRANTED",
		PlanID:     "plan-1",
		Granted:    true,
	})
	if err != nil {
		t.Fatalf("insert ifdian record: %v", err)
	}

	// 他人领取
	if _, err := (&IfdianService{}).VerifyAndGrant(202, "OT-GRANTED"); err == nil ||
		!strings.Contains(err.Error(), "已验证并发放") {
		t.Fatalf("err = %v, want 该订单已验证并发放权益", err)
	}
	// 本人重复领取同样被拒绝（幂等）
	if _, err := (&IfdianService{}).VerifyAndGrant(201, "OT-GRANTED"); err == nil ||
		!strings.Contains(err.Error(), "已验证并发放") {
		t.Fatalf("err = %v, want 该订单已验证并发放权益", err)
	}
}

// 单用户失败次数达到上限后被限流，封死枚举订单号的试错空间。
func TestVerifyAndGrantRateLimitsFailures(t *testing.T) {
	initReservationTestDatabase(t)
	stubQueryOrder(t, func(outTradeNo string) (*IfdianQueryOrderResponse, error) {
		t.Fatal("upstream query should not be called for unregistered order")
		return nil, nil
	})

	svc := &IfdianService{}
	for i := 0; i < ifdianVerifyMaxFailuresPerHour; i++ {
		if _, err := svc.VerifyAndGrant(303, "OT-GUESS"); err == nil ||
			!strings.Contains(err.Error(), "未登记") {
			t.Fatalf("attempt %d err = %v, want 订单未登记", i+1, err)
		}
	}
	if _, err := svc.VerifyAndGrant(303, "OT-GUESS"); err == nil ||
		!strings.Contains(err.Error(), "失败次数过多") {
		t.Fatalf("err = %v, want rate limited", err)
	}
	// 其他用户不受限流影响
	if _, err := svc.VerifyAndGrant(304, "OT-GUESS"); err == nil ||
		!strings.Contains(err.Error(), "未登记") {
		t.Fatalf("err = %v, want 订单未登记 for other user", err)
	}
}

// 正常路径：webhook 已落库（Granted=false）+ 上游确认已支付 → 发放并绑定到当前用户。
func TestVerifyAndGrantSuccessClaimsWebhookRecord(t *testing.T) {
	initReservationTestDatabase(t)
	insertIfdianPlan(t, "plan-1")
	stubQueryOrder(t, func(outTradeNo string) (*IfdianQueryOrderResponse, error) {
		return paidOrderResponse(outTradeNo, "plan-1"), nil
	})

	db := database.Get()
	if err := db.Register("IfdianRecord").Insert(&models.IfdianRecord{
		IfdianUserID: "ifdian-buyer",
		OutTradeNo:   "OT-OK",
		PlanID:       "plan-1",
		MappingType:  "subscribe",
		Granted:      false,
	}); err != nil {
		t.Fatalf("insert webhook record: %v", err)
	}

	result, err := (&IfdianService{}).VerifyAndGrant(404, "OT-OK")
	if err != nil {
		t.Fatalf("verify and grant: %v", err)
	}
	if granted, _ := result["granted"].(bool); !granted {
		t.Fatalf("result = %v, want granted=true", result)
	}

	var record models.IfdianRecord
	if !db.Register("IfdianRecord").FindOne(database.FilterEq("OutTradeNo", "OT-OK"), &record) {
		t.Fatal("record not found after grant")
	}
	if !record.Granted || record.UserID != 404 {
		t.Fatalf("record after grant: Granted=%v UserID=%d, want Granted=true UserID=404",
			record.Granted, record.UserID)
	}

	var sub models.UserSubscription
	if !db.Register("UserSubscription").FindOne(database.FilterEq("OrderNo", "OT-OK"), &sub) {
		t.Fatal("subscription not granted")
	}
	if sub.UserID != 404 {
		t.Fatalf("subscription userID = %d, want 404", sub.UserID)
	}
}
