package services

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// streamTestUpstream 返回一个假上游：校验请求体含 stream=true，并按 SSE 输出内容增量。
// 返回聚合结果供断言。
func streamTestUpstream(t *testing.T, sseBody, usage string, statusCode int) *httptest.Server {
	t.Helper()
	var gotStream bool
	var gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		buf := make([]byte, r.ContentLength)
		_, _ = r.Body.Read(buf)
		gotBody = string(buf)
		var req ChatCompletionRequest
		_ = json.Unmarshal(buf, &req)
		gotStream = req.Stream
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(statusCode)
		if statusCode == http.StatusOK {
			_, _ = w.Write([]byte(sseBody))
		}
	}))
	t.Cleanup(srv.Close)
	t.Cleanup(func() {
		if !gotStream {
			t.Error("upstream request did not set stream=true")
		}
		if !strings.Contains(gotBody, `"stream":true`) {
			t.Errorf("request body missing stream:true: %s", gotBody)
		}
	})
	return srv
}

func setupStreamServiceTest(t *testing.T, srv *httptest.Server) {
	t.Helper()
	setupRoutingTestDB(t)
	insertRoutingAPIKey(t, "deepseek", srv.URL, "openai", "sk-stream-test")
	setUpstreamClientsForTest(upstreamClients{
		completion: &http.Client{},
		stream:     &http.Client{},
		metadata:   &http.Client{},
	})
}

func TestChatCompletionViaStreamAggregatesContentAndUsage(t *testing.T) {
	sse := "" +
		`data: {"id":"s-1","object":"chat.completion.chunk","created":1,"model":"grok4.5","choices":[{"index":0,"delta":{"role":"assistant","content":"你好"},"finish_reason":null}]}` + "\n\n" +
		`data: {"choices":[{"index":0,"delta":{"content":"，世界"},"finish_reason":null}]}` + "\n\n" +
		`data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}` + "\n\n" +
		`data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15,"prompt_cache_hit_tokens":2,"prompt_cache_miss_tokens":8}}` + "\n\n" +
		`data: [DONE]` + "\n\n"

	srv := streamTestUpstream(t, sse, "", http.StatusOK)
	setupStreamServiceTest(t, srv)

	result, err := (&DeepSeekService{}).ChatCompletionViaStream(context.Background(), &ChatCompletionRequest{
		Model:    "grok4.5",
		Messages: []ChatMessage{{Role: "user", Content: "hi"}},
	})
	if err != nil {
		t.Fatalf("ChatCompletionViaStream: %v", err)
	}
	if result.ID != "s-1" {
		t.Errorf("id = %q, want s-1", result.ID)
	}
	if len(result.Choices) != 1 {
		t.Fatalf("choices len = %d, want 1", len(result.Choices))
	}
	msg := result.Choices[0].Message
	if msg.Role != "assistant" {
		t.Errorf("role = %q, want assistant", msg.Role)
	}
	if msg.Content != "你好，世界" {
		t.Errorf("content = %q, want 你好，世界", msg.Content)
	}
	if result.Choices[0].FinishReason != "stop" {
		t.Errorf("finish_reason = %q, want stop", result.Choices[0].FinishReason)
	}
	if result.Usage.PromptTokens != 10 || result.Usage.CompletionTokens != 5 || result.Usage.TotalTokens != 15 {
		t.Errorf("usage = %+v, want prompt=10 completion=5 total=15", result.Usage)
	}
	if result.Usage.PromptCacheHitTokens != 2 || result.Usage.PromptCacheMissTokens != 8 {
		t.Errorf("cache usage = %+v, want hit=2 miss=8", result.Usage)
	}
}

func TestChatCompletionViaStreamAggregatesToolCallArguments(t *testing.T) {
	sse := "" +
		`data: {"id":"s-2","object":"chat.completion.chunk","created":2,"model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"chat","arguments":""}}]},"finish_reason":null}]}` + "\n\n" +
		`data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"message\":\"hel"}}]},"finish_reason":null}]}` + "\n\n" +
		`data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"lo\"}"}}]},"finish_reason":"tool_calls"}]}` + "\n\n" +
		`data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}` + "\n\n" +
		`data: [DONE]` + "\n\n"

	srv := streamTestUpstream(t, sse, "", http.StatusOK)
	setupStreamServiceTest(t, srv)

	result, err := (&DeepSeekService{}).ChatCompletionViaStream(context.Background(), &ChatCompletionRequest{
		Model:    "m",
		Messages: []ChatMessage{{Role: "user", Content: "hi"}},
	})
	if err != nil {
		t.Fatalf("ChatCompletionViaStream: %v", err)
	}
	if len(result.Choices) != 1 {
		t.Fatalf("choices len = %d, want 1", len(result.Choices))
	}
	msg := result.Choices[0].Message
	if len(msg.ToolCalls) != 1 {
		t.Fatalf("tool_calls len = %d, want 1", len(msg.ToolCalls))
	}
	tc := msg.ToolCalls[0]
	if tc.ID != "call-1" || tc.Type != "function" || tc.Function.Name != "chat" {
		t.Errorf("tool_call identity = %+v, want id=call-1 type=function name=chat", tc)
	}
	if tc.Function.Arguments != `{"message":"hello"}` {
		t.Errorf("arguments = %q, want {\"message\":\"hello\"}", tc.Function.Arguments)
	}
	if result.Choices[0].FinishReason != "tool_calls" {
		t.Errorf("finish_reason = %q, want tool_calls", result.Choices[0].FinishReason)
	}
}

func TestChatCompletionViaStreamNon200ReturnsUpstreamError(t *testing.T) {
	srv := streamTestUpstream(t, "{}", "", http.StatusTooManyRequests)
	setupStreamServiceTest(t, srv)

	// 注入立即返回的 retryWait，避免 429 默认 30s 退避拖慢测试
	svc := &DeepSeekService{retryWait: func(ctx context.Context, delay time.Duration) error { return nil }}

	_, err := svc.ChatCompletionViaStream(context.Background(), &ChatCompletionRequest{
		Model:    "grok4.5",
		Messages: []ChatMessage{{Role: "user", Content: "hi"}},
	})
	if err == nil {
		t.Fatal("expected error for 429 upstream")
	}
	var httpErr *UpstreamHTTPError
	if !errors.As(err, &httpErr) {
		t.Fatalf("error = %v, want UpstreamHTTPError", err)
	}
	if httpErr.StatusCode != http.StatusTooManyRequests {
		t.Errorf("status = %d, want 429", httpErr.StatusCode)
	}
}

func TestChatCompletionViaStreamEmptyBodyReturnsError(t *testing.T) {
	srv := streamTestUpstream(t, "", "", http.StatusOK)
	setupStreamServiceTest(t, srv)

	_, err := (&DeepSeekService{}).ChatCompletionViaStream(context.Background(), &ChatCompletionRequest{
		Model:    "grok4.5",
		Messages: []ChatMessage{{Role: "user", Content: "hi"}},
	})
	if err == nil {
		t.Fatal("expected error for empty stream body")
	}
}