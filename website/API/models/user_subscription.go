package models

import (
	"time"
)

type UserSubscription struct {
	ID                  uint      `gorm:"primaryKey" json:"id"`
	UserID              uint      `gorm:"index;not null" json:"user_id"`
	PlanID              uint      `gorm:"index;not null" json:"plan_id"`
	PlanName            string    `gorm:"size:128" json:"plan_name"`
	DailyQuota          float64   `gorm:"type:decimal(12,4);default:0" json:"daily_quota"`
	StartedAt           string    `gorm:"type:date" json:"started_at"`
	ExpiresAt           string    `gorm:"type:date" json:"expires_at"`
	Status              int       `gorm:"default:1" json:"status"`
	OrderNo             string    `gorm:"size:64" json:"order_no"`
	// per-subscription 当日功能配额计数（按订阅独立计数，跨天重置）
	OcrUsedToday        int       `gorm:"default:0" json:"ocr_used_today"`
	RealReplyUsedToday  int       `gorm:"default:0" json:"real_reply_used_today"`
	QuotaResetDate      string    `gorm:"type:date" json:"quota_reset_date"`
	CreatedAt           time.Time `json:"created_at"`
}
