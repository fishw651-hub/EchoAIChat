package models

import (
	"encoding/json"
	"time"
)

// NetworkAgent 网络市场智能体（用户上传 + 管理员审核）
type NetworkAgent struct {
	ID                uint       `gorm:"primaryKey" json:"id"`
	UploaderID        uint       `gorm:"index;not null" json:"uploader_id"`
	UploaderName      string     `gorm:"size:64" json:"uploader_name"`
	Name              string     `gorm:"size:128;not null" json:"name"`
	Gender            string     `gorm:"size:16" json:"gender"`
	Description       string     `gorm:"type:text" json:"description"`
	Persona           string     `gorm:"type:text" json:"persona"`      // AES-GCM 加密
	OpeningLine       string     `gorm:"type:text" json:"opening_line"` // AES-GCM 加密
	Worldview         string     `gorm:"type:text" json:"worldview"`    // AES-GCM 加密
	MaxResponseLength int        `json:"max_response_length"`
	AvatarColor       int        `json:"avatar_color"`
	AvatarPath        string     `gorm:"size:512" json:"avatar_path"`
	ChatBackground    string     `gorm:"size:512" json:"chat_background"`
	Tags              string     `gorm:"type:text" json:"tags"`                 // JSON 数组字符串（database.go 不支持 []string 序列化）
	Status            string     `gorm:"size:16;default:pending" json:"status"` // pending/approved/rejected/taken_down
	RejectReason      string     `gorm:"type:text" json:"reject_reason"`
	Version           int        `gorm:"default:1" json:"version"`
	DownloadCount     int        `gorm:"default:0" json:"download_count"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	ReviewedAt        *time.Time `json:"reviewed_at"`
	ReviewerID        uint       `json:"reviewer_id"`
	// AI 预审结果（辅助管理员人工审核，不影响状态机）
	AiReviewStatus string `gorm:"size:16" json:"ai_review_status"` // ""/"pass"/"reject"/"error"
	AiReviewReason string `gorm:"type:text" json:"ai_review_reason"`
	AiReviewedAt   string `gorm:"size:32" json:"ai_reviewed_at"` // RFC3339
}

func (NetworkAgent) TableName() string { return "NetworkAgent" }

// GetTags 解析 Tags JSON 字符串为 []string。空字符串返回空切片。
func (a *NetworkAgent) GetTags() []string {
	if a.Tags == "" {
		return []string{}
	}
	var tags []string
	if err := json.Unmarshal([]byte(a.Tags), &tags); err != nil {
		return []string{}
	}
	return tags
}

// SetTags 将 []string 序列化为 JSON 字符串存入 Tags 字段。
func (a *NetworkAgent) SetTags(tags []string) {
	if len(tags) == 0 {
		a.Tags = "[]"
		return
	}
	data, err := json.Marshal(tags)
	if err != nil {
		a.Tags = "[]"
		return
	}
	a.Tags = string(data)
}
