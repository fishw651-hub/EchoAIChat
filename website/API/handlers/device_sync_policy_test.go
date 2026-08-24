package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

func TestRegisterDeviceStoresBrowserIdentityAndPreservesName(t *testing.T) {
	initDevicePolicyTestDatabase(t)
	gin.SetMode(gin.TestMode)
	handler := &DeviceHandler{}

	first := performDevicePolicyRequest(t, http.MethodPost, "/sync/devices/register", map[string]interface{}{
		"device_id": "edge-profile", "device_name": "Windows · Edge",
		"client_kind": "web", "platform": "Windows", "browser": "Edge",
	}, 71, handler.RegisterDevice)
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200", first.Code)
	}

	second := performDevicePolicyRequest(t, http.MethodPost, "/sync/devices/register", map[string]interface{}{
		"device_id": "edge-profile", "device_name": "",
		"client_kind": "web", "platform": "Windows", "browser": "Edge",
	}, 71, handler.RegisterDevice)
	if second.Code != http.StatusOK {
		t.Fatalf("second status = %d, want 200", second.Code)
	}

	var device models.Device
	if !database.Get().Register("Device").FindOne(database.FilterAll(
		database.FilterEq("UserID", uint(71)),
		database.FilterEq("DeviceID", "edge-profile"),
	), &device) {
		t.Fatal("registered device not found")
	}
	if device.DeviceName != "Windows · Edge" {
		t.Fatalf("device name = %q, want preserved name", device.DeviceName)
	}
	if device.ClientKind != "web" || device.Browser != "Edge" {
		t.Fatalf("identity = %q/%q, want web/Edge", device.ClientKind, device.Browser)
	}
}

func TestSyncPolicyHandlerRejectsStaleVersionWithConflict(t *testing.T) {
	initDevicePolicyTestDatabase(t)
	gin.SetMode(gin.TestMode)
	handler := &SyncPolicyHandler{Service: services.NewSyncPolicyService()}

	get := performDevicePolicyRequest(t, http.MethodGet, "/sync/policy", nil, 72, handler.Get)
	if get.Code != http.StatusOK {
		t.Fatalf("get status = %d, want 200", get.Code)
	}

	put := performDevicePolicyRequest(t, http.MethodPut, "/sync/policy", map[string]interface{}{
		"scope_mode": "selected", "selected_agent_ids": []string{"agent-a"},
		"realtime_enabled": true, "expected_version": 0,
	}, 72, handler.Update)
	if put.Code != http.StatusConflict {
		t.Fatalf("put status = %d, want 409", put.Code)
	}
}

func performDevicePolicyRequest(
	t *testing.T,
	method string,
	path string,
	body map[string]interface{},
	userID uint,
	handler gin.HandlerFunc,
) *httptest.ResponseRecorder {
	t.Helper()
	var payload []byte
	if body != nil {
		var err error
		payload, err = json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
	}
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Set("user_id", userID)
	context.Request = httptest.NewRequest(method, path, bytes.NewReader(payload))
	context.Request.Header.Set("Content-Type", "application/json")
	handler(context)
	return recorder
}

func initDevicePolicyTestDatabase(t *testing.T) {
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
