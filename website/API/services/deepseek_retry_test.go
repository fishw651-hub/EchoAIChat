package services

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

const retrySuccessResponse = `{"id":"completion-1","object":"chat.completion","created":1,"model":"test-model","choices":[],"usage":{}}`

func retryTarget(serverURL string) *upstreamTarget {
	return &upstreamTarget{Provider: "test-provider", BaseURL: serverURL, APIKey: "test-key", Format: ApiFormatOpenAI}
}

func retryRequest() *ChatCompletionRequest {
	return &ChatCompletionRequest{Model: "test-model", Stream: true, Messages: []ChatMessage{{Role: "user", Content: "hello"}}}
}

func newRetryService(client *http.Client, waits *[]time.Duration) *DeepSeekService {
	return &DeepSeekService{
		completionClient: client,
		retryWait: func(_ context.Context, delay time.Duration) error {
			*waits = append(*waits, delay)
			return nil
		},
	}
}

func assertNonStreamRequest(t *testing.T, body []byte) {
	t.Helper()
	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatalf("decode request: %v", err)
	}
	if stream, ok := payload["stream"]; ok && stream != false {
		t.Fatalf("stream = %#v, want absent or false", stream)
	}
}

func TestChatCompletionRetries429WithRetryAfter(t *testing.T) {
	var calls int
	var bodies [][]byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read request: %v", err)
		}
		bodies = append(bodies, body)
		assertNonStreamRequest(t, body)
		if calls == 1 {
			w.Header().Set("Retry-After", "7")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"retry"}`))
			return
		}
		_, _ = w.Write([]byte(retrySuccessResponse))
	}))
	defer server.Close()

	var waits []time.Duration
	result, err := newRetryService(server.Client(), &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget(server.URL))
	if err != nil {
		t.Fatalf("chat completion: %v", err)
	}
	if result.ID != "completion-1" {
		t.Fatalf("response ID = %q", result.ID)
	}
	if calls != 2 {
		t.Fatalf("calls = %d, want 2", calls)
	}
	if len(waits) != 1 || waits[0] != 7*time.Second {
		t.Fatalf("waits = %v, want [7s]", waits)
	}
	if len(bodies) != 2 || !bytes.Equal(bodies[0], bodies[1]) {
		t.Fatalf("request bodies must be byte-equivalent: %q / %q", bodies[0], bodies[1])
	}
}

func TestChatCompletionRetries503(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		if calls == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		_, _ = w.Write([]byte(retrySuccessResponse))
	}))
	defer server.Close()

	var waits []time.Duration
	_, err := newRetryService(server.Client(), &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget(server.URL))
	if err != nil {
		t.Fatalf("chat completion: %v", err)
	}
	if calls != 2 || len(waits) != 1 || waits[0] != 5*time.Second {
		t.Fatalf("calls=%d waits=%v, want 2 [5s]", calls, waits)
	}
}

func TestChatCompletionRetriesOnlyOnceAndPreservesFinalHTTPError(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		if calls == 1 {
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"first"}`))
			return
		}
		w.Header().Set("Retry-After", "9")
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":"second"}`))
	}))
	defer server.Close()

	var waits []time.Duration
	_, err := newRetryService(server.Client(), &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget(server.URL))
	var upstreamErr *UpstreamHTTPError
	if !errors.As(err, &upstreamErr) {
		t.Fatalf("error = %v, want UpstreamHTTPError", err)
	}
	if calls != 2 || len(waits) != 1 {
		t.Fatalf("calls=%d waits=%v, want 2 and one wait", calls, waits)
	}
	if upstreamErr.Body != `{"error":"second"}` || upstreamErr.RetryAfter != "9" {
		t.Fatalf("final error = %#v", upstreamErr)
	}
}

func TestChatCompletionDoesNotRetry400(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	var waits []time.Duration
	_, err := newRetryService(server.Client(), &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget(server.URL))
	if err == nil {
		t.Fatal("expected error")
	}
	if calls != 1 || len(waits) != 0 {
		t.Fatalf("calls=%d waits=%v, want 1 and no waits", calls, waits)
	}
}

type retryRoundTripper struct {
	mu    sync.Mutex
	calls int
}

func (r *retryRoundTripper) RoundTrip(*http.Request) (*http.Response, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls++
	if r.calls == 1 {
		return nil, io.EOF
	}
	return &http.Response{StatusCode: http.StatusOK, Header: make(http.Header), Body: io.NopCloser(bytes.NewBufferString(retrySuccessResponse))}, nil
}

func TestChatCompletionRetriesTransportError(t *testing.T) {
	transport := &retryRoundTripper{}
	client := &http.Client{Transport: transport}
	var waits []time.Duration

	result, err := newRetryService(client, &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget("http://upstream.test"))
	if err != nil {
		t.Fatalf("chat completion: %v", err)
	}
	if result.ID != "completion-1" || transport.calls != 2 || len(waits) != 1 || waits[0] != 5*time.Second {
		t.Fatalf("result=%#v calls=%d waits=%v", result, transport.calls, waits)
	}
}

func TestChatCompletionStopsRetryWhenWaitCancelsContext(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	service := &DeepSeekService{
		completionClient: server.Client(),
		retryWait: func(ctx context.Context, delay time.Duration) error {
			cancel()
			return waitForUpstreamRetry(ctx, delay)
		},
	}
	_, err := service.chatCompletionWithTarget(ctx, retryRequest(), retryTarget(server.URL))
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v, want context.Canceled", err)
	}
	if calls != 1 {
		t.Fatalf("calls = %d, want 1", calls)
	}
}

type retryStatusRoundTripper struct {
	calls int
}

func (r *retryStatusRoundTripper) RoundTrip(*http.Request) (*http.Response, error) {
	r.calls++
	if r.calls == 1 {
		return &http.Response{
			StatusCode: http.StatusServiceUnavailable,
			Header:     make(http.Header),
			Body:       io.NopCloser(bytes.NewBufferString(`{"error":"retry"}`)),
		}, nil
	}
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     make(http.Header),
		Body:       io.NopCloser(bytes.NewBufferString(retrySuccessResponse)),
	}, nil
}

func TestChatCompletionStopsRetryWhenWaitCancelsContextAndReturnsNil(t *testing.T) {
	transport := &retryStatusRoundTripper{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	service := &DeepSeekService{
		completionClient: &http.Client{Transport: transport},
		retryWait: func(context.Context, time.Duration) error {
			cancel()
			return nil
		},
	}

	_, err := service.chatCompletionWithTarget(ctx, retryRequest(), retryTarget("http://upstream.test"))
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v, want context.Canceled", err)
	}
	if transport.calls != 1 {
		t.Fatalf("round trips = %d, want 1", transport.calls)
	}
}

func TestChatCompletionDoesNotRetryDecodeFailure(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		_, _ = w.Write([]byte(`{`))
	}))
	defer server.Close()

	var waits []time.Duration
	_, err := newRetryService(server.Client(), &waits).chatCompletionWithTarget(context.Background(), retryRequest(), retryTarget(server.URL))
	if err == nil {
		t.Fatal("expected decode error")
	}
	if calls != 1 || len(waits) != 0 {
		t.Fatalf("calls=%d waits=%v, want 1 and no waits", calls, waits)
	}
}
