package services

import (
	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

// ActiveSubscriptionsForUser loads only the current user's enabled
// subscriptions. Expiry is checked after the indexed user/status filters.
func ActiveSubscriptionsForUser(userID uint) []models.UserSubscription {
	today := utils.TodayCN()
	var subscriptions []models.UserSubscription
	database.Get().Register("UserSubscription").FindAll(
		&subscriptions,
		database.FilterAll(
			database.FilterEq("UserID", userID),
			database.FilterEq("Status", 1),
		),
		"ID desc",
		0,
		0,
	)

	active := make([]models.UserSubscription, 0, len(subscriptions))
	for _, subscription := range subscriptions {
		if subscription.ExpiresAt >= today {
			active = append(active, subscription)
		}
	}
	return active
}

// HasActiveSubscriptionForUser is the low-allocation boolean form used by
// middleware and other entitlement checks.
func HasActiveSubscriptionForUser(userID uint) bool {
	return len(ActiveSubscriptionsForUser(userID)) > 0
}
