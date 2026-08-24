package services

import (
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

func TestGetUserDailyQuotaKeepsGrantedAllowanceWhenUsageDateIsStale(t *testing.T) {
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

	user := models.User{
		Username:           "allowance-user",
		Status:             1,
		DailyCheckInBonus:  0.5,
		DailyQuotaUsed:     0.1,
		QuotaResetDate:     "2000-01-01",
		DailyAllowanceDate: time.Now().Format("2006-01-02"),
	}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	if left := GetUserDailyQuota(&user); left != 0.5 {
		t.Fatalf("daily allowance left = %.2f, want 0.50", left)
	}
}

func TestRefreshDailyAllowanceGrantsFreeQuotaOncePerDay(t *testing.T) {
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

	user := models.User{Username: "free-user", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if err := database.Get().Register("SystemConfig").Insert(&models.SystemConfig{
		Key: "default_daily_quota", Value: "0.5",
	}); err != nil {
		t.Fatalf("insert config: %v", err)
	}

	first, refreshed, err := RefreshDailyAllowance(user.ID)
	if err != nil {
		t.Fatalf("first refresh: %v", err)
	}
	if !refreshed {
		t.Fatal("first refresh must grant today's quota")
	}
	if first.DailyCheckInBonus != 0.5 {
		t.Fatalf("free quota = %.2f, want 0.50", first.DailyCheckInBonus)
	}

	second, refreshed, err := RefreshDailyAllowance(user.ID)
	if err != nil {
		t.Fatalf("second refresh: %v", err)
	}
	if refreshed {
		t.Fatal("second refresh must be idempotent")
	}
	if second.DailyCheckInBonus != 0.5 {
		t.Fatalf("free quota after duplicate refresh = %.2f, want 0.50", second.DailyCheckInBonus)
	}
}

func TestRefreshDailyAllowanceResetsSubscriptionUsageWithoutChangingBalance(t *testing.T) {
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

	user := models.User{
		Username:              "subscriber",
		Status:                1,
		Balance:               12.34,
		DailyQuotaUsed:        0.4,
		SubscriptionQuotaUsed: 0.6,
	}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if err := database.Get().Register("UserSubscription").Insert(&models.UserSubscription{
		UserID:     user.ID,
		PlanName:   "测试订阅",
		DailyQuota: 2,
		StartedAt:  "2020-01-01",
		ExpiresAt:  "2099-12-31",
		Status:     1,
	}); err != nil {
		t.Fatalf("insert subscription: %v", err)
	}

	refreshedUser, refreshed, err := RefreshDailyAllowance(user.ID)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if !refreshed {
		t.Fatal("subscription refresh must grant today's quota")
	}
	if refreshedUser.DailyCheckInBonus != 0 {
		t.Fatalf("subscription free quota = %.2f, want 0", refreshedUser.DailyCheckInBonus)
	}
	if refreshedUser.DailyQuotaUsed != 0 || refreshedUser.SubscriptionQuotaUsed != 0 {
		t.Fatalf(
			"used quotas = %.2f/%.2f, want 0/0",
			refreshedUser.DailyQuotaUsed,
			refreshedUser.SubscriptionQuotaUsed,
		)
	}
	if refreshedUser.Balance != 12.34 {
		t.Fatalf("balance = %.2f, want 12.34", refreshedUser.Balance)
	}
}
