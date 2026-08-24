package handlers

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/hub"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func TestAdminTakeDownPublishesPublicMarketInvalidation(t *testing.T) {
	tests := []struct {
		name          string
		path          string
		register      string
		resourceType  string
		expectedScope string
		insert        func(t *testing.T) uint
		attach        func(router *gin.Engine, handler *NetworkAdminHandler)
	}{
		{
			name:          "agent",
			path:          "/agents/1",
			register:      "NetworkAgent",
			resourceType:  "agent",
			expectedScope: hub.AppEventScopeNetworkAgents,
			insert: func(t *testing.T) uint {
				record := models.NetworkAgent{UploaderID: 7, Name: "公开智能体", Status: "approved", Version: 3}
				if err := database.Get().Register("NetworkAgent").Insert(&record); err != nil {
					t.Fatal(err)
				}
				return record.ID
			},
			attach: func(router *gin.Engine, handler *NetworkAdminHandler) {
				router.PUT("/agents/:id", handler.AdminEditAgent)
			},
		},
		{
			name:          "group",
			path:          "/groups/1",
			register:      "NetworkGroup",
			resourceType:  "group",
			expectedScope: hub.AppEventScopeNetworkGroups,
			insert: func(t *testing.T) uint {
				record := models.NetworkGroup{UploaderID: 7, Name: "公开群聊", Status: "approved", Version: 3}
				if err := database.Get().Register("NetworkGroup").Insert(&record); err != nil {
					t.Fatal(err)
				}
				return record.ID
			},
			attach: func(router *gin.Engine, handler *NetworkAdminHandler) {
				router.PUT("/groups/:id", handler.AdminEditGroup)
			},
		},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			setupAiReviewTestDB(t)
			previousHub := hub.Hub
			syncHub := hub.NewSyncHub()
			hub.Hub = syncHub
			services.SetEventPublisher(syncHub)
			t.Cleanup(func() {
				hub.Hub = previousHub
				services.SetEventPublisher(nil)
			})

			client := &hub.SyncClient{
				UserID:   7,
				DeviceID: "test-device",
				Send:     make(chan []byte, 4),
				Hub:      syncHub,
			}
			syncHub.RegisterClient(client)
			t.Cleanup(func() { syncHub.UnregisterClient(client) })

			id := testCase.insert(t)
			if id != 1 {
				t.Fatalf("inserted %s id = %d, want 1", testCase.register, id)
			}

			router := gin.New()
			testCase.attach(router, &NetworkAdminHandler{})
			recorder := doJSON(router, http.MethodPut, testCase.path, `{"force_take_down":true}`)
			if recorder.Code != http.StatusOK {
				t.Fatalf("take down response = %d, body=%s", recorder.Code, recorder.Body.String())
			}

			var response struct {
				Code int `json:"code"`
			}
			if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
				t.Fatal(err)
			}
			if response.Code != utils.CodeSuccess {
				t.Fatalf("response code = %d, want %d", response.Code, utils.CodeSuccess)
			}

			for range 2 {
				var payload []byte
				select {
				case payload = <-client.Send:
				case <-time.After(time.Second):
					t.Fatalf("timed out waiting for %s invalidation", testCase.expectedScope)
				}
				var event hub.SyncMessage
				if err := json.Unmarshal(payload, &event); err != nil {
					t.Fatal(err)
				}
				if event.Scope != testCase.expectedScope {
					continue
				}
				if event.Type != "app_event" || event.ResourceType != testCase.resourceType ||
					event.Status != "taken_down" || event.Reason != "" {
					t.Fatalf("public event = %#v", event)
				}
				return
			}
			t.Fatalf("did not receive %s public invalidation", testCase.expectedScope)
		})
	}
}
