package models

import (
	"time"
)

type SubscriptionPlan struct {
	ID                uint      `json:"id"`
	Name              string    `json:"name"`
	Description       string    `json:"description"`
	Price             float64   `json:"price"`
	DailyQuota        float64   `json:"daily_quota"`
	DurationDays      int       `json:"duration_days"`
	ModelRestrict     bool      `json:"model_restrict"`
	OcrDailyQuota     int       `json:"ocr_daily_quota"`      // -1=无限, 0=不允许, >0=每日次数
	RealReplyDailyQuota int     `json:"real_reply_daily_quota"` // -1=无限, 0=不允许, >0=每日轮数
	AllowSync         bool      `json:"allow_sync"`            // 是否允许使用多端同步功能
	Status            int       `json:"status"`
	SortOrder         int       `json:"sort_order"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}
