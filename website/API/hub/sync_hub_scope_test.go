package hub

import (
	"encoding/json"
	"testing"
	"time"

	"aichat-api/models"
)

func TestNotifyDataChangeExcludesSourceAndUnselectedAgent(t *testing.T) {
	hub := NewSyncHub()
	source := &SyncClient{UserID: 101, DeviceID: "source", Send: make(chan []byte, 2), Hub: hub}
	other := &SyncClient{UserID: 101, DeviceID: "other", Send: make(chan []byte, 2), Hub: hub}
	hub.RegisterClient(source)
	hub.RegisterClient(other)
	policy := models.SyncPolicy{
		ScopeMode: "selected", SelectedAgentIDs: []string{"agent-a"},
		RealtimeEnabled: true, Version: 4,
	}

	hub.NotifyDataChange(101, "source", "chat_messages", "agent-b", policy)
	assertNoSyncHubMessage(t, source.Send)
	assertNoSyncHubMessage(t, other.Send)

	hub.NotifyDataChange(101, "source", "chat_messages", "agent-a", policy)
	assertNoSyncHubMessage(t, source.Send)
	select {
	case payload := <-other.Send:
		var message SyncMessage
		if err := json.Unmarshal(payload, &message); err != nil {
			t.Fatalf("decode message: %v", err)
		}
		if message.AgentID != "agent-a" || message.DeviceID != "source" || message.PolicyVersion != 4 {
			t.Fatalf("message = %#v", message)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("other device did not receive selected agent event")
	}
}

func TestUnregisterClientDoesNotReleaseAnotherUsersLockForSameDeviceID(t *testing.T) {
	hub := NewSyncHub()
	firstUser := &SyncClient{
		UserID:      101,
		DeviceID:    "shared-device",
		SyncEnabled: true,
		Send:        make(chan []byte, 2),
		Hub:         hub,
	}
	secondUser := &SyncClient{
		UserID:      202,
		DeviceID:    "shared-device",
		SyncEnabled: true,
		Send:        make(chan []byte, 2),
		Hub:         hub,
	}
	secondUserOtherDevice := &SyncClient{
		UserID:      202,
		DeviceID:    "other-device",
		SyncEnabled: true,
		Send:        make(chan []byte, 2),
		Hub:         hub,
	}
	for _, client := range []*SyncClient{firstUser, secondUser, secondUserOtherDevice} {
		hub.RegisterClient(client)
	}

	message := SyncMessage{AgentID: "agent-a", Status: "waiting"}
	if conflict := hub.HandleChatLock(firstUser, message); conflict != nil {
		t.Fatalf("first user lock conflict = %#v, want nil", conflict)
	}
	if conflict := hub.HandleChatLock(secondUser, message); conflict != nil {
		t.Fatalf("second user lock conflict = %#v, want nil", conflict)
	}

	hub.UnregisterClient(firstUser)

	if conflict := hub.HandleChatLock(secondUserOtherDevice, message); conflict == nil {
		t.Fatal("another user's lock was released when the first user disconnected")
	}
}

func TestHandleChatLockAcknowledgesRequestingDevice(t *testing.T) {
	hub := NewSyncHub()
	client := &SyncClient{
		UserID:      303,
		DeviceID:    "requesting-device",
		DeviceName:  "phone",
		SyncEnabled: true,
		Send:        make(chan []byte, 2),
		Hub:         hub,
	}
	hub.RegisterClient(client)

	message := SyncMessage{AgentID: "agent-a", Status: "waiting"}
	if conflict := hub.HandleChatLock(client, message); conflict != nil {
		t.Fatalf("lock conflict = %#v, want nil", conflict)
	}

	select {
	case payload := <-client.Send:
		var acknowledged SyncMessage
		if err := json.Unmarshal(payload, &acknowledged); err != nil {
			t.Fatalf("decode acknowledgement: %v", err)
		}
		if acknowledged.Type != "lock_status" || acknowledged.DeviceID != client.DeviceID || acknowledged.AgentID != "agent-a" {
			t.Fatalf("acknowledgement = %#v", acknowledged)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("requesting device did not receive lock acknowledgement")
	}
}

func assertNoSyncHubMessage(t *testing.T, channel <-chan []byte) {
	t.Helper()
	select {
	case payload := <-channel:
		t.Fatalf("unexpected message: %s", payload)
	default:
	}
}
