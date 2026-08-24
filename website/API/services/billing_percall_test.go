package services

import (
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

// 按次计费：PricePerCall > 0 时每次调用固定扣费，与 token 用量、思考倍率无关。
func TestCalculateCostPerCallFlatFee(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID:                 "per-call-model",
		ModelName:               "按次模型",
		InputPricePer1M:         100, // 高价 token 定价：若被误用，费用将远超 0.5
		InputCacheHitPricePer1M: 100,
		OutputPricePer1M:        100,
		PricePerCall:            0.5,
		Status:                  1,
	}); err != nil {
		t.Fatalf("insert model price: %v", err)
	}

	svc := &BillingService{}
	// 不同 token 用量（含 0 与超大值）费用恒为 0.5
	for _, tokens := range [][2]int{{0, 0}, {1000, 500}, {100000, 8000}} {
		cost, err := svc.CalculateCost("per-call-model", tokens[0], 0, tokens[0], tokens[1], false)
		if err != nil {
			t.Fatalf("CalculateCost: %v", err)
		}
		if cost != 0.5 {
			t.Fatalf("按次计费应为 0.5，实际 %v（tokens=%v）", cost, tokens)
		}
	}
	// 思考模式不影响按次定价
	cost, err := svc.CalculateCost("per-call-model", 5000, 0, 5000, 2000, true)
	if err != nil {
		t.Fatalf("CalculateCost thinking: %v", err)
	}
	if cost != 0.5 {
		t.Fatalf("思考模式按次计费应为 0.5，实际 %v", cost)
	}
}

// PricePerCall = 0 时保持 token 计价行为不变。
func TestCalculateCostPerCallDisabled(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID:                 "token-model",
		ModelName:               "按量模型",
		InputPricePer1M:         1,
		InputCacheHitPricePer1M: 0.02,
		OutputPricePer1M:        2,
		PricePerCall:            0,
		Status:                  1,
	}); err != nil {
		t.Fatalf("insert model price: %v", err)
	}

	// 1M 输入（未命中）+ 1M 输出 = 1 + 2 = 3
	cost, err := (&BillingService{}).CalculateCost("token-model", 1_000_000, 0, 1_000_000, 1_000_000, false)
	if err != nil {
		t.Fatalf("CalculateCost: %v", err)
	}
	if cost != 3 {
		t.Fatalf("token 计价应为 3，实际 %v", cost)
	}
}
