package hub

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func testSyncClient(hub *SyncHub, userID uint, syncEnabled bool) *SyncClient {
	return &SyncClient{
		UserID:      userID,
		DeviceID:    "device-test",
		DeviceName:  "test",
		SyncEnabled: syncEnabled,
		Send:        make(chan []byte, 4),
		Hub:         hub,
	}
}

func receiveSyncMessage(t *testing.T, client *SyncClient) SyncMessage {
	t.Helper()
	select {
	case payload := <-client.Send:
		var message SyncMessage
		if err := json.Unmarshal(payload, &message); err != nil {
			t.Fatalf("decode message: %v", err)
		}
		return message
	default:
		t.Fatal("expected websocket message")
		return SyncMessage{}
	}
}

func TestAppEventHubAllowsEventOnlyClientButRejectsChatLock(t *testing.T) {
	hub := NewSyncHub()
	client := testSyncClient(hub, 7, false)
	hub.RegisterClient(client)

	hub.NotifyUserAppEvent(7, AppEvent{
		Scope:        AppEventScopeQuota,
		EventID:      "quota:7:1",
		ResourceType: "quota",
	})
	message := receiveSyncMessage(t, client)
	if message.Type != "app_event" || message.Scope != AppEventScopeQuota {
		t.Fatalf("message = %#v, want quota app_event", message)
	}

	lockError := hub.HandleChatLock(client, SyncMessage{
		Type:    "chat_lock",
		AgentID: "agent-a",
	})
	if lockError == nil || lockError.Type != "error" {
		t.Fatalf("event-only client lock error = %#v, want error", lockError)
	}
	if _, exists := hub.locks[chatLockKey(7, "agent-a", "")]; exists {
		t.Fatal("event-only client must not create chat lock")
	}
}

func TestGlobalAppEventNeverLeaksRejectReason(t *testing.T) {
	hub := NewSyncHub()
	owner := testSyncClient(hub, 7, false)
	other := testSyncClient(hub, 8, false)
	hub.RegisterClient(owner)
	hub.RegisterClient(other)

	event := AppEvent{
		Scope:        AppEventScopeNetworkAgents,
		ResourceType: "agent",
		ResourceID:   12,
		Status:       "rejected",
		Reason:       "仅上传者可见",
		Version:      3,
		EventID:      "agent:12:3:rejected",
	}
	hub.NotifyGlobalAppEvent(event)

	for _, client := range []*SyncClient{owner, other} {
		message := receiveSyncMessage(t, client)
		if message.Reason != "" {
			t.Fatalf("global event leaked reason %q", message.Reason)
		}
	}

	hub.NotifyUserAppEvent(7, event)
	message := receiveSyncMessage(t, owner)
	if message.Reason != event.Reason {
		t.Fatalf("targeted reason = %q, want %q", message.Reason, event.Reason)
	}
	select {
	case payload := <-other.Send:
		t.Fatalf("other user received targeted event: %s", payload)
	default:
	}
}

func TestGlobalAppEventKeepsLatestScopeEventWhenNormalQueueIsFull(t *testing.T) {
	hub := NewSyncHub()
	clientReady := make(chan *SyncClient, 1)
	writeDone := make(chan struct{})
	upgrader := websocket.Upgrader{}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("upgrade websocket: %v", err)
			return
		}
		client := &SyncClient{
			UserID:   7,
			DeviceID: "device-test",
			Send:     make(chan []byte, 1),
			Conn:     conn,
			Hub:      hub,
		}
		hub.RegisterClient(client)
		client.Send <- []byte(`{"type":"sync_notify","message":"normal"}`)

		hub.NotifyGlobalAppEvent(AppEvent{
			Scope:        AppEventScopeNetworkAgents,
			ResourceType: "agent",
			ResourceID:   12,
			Status:       "taken_down",
			Reason:       "不得泄漏",
			Version:      1,
			EventID:      "agent:12:1:taken_down",
		})
		hub.NotifyGlobalAppEvent(AppEvent{
			Scope:        AppEventScopeNetworkAgents,
			ResourceType: "agent",
			ResourceID:   12,
			Status:       "deleted",
			Reason:       "同样不得泄漏",
			Version:      2,
			EventID:      "agent:12:2:deleted",
		})
		hub.NotifyGlobalAppEvent(AppEvent{
			Scope:        AppEventScopeNetworkGroups,
			ResourceType: "group",
			ResourceID:   34,
			Status:       "taken_down",
			Reason:       "同样不得泄漏",
			Version:      1,
			EventID:      "group:34:1:taken_down",
		})

		clientReady <- client
		go func() {
			client.WritePump()
			close(writeDone)
		}()
		<-writeDone
	}))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial websocket: %v", err)
	}
	defer conn.Close()

	client := <-clientReady
	defer hub.UnregisterClient(client)
	defer close(client.Send)

	conn.SetReadDeadline(time.Now().Add(time.Second))
	_, payload, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("read priority app event: %v", err)
	}
	var appEvent SyncMessage
	if err := json.Unmarshal(payload, &appEvent); err != nil {
		t.Fatalf("decode app event: %v", err)
	}
	if appEvent.Type != "app_event" ||
		appEvent.Scope != AppEventScopeNetworkAgents ||
		appEvent.Status != "deleted" ||
		appEvent.Version != 2 {
		t.Fatalf("app event = %#v, want latest network-agent event", appEvent)
	}
	if appEvent.Reason != "" {
		t.Fatalf("global app event leaked reason %q", appEvent.Reason)
	}

	conn.SetReadDeadline(time.Now().Add(time.Second))
	_, payload, err = conn.ReadMessage()
	if err != nil {
		t.Fatalf("read pending group app event: %v", err)
	}
	var groupEvent SyncMessage
	if err := json.Unmarshal(payload, &groupEvent); err != nil {
		t.Fatalf("decode group app event: %v", err)
	}
	if groupEvent.Type != "app_event" ||
		groupEvent.Scope != AppEventScopeNetworkGroups ||
		groupEvent.Status != "taken_down" ||
		groupEvent.Version != 1 {
		t.Fatalf("group app event = %#v, want pending network-group event", groupEvent)
	}
	if groupEvent.Reason != "" {
		t.Fatalf("global group app event leaked reason %q", groupEvent.Reason)
	}

	conn.SetReadDeadline(time.Now().Add(time.Second))
	_, payload, err = conn.ReadMessage()
	if err != nil {
		t.Fatalf("read normal message after app event: %v", err)
	}
	var normal SyncMessage
	if err := json.Unmarshal(payload, &normal); err != nil {
		t.Fatalf("decode normal message: %v", err)
	}
	if normal.Type != "sync_notify" || normal.Message != "normal" {
		t.Fatalf("normal message = %#v", normal)
	}
}
