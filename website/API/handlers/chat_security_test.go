package handlers

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

type countingChatService struct {
	calls int
}

func (s *countingChatService) ChatCompletion(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
	s.calls++
	return &services.ChatCompletionResponse{}, nil
}

func (s *countingChatService) ChatCompletionStream(context.Context, *services.ChatCompletionRequest, io.Writer) (*services.ChatCompletionResponse, error) {
	s.calls++
	return &services.ChatCompletionResponse{}, nil
}

func TestChatRejectsEmptyQuotaBeforeCallingUpstream(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	user := models.User{Username: "empty-quota", Status: 1, QuotaResetDate: time.Now().Format("2006-01-02")}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	price := models.ModelPrice{ModelID: "deepseek-v4-flash", Status: 1, InputPricePer1M: 1, InputCacheHitPricePer1M: 0.02, OutputPricePer1M: 2}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}
	agent := models.UserAgent{UserID: user.ID, ClientID: "empty-quota-agent", Name: "test-agent"}
	if err := services.InsertUserAgent(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}

	upstream := &countingChatService{}
	handler := &ChatHandler{deepseekService: upstream, billingService: &services.BillingService{}}
	router := gin.New()
	router.POST("/chat", func(c *gin.Context) {
		c.Set("user_id", user.ID)
		handler.ChatCompletions(c)
	})

	request := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewBufferString(`{"client_agent_id":"empty-quota-agent","request_kind":"chat","model":"deepseek-v4-flash","messages":[{"role":"user","content":"hello"}],"max_tokens":32}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusPaymentRequired {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusPaymentRequired)
	}
	if upstream.calls != 0 {
		t.Fatalf("upstream calls = %d, want 0", upstream.calls)
	}
}
