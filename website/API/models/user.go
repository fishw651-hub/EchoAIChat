package models

import (
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID                    uint           `json:"id"`
	Username              string         `json:"username"`
	Email                 string         `json:"email"`
	PasswordHash          string         `json:"-"`
	Nickname              string         `json:"nickname"`
	AvatarURL             string         `json:"avatar_url"`
	Balance               float64        `json:"balance"`
	DailyQuotaUsed        float64        `json:"daily_quota_used"`
	DailyCheckInBonus     float64        `json:"daily_check_in_bonus"`
	SubscriptionQuotaUsed float64        `json:"subscription_quota_used"`
	QuotaResetDate        string         `json:"quota_reset_date"`
	DailyAllowanceDate    string         `json:"daily_allowance_date"`
	OcrUsedToday          int            `json:"ocr_used_today"`
	RealReplyUsedToday    int            `json:"real_reply_used_today"`
	Role                  string         `json:"role"`
	Status                int            `json:"status"`
	// TokenVersion 令牌版本号：改密/重置密码时递增，使旧 JWT 立即失效（内部字段，不出参）
	TokenVersion          int            `json:"-"`
	LastLoginAt           *time.Time     `json:"last_login_at,omitempty"`
	LastLoginIP           string         `json:"last_login_ip,omitempty"`
	CreatedAt             time.Time      `json:"created_at"`
	UpdatedAt             time.Time      `json:"updated_at"`
	DeletedAt             gorm.DeletedAt `json:"-"`
}
