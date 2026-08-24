package models

type SubscriptionPlanModel struct {
	ID            uint   `json:"id"`
	PlanID        uint   `json:"plan_id"`
	ModelID       string `json:"model_id"`
	AllowThinking bool   `json:"allow_thinking"`
}
