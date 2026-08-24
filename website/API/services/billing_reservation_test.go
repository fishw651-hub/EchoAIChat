package services

import (
	"errors"
	"strings"
	"testing"
	"time"

	"aichat-api/database"
)

func TestReserveRejectsEmptyQuotaBeforeUpstream(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 0)

	_, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash", nil, 128, false)
	if err == nil {
		t.Fatal("reserve succeeded with no available quota")
	}
}

func TestReserveReleaseRestoresQuota(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 1)

	reservation, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash", nil, 128, false)
	if err != nil {
		t.Fatalf("reserve quota: %v", err)
	}
	if reservation.ReservedCost <= 0 {
		t.Fatalf("reserved cost = %f, want positive", reservation.ReservedCost)
	}
	if err := (&BillingService{}).Release(reservation.ID); err != nil {
		t.Fatalf("release reservation: %v", err)
	}

	var after struct {
		DailyQuotaUsed float64
		QuotaResetDate string
	}
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found")
	}
	if after.DailyQuotaUsed != 0 {
		t.Fatalf("daily quota after release = %f, want 0", after.DailyQuotaUsed)
	}
	if after.QuotaResetDate != time.Now().Format("2006-01-02") {
		t.Fatalf("quota reset date = %q", after.QuotaResetDate)
	}
}

func TestReserveRejectsOversizedMessages(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 100)

	big := strings.Repeat("a", MaxChatMessagesBytes+1)
	_, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash",
		[]ChatMessage{{Role: "user", Content: big}}, 128, false)
	var tooLarge *RequestTooLargeError
	if !errors.As(err, &tooLarge) {
		t.Fatalf("err = %v, want RequestTooLargeError", err)
	}
}

func TestReserveScalesWithMessageSize(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 100)

	small, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash",
		[]ChatMessage{{Role: "user", Content: "hi"}}, 128, false)
	if err != nil {
		t.Fatalf("reserve small: %v", err)
	}
	// 200KB 文本 ≈ 51200 token（len/4 估算），远超 16K 固定预留。
	large, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash",
		[]ChatMessage{{Role: "user", Content: strings.Repeat("a", 200*1024)}}, 128, false)
	if err != nil {
		t.Fatalf("reserve large: %v", err)
	}
	if large.ReservedCost <= small.ReservedCost*2 {
		t.Fatalf("large reserve = %f, small reserve = %f, want large > 2x small",
			large.ReservedCost, small.ReservedCost)
	}
}

func TestSettleClampsOverrunToDailyBonus(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 0.05)

	reservation, err := (&BillingService{}).Reserve(user.ID, "deepseek-v4-flash", nil, 128, false)
	if err != nil {
		t.Fatalf("reserve: %v", err)
	}
	// 实际用量 100 万输入 token，费用远超预留与签到额度。
	if _, err := (&BillingService{}).Settle(
		reservation.ID, "billing-user", "deepseek-v4-flash",
		1_000_000, 0, 1_000_000, 128, false,
	); err != nil {
		t.Fatalf("settle: %v", err)
	}

	var after struct {
		DailyQuotaUsed float64
	}
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found")
	}
	// 结算封顶：used 最多扣到签到额度（剩余为 0），不允许变成无意义的大数。
	if after.DailyQuotaUsed != 0.05 {
		t.Fatalf("daily quota used = %f, want clamped to 0.05", after.DailyQuotaUsed)
	}
}

func initReservationTestDatabase(t *testing.T) {
	t.Helper()
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}
