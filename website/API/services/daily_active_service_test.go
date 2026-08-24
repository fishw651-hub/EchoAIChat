package services

import (
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

func TestDailyActiveServiceTrackDeduplicatesUserPerDay(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	service := NewDailyActiveService()
	now := time.Date(2026, 7, 20, 10, 30, 0, 0, time.Local)
	if err := service.Track(42, "user", now); err != nil {
		t.Fatalf("first track: %v", err)
	}
	if err := service.Track(42, "user", now.Add(2*time.Hour)); err != nil {
		t.Fatalf("second track: %v", err)
	}

	var records []models.DailyActiveUser
	database.Get().Register("DailyActiveUser").FindAll(&records, nil, "", 0, 0)
	if len(records) != 1 {
		t.Fatalf("daily active records = %d, want 1", len(records))
	}
	if records[0].UserID != 42 {
		t.Fatalf("user id = %d, want 42", records[0].UserID)
	}
	if records[0].ActiveDate != "2026-07-20" {
		t.Fatalf("active date = %q, want 2026-07-20", records[0].ActiveDate)
	}
}

func TestDailyActiveServiceTrackIgnoresAdministrators(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	service := NewDailyActiveService()
	now := time.Date(2026, 7, 20, 10, 30, 0, 0, time.Local)
	for _, role := range []string{"admin", "super_admin"} {
		if err := service.Track(42, role, now); err != nil {
			t.Fatalf("track %s: %v", role, err)
		}
	}

	if count := database.Get().Register("DailyActiveUser").Count(nil); count != 0 {
		t.Fatalf("daily active records = %d, want 0", count)
	}
}

func TestGetDailyActiveStatsBuildsContinuousTrend(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	service := NewDailyActiveService()
	now := time.Date(2026, 7, 20, 18, 0, 0, 0, time.Local)
	activity := []struct {
		userID uint
		date   time.Time
	}{
		{userID: 1, date: now.AddDate(0, 0, -4)},
		{userID: 2, date: now.AddDate(0, 0, -4)},
		{userID: 3, date: now.AddDate(0, 0, -4)},
		{userID: 1, date: now.AddDate(0, 0, -1)},
		{userID: 1, date: now},
		{userID: 2, date: now},
	}
	for _, item := range activity {
		if err := service.Track(item.userID, "user", item.date); err != nil {
			t.Fatalf("track user %d: %v", item.userID, err)
		}
	}

	stats, err := GetDailyActiveStats(7, now)
	if err != nil {
		t.Fatalf("get stats: %v", err)
	}
	if len(stats.Trend) != 7 {
		t.Fatalf("trend length = %d, want 7", len(stats.Trend))
	}
	if stats.Trend[0].Date != "2026-07-14" || stats.Trend[6].Date != "2026-07-20" {
		t.Fatalf("trend dates = %q..%q, want 2026-07-14..2026-07-20", stats.Trend[0].Date, stats.Trend[6].Date)
	}
	if stats.Trend[1].Count != 0 || stats.Trend[2].Count != 3 || stats.Trend[5].Count != 1 || stats.Trend[6].Count != 2 {
		t.Fatalf("unexpected trend counts: %+v", stats.Trend)
	}
	if stats.Today != 2 || stats.Yesterday != 1 {
		t.Fatalf("today/yesterday = %d/%d, want 2/1", stats.Today, stats.Yesterday)
	}
	if stats.ChangePercent != 100 {
		t.Fatalf("change percent = %.2f, want 100", stats.ChangePercent)
	}
	if stats.Peak != 3 {
		t.Fatalf("peak = %d, want 3", stats.Peak)
	}
	if stats.Average < 0.8571 || stats.Average > 0.8572 {
		t.Fatalf("average = %.4f, want about 0.8571", stats.Average)
	}
}
