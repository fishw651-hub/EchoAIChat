package services

import (
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

func TestActiveSubscriptionsForUserScopesQueryToCurrentUser(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	table := database.Get().Register("UserSubscription")
	subscriptions := []models.UserSubscription{
		{UserID: 7, PlanID: 1, Status: 1, ExpiresAt: "2099-01-01"},
		{UserID: 7, PlanID: 2, Status: 0, ExpiresAt: "2099-01-01"},
		{UserID: 7, PlanID: 3, Status: 1, ExpiresAt: "2020-01-01"},
		{UserID: 8, PlanID: 4, Status: 1, ExpiresAt: "2099-01-01"},
	}
	for i := range subscriptions {
		if err := table.Insert(&subscriptions[i]); err != nil {
			t.Fatalf("insert subscription %d: %v", i, err)
		}
	}

	got := ActiveSubscriptionsForUser(7)
	if len(got) != 1 {
		t.Fatalf("active subscriptions = %d, want 1", len(got))
	}
	if got[0].UserID != 7 || got[0].PlanID != 1 {
		t.Fatalf("unexpected subscription: %+v", got[0])
	}
}
