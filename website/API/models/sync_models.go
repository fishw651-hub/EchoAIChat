package models

import "time"

// 通用字段：每个 SyncXxx 表都有 UserID + ClientID + 时间戳
// ClientID 是客户端本地主键（UUID 或 deviceId_整型id），用于 upsert 定位

type SyncAgent struct {
	ID                uint      `json:"id"`
	UserID            uint      `json:"user_id"`
	ClientID          string    `json:"client_id"` // agents.id (UUID)
	Name              string    `json:"name"`
	Gender            string    `json:"gender"`
	Description       string    `json:"description"`
	Persona           string    `json:"persona"`      // 加密
	OpeningLine       string    `json:"opening_line"` // 加密
	AvatarColor       int       `json:"avatar_color"`
	AvatarPath        string    `json:"avatar_path"`
	ChatBackground    string    `json:"chat_background"`
	Worldview         string    `json:"worldview"` // 加密
	MaxResponseLength int       `json:"max_response_length"`
	IsActive          int       `json:"is_active"`
	RealInfoEnabled   int       `json:"real_info_enabled"`
	IsSimCharacter    int       `json:"is_sim_character"`
	IsGroupOnly       int       `json:"is_group_only"`
	SourceGroupID     string    `json:"source_group_id"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type SyncChatMessage struct {
	ID         uint      `json:"id"`
	UserID     uint      `json:"user_id"`
	ClientID   string    `json:"client_id"` // deviceId_<id>
	Role       string    `json:"role"`
	Content    string    `json:"content"`
	Timestamp  int64     `json:"timestamp"`
	ShortMemID string    `json:"short_mem_id"`
	AgentID    string    `json:"agent_id"`
	GroupID    string    `json:"group_id"`
	ImagePath  string    `json:"image_path"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SyncShortTermMessage struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // short_term_messages.id (UUID)
	Role      string    `json:"role"`
	Content   string    `json:"content"`
	Timestamp int64     `json:"timestamp"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncGroupChat struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"client_id"` // group_chats.id (UUID)
	Name          string    `json:"name"`
	Description   string    `json:"description"`
	AvatarColor   int       `json:"avatar_color"`
	GroupPersona  string    `json:"group_persona"`
	SpeechMode    string    `json:"speech_mode"`
	SimulatorMode int       `json:"simulator_mode"`
	WorldSetting  string    `json:"world_setting"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type SyncGroupMember struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // deviceId_<id>
	GroupID   string    `json:"group_id"`
	AgentID   string    `json:"agent_id"`
	Role      string    `json:"role"`
	IsPresent int       `json:"is_present"`
	JoinedAt  int64     `json:"joined_at"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncGroupMessage struct {
	ID           uint      `json:"id"`
	UserID       uint      `json:"user_id"`
	ClientID     string    `json:"client_id"` // deviceId_<id>
	GroupID      string    `json:"group_id"`
	SenderType   string    `json:"sender_type"`
	SenderID     string    `json:"sender_id"`
	SenderName   string    `json:"sender_name"`
	Content      string    `json:"content"`
	Timestamp    int64     `json:"timestamp"`
	ToolCallData string    `json:"tool_call_data"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type SyncGroupShortTerm struct {
	ID         uint      `json:"id"`
	UserID     uint      `json:"user_id"`
	ClientID   string    `json:"client_id"` // deviceId_<id>
	GroupID    string    `json:"group_id"`
	Role       string    `json:"role"`
	SenderName string    `json:"sender_name"`
	Content    string    `json:"content"`
	Timestamp  int64     `json:"timestamp"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SyncGroupSharedMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // group_shared_memories.id (UUID)
	GroupID   string    `json:"group_id"`
	Field     string    `json:"field"`
	Content   string    `json:"content"`
	UpdatedAt time.Time `json:"updated_at"`
	CreatedAt time.Time `json:"created_at"`
}

type SyncLongTermMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // long_term_memories.id (UUID)
	Field     string    `json:"field"`
	Content   string    `json:"content"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncBaseMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // base_memories.id (UUID)
	Type      string    `json:"type"`
	Content   string    `json:"content"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncPlannedMessage struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"client_id"` // deviceId_<id>
	ScheduledTime int64     `json:"scheduled_time"`
	Message       string    `json:"message"`
	Delivered     int       `json:"delivered"`
	AgentID       string    `json:"agent_id"`
	GroupID       string    `json:"group_id"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type SyncUserProfile struct {
	ID         uint      `json:"id"`
	UserID     uint      `json:"user_id"`
	ClientID   string    `json:"client_id"` // user_profiles.id (UUID)
	Category   string    `json:"category"`
	Key        string    `json:"key"`
	Value      string    `json:"value"` // 加密
	Confidence int       `json:"confidence"`
	Source     string    `json:"source"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SyncProvider struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"client_id"` // deviceId_<id>
	Name          string    `json:"name"`
	ApiBaseUrl    string    `json:"api_base_url"`
	ApiKey        string    `json:"api_key"` // 加密
	SelectedModel string    `json:"selected_model"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// SyncTombstone 记录用户在客户端删除的条目
type SyncTombstone struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	TableName string    `json:"table_name"` // 'agents' / 'chat_messages' / ...
	ClientID  string    `json:"client_id"`
	AgentID   string    `json:"agent_id"`
	CreatedAt time.Time `json:"created_at"`
}
