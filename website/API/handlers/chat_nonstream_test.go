package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aichat-api/database"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type nonStream429Service struct {
	calls int
}

func (s *nonStream429Service) ChatCompletion(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
	s.calls++
	return nil, &services.UpstreamHTTPError{
		Provider:   "grok",
		StatusCode: http.StatusTooManyRequests,
		Body:       `{"error":{"type":"rate_limit_exceeded"}}`,
		RetryAfter: "7",
	}
}

func (s *nonStream429Service) ChatCompletionViaStream(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
	return s.ChatCompletion(context.Background(), nil)
}

type recordingBillingService struct {
	releases int
	settles  int
	cost     float64
}

func (s *recordingBillingService) Reserve(uint, string, []services.ChatMessage, int, bool) (*services.BillingReservation, error) {
	return &services.BillingReservation{ID: "reservation-1"}, nil
}

func (s *recordingBillingService) Release(string) error {
	s.releases++
	return nil
}

func (s *recordingBillingService) Settle(string, string, string, int, int, int, int, bool) (float64, error) {
	s.settles++
	return s.cost, nil
}

type nonStreamSuccessService struct {
	calls int
}

func (s *nonStreamSuccessService) ChatCompletion(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
	s.calls++
	var result services.ChatCompletionResponse
	if err := json.Unmarshal([]byte(`{
		"id":"completion-1",
		"created":1,
		"model":"grok4.5",
		"choices":[{
			"index":0,
			"message":{"role":"assistant","content":"","tool_calls":[{"id":"call-1","type":"function","function":{"name":"chat","arguments":"{\"message\":\"ok\"}"}}]},
			"finish_reason":"tool_calls"
		}],
		"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}
	}`), &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func (s *nonStreamSuccessService) ChatCompletionViaStream(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
	return s.ChatCompletion(context.Background(), nil)
}

func TestChatCompletionsMapUpstream429BeforeWritingResponse(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	tests := []struct {
		name    string
		handler func(*ChatHandler, *gin.Context)
	}{
		{name: "json", handler: func(h *ChatHandler, c *gin.Context) { h.ChatCompletions(c) }},
		{name: "legacy stream", handler: func(h *ChatHandler, c *gin.Context) { h.ChatCompletionsStream(c) }},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upstream := &nonStream429Service{}
			billing := &recordingBillingService{}
			handler := &ChatHandler{deepseekService: upstream, billingService: billing}
			request := httptest.NewRequest(
				http.MethodPost,
				"/chat",
				bytes.NewBufferString(`{"request_kind":"utility","model":"grok4.5","messages":[{"role":"user","content":"hello"}],"max_tokens":32}`),
			)
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			context, _ := gin.CreateTestContext(response)
			context.Request = request
			context.Set("user_id", uint(1))

			tt.handler(handler, context)

			if response.Code != http.StatusTooManyRequests {
				t.Fatalf("status = %d, want %d; body=%s", response.Code, http.StatusTooManyRequests, response.Body.String())
			}
			var body utils.Response
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode response: %v; body=%s", err, response.Body.String())
			}
			if body.Code != utils.CodeTooManyReqs {
				t.Fatalf("code = %d, want %d", body.Code, utils.CodeTooManyReqs)
			}
			if response.Header().Get("Retry-After") != "7" {
				t.Fatalf("retry-after = %q, want 7", response.Header().Get("Retry-After"))
			}
			if upstream.calls != 1 {
				t.Fatalf("upstream calls = %d, want 1", upstream.calls)
			}
			if billing.releases != 1 {
				t.Fatalf("billing releases = %d, want 1", billing.releases)
			}
		})
	}
}

func TestLegacyStreamUsesNonStreamCompletionAndWritesCompatibleEvents(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	upstream := &nonStreamSuccessService{}
	billing := &recordingBillingService{cost: 0.002}
	handler := &ChatHandler{deepseekService: upstream, billingService: billing}
	request := httptest.NewRequest(
		http.MethodPost,
		"/chat",
		bytes.NewBufferString(`{"request_kind":"utility","model":"grok4.5","messages":[{"role":"user","content":"hello"}],"max_tokens":32}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(response)
	context.Request = request
	context.Set("user_id", uint(1))

	handler.ChatCompletionsStream(context)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", response.Code, response.Body.String())
	}
	if contentType := response.Header().Get("Content-Type"); !strings.Contains(contentType, "text/event-stream") {
		t.Fatalf("content-type = %q, want text/event-stream", contentType)
	}
	body := response.Body.String()
	for _, fragment := range []string{"call-1", "data: [DONE]", `"cost":0.002`} {
		if !strings.Contains(body, fragment) {
			t.Fatalf("body missing %q: %s", fragment, body)
		}
	}
	if upstream.calls != 1 || billing.settles != 1 || billing.releases != 0 {
		t.Fatalf("calls=%d settles=%d releases=%d", upstream.calls, billing.settles, billing.releases)
	}
}
