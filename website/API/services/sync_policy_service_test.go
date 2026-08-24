package services

import (
	"errors"
	"reflect"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

func TestSyncPolicyMigratesLegacyFullSyncToRealtimeAll(t *testing.T) {
	initSyncPolicyTestDatabase(t)
	setting := models.SyncSetting{UserID: 41, FullSyncEnabled: true}
	if err := database.Get().Register("SyncSetting").Insert(&setting); err != nil {
		t.Fatalf("insert setting: %v", err)
	}

	policy, err := NewSyncPolicyService().Get(41)
	if err != nil {
		t.Fatalf("get policy: %v", err)
	}
	if policy.ScopeMode != "all" {
		t.Fatalf("scope mode = %q, want all", policy.ScopeMode)
	}
	if !policy.RealtimeEnabled {
		t.Fatal("realtime enabled = false, want true")
	}
	if policy.Version != 1 {
		t.Fatalf("version = %d, want 1", policy.Version)
	}
}

func TestSyncPolicyUpdateRejectsStaleVersion(t *testing.T) {
	initSyncPolicyTestDatabase(t)
	service := NewSyncPolicyService()
	policy, err := service.Get(42)
	if err != nil {
		t.Fatalf("get policy: %v", err)
	}

	_, err = service.Update(42, models.SyncPolicyUpdate{
		ScopeMode:       "selected",
		ExpectedVersion: policy.Version - 1,
	})
	if !errors.Is(err, ErrSyncPolicyConflict) {
		t.Fatalf("error = %v, want ErrSyncPolicyConflict", err)
	}
}

func TestSyncPolicyUpdateNormalizesSelectedAgents(t *testing.T) {
	initSyncPolicyTestDatabase(t)
	service := NewSyncPolicyService()
	current, err := service.Get(43)
	if err != nil {
		t.Fatalf("get policy: %v", err)
	}

	updated, err := service.Update(43, models.SyncPolicyUpdate{
		ScopeMode:        "selected",
		SelectedAgentIDs: []string{" agent-b ", "agent-a", "agent-b", ""},
		RealtimeEnabled:  true,
		ExpectedVersion:  current.Version,
	})
	if err != nil {
		t.Fatalf("update policy: %v", err)
	}
	want := []string{"agent-a", "agent-b"}
	if !reflect.DeepEqual(updated.SelectedAgentIDs, want) {
		t.Fatalf("selected ids = %#v, want %#v", updated.SelectedAgentIDs, want)
	}
	if updated.Version != current.Version+1 {
		t.Fatalf("version = %d, want %d", updated.Version, current.Version+1)
	}
}

func initSyncPolicyTestDatabase(t *testing.T) {
	t.Helper()
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
}
