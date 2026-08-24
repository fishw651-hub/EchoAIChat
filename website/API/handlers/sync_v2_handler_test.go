package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

func TestSyncV2FiltersUploadAndDownloadBySelectedScope(t *testing.T) {
	initDevicePolicyTestDatabase(t)
	gin.SetMode(gin.TestMode)
	const userID uint = 81
	insertSyncV2Device(t, userID, "device-a")

	policyService := services.NewSyncPolicyService()
	current, err := policyService.Get(userID)
	if err != nil {
		t.Fatalf("get policy: %v", err)
	}
	policy, err := policyService.Update(userID, models.SyncPolicyUpdate{
		ScopeMode: "selected", SelectedAgentIDs: []string{"agent-a"},
		ExpectedVersion: current.Version,
	})
	if err != nil {
		t.Fatalf("update policy: %v", err)
	}

	cloudB := map[string]interface{}{
		"client_id": "agent-b", "name": "cloud-b",
		"updated_at": time.Now().Add(-time.Minute).UTC().Format(time.RFC3339Nano),
	}
	database.Get().Register("SyncAgent").BatchUpsertByUserIDClientID(userID, []map[string]interface{}{cloudB})

	tables := map[string]interface{}{
		"agents": map[string]interface{}{"items": []map[string]interface{}{
			{"client_id": "agent-a", "name": "local-a", "updated_at": time.Now().UTC().Format(time.RFC3339Nano)},
			{"client_id": "agent-b", "name": "local-b", "updated_at": time.Now().UTC().Format(time.RFC3339Nano)},
		}},
		"providers": map[string]interface{}{"items": []map[string]interface{}{
			{"client_id": "provider-1", "name": "must-not-upload"},
		}},
	}
	handler := &SyncV2Handler{
		PolicyService: policyService,
		PreviewStore:  services.NewSyncPreviewStore(),
	}
	previewBody := map[string]interface{}{
		"mode": "immediate", "policy_version": policy.Version, "tables": tables,
	}
	preview := performSyncV2Request(t, "/sync/v2/preview", previewBody, userID, "device-a", handler.Preview)
	token := responseDataString(t, preview, "preview_token")

	runBody := map[string]interface{}{
		"preview_token": token, "mode": "immediate",
		"policy_version": policy.Version, "tables": tables,
	}
	run := performSyncV2Request(t, "/sync/v2/run", runBody, userID, "device-a", handler.Run)
	if run.Code != http.StatusOK {
		t.Fatalf("run status = %d body=%s", run.Code, run.Body.String())
	}
	var runEnvelope map[string]interface{}
	if err := json.Unmarshal(run.Body.Bytes(), &runEnvelope); err != nil {
		t.Fatalf("decode run response: %v", err)
	}
	if runEnvelope["code"] != float64(0) {
		t.Fatalf("run response = %s", run.Body.String())
	}

	if _, ok := database.Get().Register("SyncAgent").FindByUserIDClientID(userID, "agent-a"); !ok {
		t.Fatalf("selected agent-a was not uploaded; response=%s", run.Body.String())
	}
	storedB, ok := database.Get().Register("SyncAgent").FindByUserIDClientID(userID, "agent-b")
	if !ok || syncTestString(storedB, "Name", "name") != "cloud-b" {
		t.Fatalf("unselected agent-b was modified: %#v", storedB)
	}
	if _, ok := database.Get().Register("SyncProvider").FindByUserIDClientID(userID, "provider-1"); ok {
		t.Fatal("global provider bypassed selected scope")
	}

	data := responseDataMap(t, run)
	agents := data["tables"].(map[string]interface{})["agents"].([]interface{})
	if len(agents) != 1 || agents[0].(map[string]interface{})["ClientID"] != "agent-a" {
		t.Fatalf("downloaded agents = %#v, want only agent-a", agents)
	}
}

func TestSyncV2MergeReportsOnlyActualCloudChanges(t *testing.T) {
	initDevicePolicyTestDatabase(t)
	const userID uint = 82
	now := time.Now().UTC()
	database.Get().Register("SyncAgent").BatchUpsertByUserIDClientID(userID, []map[string]interface{}{
		{"client_id": "agent-a", "name": "cloud-new", "updated_at": now.Format(time.RFC3339Nano)},
	})
	handler := &SyncV2Handler{}
	scope := services.NewSelectedSyncScope([]string{"agent-a"})

	changes, err := handler.mergeAndPersist(
		context.Background(),
		userID,
		scope,
		map[string]syncV2TablePayload{
			"agents": {Items: []map[string]interface{}{
				{"client_id": "agent-a", "name": "local-old", "updated_at": now.Add(-time.Minute).Format(time.RFC3339Nano)},
			}},
		},
	)
	if err != nil {
		t.Fatalf("merge older local: %v", err)
	}
	if len(changes) != 0 {
		t.Fatalf("older local produced realtime changes: %#v", changes)
	}
}

func performSyncV2Request(
	t *testing.T,
	path string,
	body map[string]interface{},
	userID uint,
	deviceID string,
	handler gin.HandlerFunc,
) *httptest.ResponseRecorder {
	t.Helper()
	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Set("user_id", userID)
	context.Request = httptest.NewRequest(http.MethodPost, path, bytes.NewReader(payload))
	context.Request.Header.Set("Content-Type", "application/json")
	context.Request.Header.Set("X-Device-ID", deviceID)
	handler(context)
	return recorder
}

func responseDataMap(t *testing.T, recorder *httptest.ResponseRecorder) map[string]interface{} {
	t.Helper()
	var response map[string]interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	data, ok := response["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("response data = %#v", response["data"])
	}
	return data
}

func responseDataString(t *testing.T, recorder *httptest.ResponseRecorder, key string) string {
	t.Helper()
	data := responseDataMap(t, recorder)
	value, ok := data[key].(string)
	if !ok || value == "" {
		t.Fatalf("response %s = %#v body=%s", key, data[key], recorder.Body.String())
	}
	return value
}

func insertSyncV2Device(t *testing.T, userID uint, deviceID string) {
	t.Helper()
	device := models.Device{UserID: userID, DeviceID: deviceID, DeviceName: "test device"}
	if err := database.Get().Register("Device").Insert(&device); err != nil {
		t.Fatalf("insert device: %v", err)
	}
}

func syncTestString(item map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if value, ok := item[key].(string); ok {
			return value
		}
	}
	return ""
}
