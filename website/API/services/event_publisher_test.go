package services

import (
	"sync"
	"testing"
	"time"

	"aichat-api/hub"
)

type fakeEventPublisher struct {
	mu      sync.Mutex
	user    []userEvent
	global  []hub.AppEvent
	syncChg []syncChange
}

type userEvent struct {
	userID uint
	event  hub.AppEvent
}

type syncChange struct {
	userID uint
	table  string
}

func (f *fakeEventPublisher) NotifyUserAppEvent(userID uint, event hub.AppEvent) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.user = append(f.user, userEvent{userID: userID, event: event})
}

func (f *fakeEventPublisher) NotifyGlobalAppEvent(event hub.AppEvent) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.global = append(f.global, event)
}

func (f *fakeEventPublisher) NotifySyncChange(userID uint, tableName string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.syncChg = append(f.syncChg, syncChange{userID: userID, table: tableName})
}

func TestPublishFunctionsRouteThroughEventPublisher(t *testing.T) {
	fake := &fakeEventPublisher{}
	SetEventPublisher(fake)
	t.Cleanup(func() { SetEventPublisher(nil) })

	PublishQuotaChanged(7)
	PublishSubscriptionChanged(7)
	PublishNetworkReviewStatus(7, "agent", 12, "approved", "通过", 3, "pending", time.Unix(1700000000, 0))

	if len(fake.user) != 3 {
		t.Fatalf("user events = %d, want 3", len(fake.user))
	}
	if fake.user[0].event.Scope != hub.AppEventScopeQuota || fake.user[0].userID != 7 {
		t.Fatalf("quota event = %#v", fake.user[0])
	}
	if fake.user[1].event.Scope != hub.AppEventScopeSubscription {
		t.Fatalf("subscription event = %#v", fake.user[1])
	}
	review := fake.user[2].event
	if review.Scope != hub.AppEventScopeMyUploads || review.Status != "approved" || review.Reason != "通过" {
		t.Fatalf("review event = %#v", review)
	}
	// previousStatus=pending 且 status=approved → 公共市场需要刷新
	if len(fake.global) != 1 || fake.global[0].Scope != hub.AppEventScopeNetworkAgents {
		t.Fatalf("global events = %#v", fake.global)
	}
	if len(fake.syncChg) != 0 {
		t.Fatalf("unexpected sync changes = %#v", fake.syncChg)
	}
}

func TestPublishFunctionsNoopWithoutPublisher(t *testing.T) {
	SetEventPublisher(nil)
	// 不应 panic
	PublishQuotaChanged(1)
	PublishSubscriptionChanged(1)
	PublishNetworkReviewStatus(1, "group", 2, "rejected", "x", 1, "approved", time.Time{})
}
