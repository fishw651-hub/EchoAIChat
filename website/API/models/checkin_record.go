package models

import "time"

type CheckInRecord struct {
	ID          uint      `json:"id"`
	UserID      uint      `json:"user_id"`
	CheckInDate string    `json:"checkin_date"`
	Reward      float64   `json:"reward"`
	CreatedAt   time.Time `json:"created_at"`
}
