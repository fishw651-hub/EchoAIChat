package models

import "time"

type IfdianPlan struct {
	ID           uint    `json:"id"`
	IfdianPlanID string  `json:"ifdian_plan_id"`
	Name         string  `json:"name"`
	Price        float64 `json:"price"`
	PlanType     string  `json:"plan_type"`
	MappingType  string  `json:"mapping_type"`
	LocalPlanID  uint    `json:"local_plan_id"`
	PlanName     string  `json:"plan_name"`
	Amount       float64 `json:"amount"`
	DailyQuota   float64 `json:"daily_quota"`
	DurationDays int     `json:"duration_days"`
	Status       int     `json:"status"`
}

type IfdianRecord struct {
	ID           uint      `json:"id"`
	UserID       uint      `json:"user_id"`
	IfdianUserID string    `json:"ifdian_user_id"`
	OutTradeNo   string    `json:"out_trade_no"`
	PlanID       string    `json:"plan_id"`
	PlanName     string    `json:"plan_name"`
	Amount       float64   `json:"amount"`
	MappingType  string    `json:"mapping_type"`
	Granted      bool      `json:"granted"`
	CreatedAt    time.Time `json:"created_at"`
}
