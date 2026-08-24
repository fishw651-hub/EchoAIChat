package models

import (
	"time"
)

type APIKey struct {
	ID              uint      `gorm:"primaryKey" json:"id"`
	Provider        string    `gorm:"size:32;default:deepseek" json:"provider"`
	Name            string    `gorm:"size:64" json:"name"`
	APIKeyEncrypted string    `gorm:"type:text;not null" json:"-"`
	BaseURL         string    `gorm:"type:text" json:"base_url"`
	ApiFormat       string    `gorm:"size:16;default:openai" json:"api_format"`
	IsActive        bool      `gorm:"default:true" json:"is_active"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

func (a *APIKey) MaskedKey() string {
	if len(a.Name) > 4 {
		return a.Name[:4] + "****"
	}
	return a.Name + "****"
}
