package models

import "time"

// ShareCode 智能体分享码：用户生成 6 位数字码（ShareCodeTTL 内有效），
// 其他用户凭码兑换智能体快照（Snapshot 为 JSON 字符串，含头像 base64）
type ShareCode struct {
	ID          uint      `json:"id"`
	Code        string    `json:"code"`          // 6 位数字分享码
	OwnerUserID uint      `json:"owner_user_id"` // 生成分享码的用户
	Snapshot    string    `json:"snapshot"`      // 智能体快照 JSON 字符串
	CreatedAt   time.Time `json:"created_at"`
	ExpiresAt   time.Time `json:"expires_at"`
}
