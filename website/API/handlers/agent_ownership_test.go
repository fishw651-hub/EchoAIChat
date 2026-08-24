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
	"aichat-api/utils"
	"github.com/gin-gonic/gin"
)

func TestRequireOwnedAgentRejectsAnotherUser(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	agent := models.UserAgent{UserID: 1, ClientID: "client-agent-a", Name: "A"}
	if err := services.InsertUserAgent(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}
	if _, err := services.RequireOwnedAgent(2, "client-agent-a"); err == nil {
		t.Fatal("expected cross-account ownership error")
	}
	owned, err := services.RequireOwnedAgent(1, "client-agent-a")
	if err != nil || owned == nil || owned.ID != agent.ID {
		t.Fatalf("owned lookup = (%v, %v), want agent %d", owned, err, agent.ID)
	}
}

func TestChatRejectsAgentOwnedByAnotherUserBeforeBilling(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	agent := models.UserAgent{UserID: 1, ClientID: "cross-account-agent", Name: "A"}
	if err := services.InsertUserAgent(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}

	gin.SetMode(gin.TestMode)
	router := gin.New()
	handler := NewChatHandler()
	router.POST("/chat", func(c *gin.Context) {
		c.Set("user_id", uint(2))
		handler.ChatCompletions(c)
	})
	body, _ := json.Marshal(map[string]interface{}{
		"client_agent_id": "cross-account-agent",
		"request_kind":    "chat",
		"model":           "deepseek-v4-flash",
		"messages":        []map[string]string{{"role": "user", "content": "hi"}},
	})
	request := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusForbidden)
	}
}

func TestChatRequiresHardProtocolFields(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	handler := NewChatHandler()
	router.POST("/chat", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		handler.ChatCompletions(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewBufferString(`{"model":"deepseek-v4-flash","messages":[]}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var envelope struct {
		Code int `json:"code"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.Code != utils.CodeBadRequest {
		t.Fatalf("response code = %d, want %d", envelope.Code, utils.CodeBadRequest)
	}
}
