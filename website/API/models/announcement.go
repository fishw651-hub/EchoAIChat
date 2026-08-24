package models

import "time"

// Announcement 弹窗公告：客户端启动时拉取当前生效的公告并以弹窗展示
// Frequency 控制展示频率：once=仅一次 / daily=每天一次 / always=每次启动
// Audience 控制目标用户：all=全部用户 / subscriber=仅订阅 / free=仅免费
// StartAt/EndAt 为 RFC3339 时间字符串，两个均必填且 EndAt 必须晚于 StartAt
type Announcement struct {
	ID        uint      `json:"id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"` // Markdown 格式
	Frequency string    `json:"frequency"`
	Audience  string    `json:"audience"`
	StartAt   string    `json:"start_at"`
	EndAt     string    `json:"end_at"`
	Enabled   bool      `json:"enabled"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
