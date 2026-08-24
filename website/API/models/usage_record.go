package models

import (
	"time"
)

type UsageRecord struct {
	ID               uint      `gorm:"primaryKey" json:"id"`
	UserID           uint      `gorm:"index;not null" json:"user_id"`
	Username         string    `gorm:"size:64" json:"username"`
	Model            string    `gorm:"size:64" json:"model"`
	PromptTokens     int       `json:"prompt_tokens"`
	PromptCacheHit   int       `json:"prompt_cache_hit"`
	PromptCacheMiss  int       `json:"prompt_cache_miss"`
	CompletionTokens int       `json:"completion_tokens"`
	Cost             float64   `gorm:"type:decimal(12,6)" json:"cost"`
	PricingPeriod    string    `json:"pricing_period"`
	PriceMultiplier  float64   `json:"price_multiplier"`
	CreatedAt        time.Time `json:"created_at"`
}
