package models

import (
	"time"
)

type UserAgent struct {
	ID                            uint      `gorm:"primaryKey" json:"id"`
	UserID                        uint      `gorm:"index;not null" json:"user_id"`
	ClientID                      string    `gorm:"index;size:128" json:"client_id"`
	Name                          string    `gorm:"size:128;not null" json:"name"`
	Gender                        string    `gorm:"size:16" json:"gender"`
	Description                   string    `gorm:"type:text" json:"description"`
	Persona                       string    `gorm:"type:text" json:"persona"`
	OpeningLine                   string    `gorm:"type:text" json:"opening_line"`
	AvatarColor                   int       `json:"avatar_color"`
	AvatarPath                    string    `gorm:"size:512" json:"avatar_path"`
	ChatBackground                string    `gorm:"size:512" json:"chat_background"`
	Worldview                     string    `gorm:"type:text" json:"worldview"`
	MaxResponseLength             int       `json:"max_response_length"`
	IsSimCharacter                bool      `json:"is_sim_character"`
	RealInfoEnabled               bool      `json:"real_info_enabled"`
	ProactiveCareEnabled          bool      `json:"proactive_care_enabled"`
	ProactiveCareDailyLimit       int       `json:"proactive_care_daily_limit"`
	ProactiveCareMinIntervalHours int       `json:"proactive_care_min_interval_hours"`
	CreatedAt                     time.Time `json:"created_at"`
	UpdatedAt                     time.Time `json:"updated_at"`
}
