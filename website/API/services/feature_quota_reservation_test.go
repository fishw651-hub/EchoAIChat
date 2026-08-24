package services

import (
	"errors"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

func TestFeatureQuotaReservationCanOnlyFinalizeOnce(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	user := models.User{Username: "feature-quota", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	reservation, err := ReserveFeatureQuota(user.ID, "real_reply")
	if err != nil {
		t.Fatalf("reserve: %v", err)
	}
	if err := CommitFeatureQuota(reservation.ReservationID); err != nil {
		t.Fatalf("commit: %v", err)
	}
	if err := ReleaseFeatureQuota(reservation.ReservationID); !errors.Is(err, ErrReservationFinalized) {
		t.Fatalf("release after commit = %v, want ErrReservationFinalized", err)
	}
}
