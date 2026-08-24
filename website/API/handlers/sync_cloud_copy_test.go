package handlers

import (
	"net/http"
	"testing"

	"aichat-api/database"

	"github.com/gin-gonic/gin"
)

func TestDeleteCloudCopyOnlyRemovesSelectedAgentData(t *testing.T) {
	initDevicePolicyTestDatabase(t)
	gin.SetMode(gin.TestMode)
	const userID uint = 91

	database.Get().Register("SyncAgent").BatchUpsertByUserIDClientID(userID, []map[string]interface{}{
		{"client_id": "agent-a", "name": "A"},
		{"client_id": "agent-b", "name": "B"},
	})
	database.Get().Register("SyncChatMessage").BatchUpsertByUserIDClientID(userID, []map[string]interface{}{
		{"client_id": "message-a", "agent_id": "agent-a", "content": "A"},
		{"client_id": "message-b", "agent_id": "agent-b", "content": "B"},
	})

	recorder := performDevicePolicyRequest(t, http.MethodDelete, "/sync/cloud", map[string]interface{}{
		"scope_mode":       "selected",
		"selected_agent_ids": []string{"agent-a"},
	}, userID, (&SyncHandler{}).DeleteCloudCopy)
	if recorder.Code != http.StatusOK {
		t.Fatalf("delete status = %d, body=%s", recorder.Code, recorder.Body.String())
	}

	if _, ok := database.Get().Register("SyncAgent").FindByUserIDClientID(userID, "agent-a"); ok {
		t.Fatal("selected agent cloud copy still exists")
	}
	if _, ok := database.Get().Register("SyncChatMessage").FindByUserIDClientID(userID, "message-a"); ok {
		t.Fatal("selected agent chat cloud copy still exists")
	}
	if _, ok := database.Get().Register("SyncAgent").FindByUserIDClientID(userID, "agent-b"); !ok {
		t.Fatal("unselected agent cloud copy was deleted")
	}
	if _, ok := database.Get().Register("SyncChatMessage").FindByUserIDClientID(userID, "message-b"); !ok {
		t.Fatal("unselected agent chat cloud copy was deleted")
	}
}
