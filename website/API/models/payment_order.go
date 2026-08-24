package models

import (
	"time"
)

type PaymentOrder struct {
	ID            uint       `gorm:"primaryKey" json:"id"`
	UserID        uint       `gorm:"index;not null" json:"user_id"`
	Username      string     `gorm:"size:64" json:"username"`
	OrderNo       string     `gorm:"uniqueIndex;size:64;not null" json:"order_no"`
	TradeNo       string     `gorm:"size:64" json:"trade_no"`
	Type          string     `gorm:"size:16;not null" json:"type"`
	PlanID        *uint      `json:"plan_id,omitempty"`
	PlanName      string     `gorm:"size:128" json:"plan_name"`
	Amount        float64    `gorm:"type:decimal(10,2);not null" json:"amount"`
	ActualAmount  float64    `gorm:"type:decimal(10,2);default:0" json:"actual_amount"`
	Status        string     `gorm:"size:16;default:pending" json:"status"`
	PaymentType   string     `gorm:"size:16" json:"payment_type"`
	PaidAt        *time.Time `json:"paid_at,omitempty"`
	Processed     bool       `json:"processed"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}
