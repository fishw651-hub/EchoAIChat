package models

import "time"

// ProactiveCareClaim is the server-authoritative single-use claim for one
// proactive message. A pending claim reserves both the daily slot and one
// real-reply feature unit until committed or released.
type ProactiveCareClaim struct {
	ID                   uint       `json:"id"`
	ClaimToken           string     `json:"claim_token"`
	UserID               uint       `json:"user_id"`
	ClientAgentID        string     `json:"client_agent_id"`
	FeatureReservationID string     `json:"feature_reservation_id"`
	Status               string     `json:"status"`
	CreatedAt            time.Time  `json:"created_at"`
	FinalizedAt          *time.Time `json:"finalized_at,omitempty"`
}
