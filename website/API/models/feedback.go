package models

import "time"

// Feedback 用户反馈
type Feedback struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	Username  string    `json:"username"`
	Category  string    `json:"category"`  // feature/feature_tweak/bug/ui/pricing/other
	Content   string    `json:"content"`
	Contact   string    `json:"contact"`   // 邮箱或电话
	Status    int       `json:"status"`    // 0=待处理 1=处理中 2=已回复 3=已关闭
	Reply     string    `json:"reply"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
