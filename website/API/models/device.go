package models

import "time"

// Device 用户设备（用于多端同步设备管理）
type Device struct {
	ID           uint       `json:"id"`
	UserID       uint       `json:"user_id"`
	DeviceID     string     `json:"device_id"`   // 客户端生成的 UUID，唯一标识一台设备
	DeviceName   string     `json:"device_name"` // 用户可编辑的设备名称
	ClientKind   string     `json:"client_kind"` // native / web
	Platform     string     `json:"platform"`    // android / ios / windows / mac / linux
	Browser      string     `json:"browser"`     // Chrome / Edge / Firefox / Safari
	Role         string     `json:"role"`        // "master" 主机 / "slave" 副机
	LastActiveAt time.Time  `json:"last_active_at"`
	LastSyncAt   *time.Time `json:"last_sync_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// SyncSetting 用户级别的多端同步设置
type SyncSetting struct {
	ID               uint      `json:"id"`
	UserID           uint      `json:"user_id"`
	FullSyncEnabled  bool      `json:"full_sync_enabled"` // 旧客户端兼容字段
	ScopeMode        string    `json:"scope_mode"`
	SelectedAgentIDs []string  `json:"selected_agent_ids"`
	RealtimeEnabled  bool      `json:"realtime_enabled"`
	PolicyVersion    uint64    `json:"policy_version"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type SyncPolicy struct {
	ScopeMode        string    `json:"scope_mode"`
	SelectedAgentIDs []string  `json:"selected_agent_ids"`
	RealtimeEnabled  bool      `json:"realtime_enabled"`
	Version          uint64    `json:"version"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type SyncPolicyUpdate struct {
	ScopeMode        string   `json:"scope_mode"`
	SelectedAgentIDs []string `json:"selected_agent_ids"`
	RealtimeEnabled  bool     `json:"realtime_enabled"`
	ExpectedVersion  uint64   `json:"expected_version"`
}
