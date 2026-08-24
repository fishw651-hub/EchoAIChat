package services

import (
	"errors"
	"testing"
	"time"
)

func TestSyncPreviewTokenRejectsChangedDevicePolicyScopeOrPayload(t *testing.T) {
	now := time.Date(2026, 7, 15, 2, 0, 0, 0, time.UTC)
	store := newSyncPreviewStore(5*time.Minute, func() time.Time { return now })
	binding := SyncPreviewBinding{
		UserID: 91, DeviceID: "device-a", Mode: "one_shot", PolicyVersion: 4,
		Scope: NewSelectedSyncScope([]string{"agent-a"}), PayloadHash: "hash-a",
	}

	checks := []SyncPreviewBinding{
		{UserID: 91, DeviceID: "device-b", Mode: "one_shot", PolicyVersion: 4, Scope: binding.Scope, PayloadHash: "hash-a"},
		{UserID: 91, DeviceID: "device-a", Mode: "one_shot", PolicyVersion: 5, Scope: binding.Scope, PayloadHash: "hash-a"},
		{UserID: 91, DeviceID: "device-a", Mode: "one_shot", PolicyVersion: 4, Scope: NewSelectedSyncScope([]string{"agent-b"}), PayloadHash: "hash-a"},
		{UserID: 91, DeviceID: "device-a", Mode: "one_shot", PolicyVersion: 4, Scope: binding.Scope, PayloadHash: "hash-b"},
	}
	for index, changed := range checks {
		token, _, err := store.Issue(binding)
		if err != nil {
			t.Fatalf("issue %d: %v", index, err)
		}
		if err := store.Consume(token, changed); !errors.Is(err, ErrSyncPreviewChanged) {
			t.Fatalf("check %d error = %v, want ErrSyncPreviewChanged", index, err)
		}
	}
}

func TestSyncPreviewTokenExpiresAndIsSingleUse(t *testing.T) {
	now := time.Date(2026, 7, 15, 2, 0, 0, 0, time.UTC)
	store := newSyncPreviewStore(time.Minute, func() time.Time { return now })
	binding := SyncPreviewBinding{
		UserID: 92, DeviceID: "device-a", Mode: "immediate", PolicyVersion: 1,
		Scope: NewAllSyncScope(), PayloadHash: "hash-a",
	}

	token, _, err := store.Issue(binding)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if err := store.Consume(token, binding); err != nil {
		t.Fatalf("first consume: %v", err)
	}
	if err := store.Consume(token, binding); !errors.Is(err, ErrSyncPreviewInvalid) {
		t.Fatalf("second consume error = %v, want invalid", err)
	}

	expiredToken, _, err := store.Issue(binding)
	if err != nil {
		t.Fatalf("issue expired token: %v", err)
	}
	now = now.Add(2 * time.Minute)
	if err := store.Consume(expiredToken, binding); !errors.Is(err, ErrSyncPreviewExpired) {
		t.Fatalf("expired error = %v, want expired", err)
	}
}
