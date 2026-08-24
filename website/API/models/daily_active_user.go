package models

import "time"

type DailyActiveUser struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"-"`
	ActiveDate    string    `json:"active_date"`
	FirstActiveAt time.Time `json:"first_active_at"`
	CreatedAt     time.Time `json:"created_at"`
}
