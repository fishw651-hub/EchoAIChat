package models

import "time"

// DeviceBan 设备封禁记录（按物理设备 ID，跨账号）
// 一台设备在窗口期内切换过多不同账号时触发本地封禁，封禁计数持久化在服务器
type DeviceBan struct {
	ID        uint      `json:"id"`
	DeviceID  string    `json:"device_id"`
	BanUntil  time.Time `json:"ban_until"`
	BanCount  int       `json:"ban_count"` // 累计封禁次数，用于递增封禁天数
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// DeviceAccountLog 设备登录账号记录（统计窗口期内切换的不同账号）
type DeviceAccountLog struct {
	ID       uint      `json:"id"`
	DeviceID string    `json:"device_id"`
	UserID   uint      `json:"user_id"`
	LoginAt  time.Time `json:"login_at"`
}
