package models

import (
	"encoding/json"
	"time"
)

// NetworkGroup 网络市场群聊（用户上传 + 管理员审核）
type NetworkGroup struct {
	ID                  uint       `gorm:"primaryKey" json:"id"`
	UploaderID          uint       `gorm:"index;not null" json:"uploader_id"`
	UploaderName        string     `gorm:"size:64" json:"uploader_name"`
	Name                string     `gorm:"size:128;not null" json:"name"`
	Description         string     `gorm:"type:text" json:"description"`
	GroupPersona        string     `gorm:"type:text" json:"group_persona"`          // AES-GCM 加密
	OpeningLine         string     `gorm:"type:text" json:"opening_line"`           // AES-GCM 加密
	OpeningSpeakerIndex int        `json:"opening_speaker_index"`                   // -1 表示模拟器旁白或旧数据
	WorldSetting        string     `gorm:"type:text" json:"world_setting"`          // AES-GCM 加密
	SpeechMode          string     `gorm:"size:16;default:free" json:"speech_mode"` // free/moderator
	IsSimulatorMode     bool       `gorm:"default:false" json:"is_simulator_mode"`
	AvatarColor         int        `json:"avatar_color"`
	Tags                string     `gorm:"type:text" json:"tags"` // JSON 数组字符串
	Status              string     `gorm:"size:16;default:pending" json:"status"`
	RejectReason        string     `gorm:"type:text" json:"reject_reason"`
	Version             int        `gorm:"default:1" json:"version"`
	DownloadCount       int        `gorm:"default:0" json:"download_count"`
	MembersJSON         string     `gorm:"type:text" json:"members_json"` // AES-GCM 加密的成员设定数组
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
	ReviewedAt          *time.Time `json:"reviewed_at"`
	ReviewerID          uint       `json:"reviewer_id"`
	// AI 预审结果（辅助管理员人工审核，不影响状态机）
	AiReviewStatus string `gorm:"size:16" json:"ai_review_status"` // ""/"pass"/"reject"/"error"
	AiReviewReason string `gorm:"type:text" json:"ai_review_reason"`
	AiReviewedAt   string `gorm:"size:32" json:"ai_reviewed_at"` // RFC3339
}

func (NetworkGroup) TableName() string { return "NetworkGroup" }

// GetTags 解析 Tags JSON 字符串为 []string。空字符串返回空切片。
func (g *NetworkGroup) GetTags() []string {
	if g.Tags == "" {
		return []string{}
	}
	var tags []string
	if err := json.Unmarshal([]byte(g.Tags), &tags); err != nil {
		return []string{}
	}
	return tags
}

// SetTags 将 []string 序列化为 JSON 字符串存入 Tags 字段。
func (g *NetworkGroup) SetTags(tags []string) {
	if len(tags) == 0 {
		g.Tags = "[]"
		return
	}
	data, err := json.Marshal(tags)
	if err != nil {
		g.Tags = "[]"
		return
	}
	g.Tags = string(data)
}

// NetworkMemberPayload 群成员设定（用于 MembersJSON 解析）
type NetworkMemberPayload struct {
	Name              string `json:"name"`
	Gender            string `json:"gender"`
	Description       string `json:"description"`
	Persona           string `json:"persona"`
	OpeningLine       string `json:"opening_line"`
	Worldview         string `json:"worldview"`
	MaxResponseLength int    `json:"max_response_length"`
	AvatarColor       int    `json:"avatar_color"`
	Avatar            string `json:"avatar"` // data:image/...;base64,... 或空
	Role              string `json:"role"`   // moderator/member
	IsSimCharacter    bool   `json:"is_sim_character"`
}
