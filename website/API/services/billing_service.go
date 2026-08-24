package services

import (
	"fmt"
	"math"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

type BillingError struct {
	Mistake  string  `json:"mistake"`
	Required float64 `json:"required"`
	Current  float64 `json:"current"`
}

func (e *BillingError) Error() string {
	return fmt.Sprintf("余额不足，需要%.6f元，当前余额%.4f元", e.Required, e.Current)
}

func (e *BillingError) ToMap() map[string]interface{} {
	return map[string]interface{}{
		"mistake":  e.Mistake,
		"required": e.Required,
		"current":  e.Current,
	}
}

func NewBillingError(required, current float64) *BillingError {
	return &BillingError{
		Mistake:  utils.MistakeBalanceInsufficient,
		Required: required,
		Current:  current,
	}
}

type BillingService struct{}

func (s *BillingService) CalculateCost(modelID string, promptTokens, cacheHit, cacheMiss, completionTokens int, thinkingEnabled bool) (float64, error) {
	var price models.ModelPrice
	if !database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", modelID), &price) {
		return 0, fmt.Errorf("模型%s未配置定价", modelID)
	}

	var inputP, cacheP, outputP float64

	if thinkingEnabled && price.ThinkingStatus == 1 {
		inputP = price.ThinkingInputPricePer1M
		cacheP = price.ThinkingInputCacheHitPricePer1M
		outputP = price.ThinkingOutputPricePer1M
	} else {
		if price.Status != 1 {
			return 0, fmt.Errorf("模型%s已停用", modelID)
		}
		inputP = price.InputPricePer1M
		cacheP = price.InputCacheHitPricePer1M
		outputP = price.OutputPricePer1M
	}

	// 按次计费：固定费用，与 token 用量、活动折扣、思考倍率无关
	//（分时定价倍率在 CalculateCostWithTimeOfUse 外层叠加，仍然生效）
	if price.PricePerCall > 0 {
		return math.Round(price.PricePerCall*1_000_000) / 1_000_000, nil
	}

	cacheHitCost := float64(cacheHit) / 1_000_000 * cacheP
	cacheMissCost := float64(cacheMiss) / 1_000_000 * inputP
	outputCost := float64(completionTokens) / 1_000_000 * outputP

	totalCost := cacheHitCost + cacheMissCost + outputCost

	rule := getChatActivityRule(modelID, thinkingEnabled)
	if rule != nil {
		if thinkingEnabled {
			cacheHitCost = float64(cacheHit) / 1_000_000 * cacheP * rule.ThinkingCacheHitDiscount
			cacheMissCost = float64(cacheMiss) / 1_000_000 * inputP * rule.ThinkingInputDiscount
			outputCost = float64(completionTokens) / 1_000_000 * outputP * rule.ThinkingOutputDiscount
		} else {
			cacheHitCost = float64(cacheHit) / 1_000_000 * cacheP * rule.CacheHitDiscount
			cacheMissCost = float64(cacheMiss) / 1_000_000 * inputP * rule.InputDiscount
			outputCost = float64(completionTokens) / 1_000_000 * outputP * rule.OutputDiscount
		}
		totalCost = cacheHitCost + cacheMissCost + outputCost
	}

	return math.Round(totalCost*1_000_000) / 1_000_000, nil
}

func (s *BillingService) CalculateCostWithTimeOfUse(modelID string, promptTokens, cacheHit, cacheMiss, completionTokens int, thinkingEnabled bool, at time.Time) (float64, string, float64, error) {
	cost, err := s.CalculateCost(modelID, promptTokens, cacheHit, cacheMiss, completionTokens, thinkingEnabled)
	if err != nil {
		return 0, "", 0, err
	}
	pricing, err := LoadTimeOfUsePricing()
	if err != nil {
		pricing = DefaultTimeOfUsePricing()
	}
	period, multiplier, err := pricing.MultiplierAt(at)
	if err != nil {
		period = "peak"
		multiplier = 1
	}
	return applyPriceMultiplier(cost, multiplier), period, multiplier, nil
}

func applyPriceMultiplier(cost, multiplier float64) float64 {
	if !isPositiveFinite(multiplier) {
		multiplier = 1
	}
	return math.Round(cost*multiplier*1_000_000) / 1_000_000
}

func getChatActivityRule(modelID string, thinking bool) *models.ActivityModelRule {
	today := utils.TodayCN()
	var activities []models.Activity
	database.Get().Register("Activity").FindAll(&activities, nil, "", 0, 0)
	var activeID uint
	for _, a := range activities {
		if a.Status == 1 && a.ApplyScope == "chat" && a.StartedAt <= today && a.EndedAt >= today {
			activeID = a.ID
			break
		}
	}
	if activeID == 0 {
		return nil
	}
	var rules []models.ActivityModelRule
	database.Get().Register("ActivityModelRule").FindAll(&rules, nil, "", 0, 0)
	for _, r := range rules {
		if r.ActivityID == activeID && r.ModelID == modelID {
			return &r
		}
	}
	return nil
}

// Deprecated: 无生产调用方（仅测试引用）。读 user→判配额→IncrementField 分属
// 不同事务，并发下可双双通过检查导致超扣——新代码请用 Reserve/Settle
// 预留-结算流程（per-user 分片锁 + 事务内原子扣减）。
func (s *BillingService) DeductAndRecord(userID uint, username, modelID string, promptTokens, cacheHit, cacheMiss, completionTokens int, thinkingEnabled bool) (float64, float64, error) {
	db := database.Get()
	users := db.Register("User")

	cost, err := s.CalculateCost(modelID, promptTokens, cacheHit, cacheMiss, completionTokens, thinkingEnabled)
	if err != nil {
		return 0, 0, err
	}

	var user models.User
	if !users.FindByID(userID, &user) {
		return 0, 0, fmt.Errorf("用户不存在")
	}

	today := utils.TodayCN()
	if user.QuotaResetDate != today {
		updates := map[string]interface{}{
			"DailyQuotaUsed":        0,
			"SubscriptionQuotaUsed": 0,
			"QuotaResetDate":        today,
		}
		user.DailyQuotaUsed = 0
		user.SubscriptionQuotaUsed = 0
		user.QuotaResetDate = today
		if user.DailyAllowanceDate != today {
			updates["DailyCheckInBonus"] = 0.0
			user.DailyCheckInBonus = 0
		}
		users.UpdateWhere(database.FilterEq("ID", userID), updates)
	}

	subTotal := getSubscriptionQuotaTotal(userID)
	canUseSub := modelInUserSubscription(userID, modelID, thinkingEnabled)
	hasSub := subTotal > 0

	freeLeft := user.DailyCheckInBonus - user.DailyQuotaUsed
	if freeLeft < 0 {
		freeLeft = 0
	}
	subLeft := subTotal - user.SubscriptionQuotaUsed
	if subLeft < 0 {
		subLeft = 0
	}

	freeUsed := 0.0
	subUsed := 0.0

	if hasSub {
		if !canUseSub || subLeft < cost {
			return 0, 0, NewBillingError(cost, subLeft)
		}
		subUsed = cost
	} else {
		if freeLeft < cost {
			return 0, 0, NewBillingError(cost, freeLeft)
		}
		freeUsed = math.Min(freeLeft, cost)
	}

	if freeUsed > 0 {
		database.Get().Register("User").IncrementField(
			database.FilterEq("ID", userID),
			"DailyQuotaUsed",
			freeUsed,
		)
	}
	if subUsed > 0 {
		database.Get().Register("User").IncrementField(
			database.FilterEq("ID", userID),
			"SubscriptionQuotaUsed",
			subUsed,
		)
	}
	balanceAfter := 0.0

	record := models.UsageRecord{
		UserID:           userID,
		Username:         username,
		Model:            modelID,
		PromptTokens:     promptTokens,
		PromptCacheHit:   cacheHit,
		PromptCacheMiss:  cacheMiss,
		CompletionTokens: completionTokens,
		Cost:             cost,
	}
	db.Register("UsageRecord").Insert(&record)

	return cost, balanceAfter, nil
}

func getSubscriptionQuotaTotal(userID uint) float64 {
	sum := 0.0
	for _, s := range ActiveSubscriptionsForUser(userID) {
		sum += s.DailyQuota
	}
	return sum
}

func modelInUserSubscription(userID uint, modelID string, thinkingEnabled bool) bool {
	return HasActiveSubscriptionForUser(userID)
}
