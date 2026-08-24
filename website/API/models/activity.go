package models

import "time"

type Activity struct {
	ID          uint      `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Type        string    `json:"type"`
	ApplyScope  string    `json:"apply_scope"`
	Discount    float64   `json:"discount"`
	StartedAt   string    `json:"started_at"`
	EndedAt     string    `json:"ended_at"`
	Status      int       `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type ActivityModelRule struct {
	ID                       uint    `json:"id"`
	ActivityID               uint    `json:"activity_id"`
	ModelID                  string  `json:"model_id"`
	InputDiscount            float64 `json:"input_discount"`
	CacheHitDiscount         float64 `json:"cache_hit_discount"`
	OutputDiscount           float64 `json:"output_discount"`
	ThinkingInputDiscount    float64 `json:"thinking_input_discount"`
	ThinkingCacheHitDiscount float64 `json:"thinking_cache_hit_discount"`
	ThinkingOutputDiscount   float64 `json:"thinking_output_discount"`
}
