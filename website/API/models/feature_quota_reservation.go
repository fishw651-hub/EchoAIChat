package models

import "time"

// FeatureQuotaReservation reserves one discrete feature quota unit until the
// owning server-side operation commits or releases it.
type FeatureQuotaReservation struct {
	ID             uint       `json:"id"`
	ReservationID  string     `json:"reservation_id"`
	UserID         uint       `json:"user_id"`
	QuotaType      string     `json:"quota_type"`
	SubscriptionID uint       `json:"subscription_id"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"created_at"`
	FinalizedAt    *time.Time `json:"finalized_at,omitempty"`
}
