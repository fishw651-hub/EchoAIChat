package services

import (
	"errors"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

func TestBillingServiceDeductAndRecordRejectsUsersWithoutSubscriptionQuota(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	insertModelPrice(t)
	user := insertBillingUser(t, 100)

	_, _, err := (&BillingService{}).DeductAndRecord(
		user.ID,
		user.Username,
		"deepseek-v4-flash",
		1000,
		0,
		1000,
		1000,
		false,
	)

	var billingErr *BillingError
	if !errors.As(err, &billingErr) {
		t.Fatalf("error = %v, want BillingError", err)
	}
	if billingErr.Mistake != utils.MistakeBalanceInsufficient {
		t.Fatalf("mistake = %q, want %q", billingErr.Mistake, utils.MistakeBalanceInsufficient)
	}

	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found after billing")
	}
	if after.Balance != 100 {
		t.Fatalf("balance = %.2f, want unchanged 100", after.Balance)
	}
}

func TestBillingServiceDeductAndRecordConsumesFreeCheckInQuotaForFreeUsers(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 100, 0.2)

	cost, balanceAfter, err := (&BillingService{}).DeductAndRecord(
		user.ID,
		user.Username,
		"deepseek-v4-flash",
		1000,
		0,
		1000,
		1000,
		false,
	)
	if err != nil {
		t.Fatalf("deduct and record: %v", err)
	}
	if balanceAfter != 0 {
		t.Fatalf("balanceAfter = %.6f, want 0 because permanent balance is not used", balanceAfter)
	}

	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found after billing")
	}
	if after.Balance != 100 {
		t.Fatalf("balance = %.2f, want unchanged 100", after.Balance)
	}
	if after.DailyQuotaUsed != cost {
		t.Fatalf("daily quota used = %.6f, want %.6f", after.DailyQuotaUsed, cost)
	}
	if after.SubscriptionQuotaUsed != 0 {
		t.Fatalf("subscription used = %.6f, want 0", after.SubscriptionQuotaUsed)
	}
}

func TestBillingServiceDeductAndRecordConsumesOnlySubscriptionDailyQuota(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 100, 0.2)
	insertSubscription(t, user.ID, 1)

	cost, balanceAfter, err := (&BillingService{}).DeductAndRecord(
		user.ID,
		user.Username,
		"deepseek-v4-flash",
		1000,
		0,
		1000,
		1000,
		false,
	)
	if err != nil {
		t.Fatalf("deduct and record: %v", err)
	}
	if cost <= 0 {
		t.Fatalf("cost = %.6f, want positive", cost)
	}
	if balanceAfter != 0 {
		t.Fatalf("balanceAfter = %.6f, want 0 because permanent balance is not used", balanceAfter)
	}

	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found after billing")
	}
	if after.Balance != 100 {
		t.Fatalf("balance = %.2f, want unchanged 100", after.Balance)
	}
	if after.SubscriptionQuotaUsed != cost {
		t.Fatalf("subscription used = %.6f, want %.6f", after.SubscriptionQuotaUsed, cost)
	}
	if after.DailyQuotaUsed != 0 {
		t.Fatalf("daily quota used = %.6f, want 0 because subscription users do not use free quota", after.DailyQuotaUsed)
	}
}

func TestSubscriptionQuotaImmediatelyAvailableOnPurchaseSameDay(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 0.2)

	// 购买订阅前：免费用户只有 0.2 签到额度，无订阅额度
	freeLeftBefore, subLeftBefore, _ := GetUserBalanceTiers(&user)
	if subLeftBefore != 0 {
		t.Fatalf("before purchase, subLeft = %.2f, want 0", subLeftBefore)
	}
	if freeLeftBefore != 0.2 {
		t.Fatalf("before purchase, freeLeft = %.2f, want 0.2", freeLeftBefore)
	}

	// 模拟当天购买订阅（DailyQuota=5）
	insertSubscription(t, user.ID, 5)

	// 购买后当天立即有订阅额度，不需要等第二天重置
	var updated models.User
	if !database.Get().Register("User").FindByID(user.ID, &updated) {
		t.Fatal("user not found after purchase")
	}
	freeLeftAfter, subLeftAfter, _ := GetUserBalanceTiers(&updated)
	if subLeftAfter != 5 {
		t.Fatalf("after purchase same day, subLeft = %.2f, want 5.0 (immediately available)", subLeftAfter)
	}
	if freeLeftAfter != 0 {
		t.Fatalf("after purchase, freeLeft = %.2f, want 0 (subscription overrides free)", freeLeftAfter)
	}

	// 当天即可用订阅额度消费
	cost, _, err := (&BillingService{}).DeductAndRecord(
		user.ID, user.Username, "deepseek-v4-flash",
		1000, 0, 1000, 1000, false,
	)
	if err != nil {
		t.Fatalf("deduct after same-day purchase: %v", err)
	}
	if cost <= 0 {
		t.Fatalf("cost = %.6f, want positive", cost)
	}

	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found after billing")
	}
	if after.SubscriptionQuotaUsed != cost {
		t.Fatalf("subscription used = %.6f, want %.6f", after.SubscriptionQuotaUsed, cost)
	}
	if after.DailyQuotaUsed != 0 {
		t.Fatalf("daily quota used = %.6f, want 0 (subscription user)", after.DailyQuotaUsed)
	}
}

func insertModelPrice(t *testing.T) {
	t.Helper()
	err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID:                 "deepseek-v4-flash",
		ModelName:               "deepseek-v4-flash",
		InputPricePer1M:         1,
		InputCacheHitPricePer1M: 0.02,
		OutputPricePer1M:        2,
		Status:                  1,
	})
	if err != nil {
		t.Fatalf("insert model price: %v", err)
	}
}

func insertBillingUser(t *testing.T, balance float64) models.User {
	return insertBillingUserWithBonus(t, balance, 0)
}

func insertBillingUserWithBonus(t *testing.T, balance, dailyCheckInBonus float64) models.User {
	t.Helper()
	user := models.User{
		Username:          "billing-user",
		Balance:           balance,
		DailyCheckInBonus: dailyCheckInBonus,
		Status:            1,
		QuotaResetDate:    time.Now().Format("2006-01-02"),
	}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	return user
}

func insertSubscription(t *testing.T, userID uint, dailyQuota float64) {
	t.Helper()
	today := time.Now().Format("2006-01-02")
	plan := models.SubscriptionPlan{
		Name:       "test plan",
		DailyQuota: dailyQuota,
		Status:     1,
	}
	if err := database.Get().Register("SubscriptionPlan").Insert(&plan); err != nil {
		t.Fatalf("insert subscription plan: %v", err)
	}
	sub := models.UserSubscription{
		UserID:         userID,
		PlanID:         plan.ID,
		PlanName:       "test plan",
		DailyQuota:     dailyQuota,
		StartedAt:      today,
		ExpiresAt:      today,
		Status:         1,
		QuotaResetDate: today,
	}
	if err := database.Get().Register("UserSubscription").Insert(&sub); err != nil {
		t.Fatalf("insert subscription: %v", err)
	}
}
