package services

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/models"
)

// setupRoutingTestDB 初始化临时 DB 与最小 config（含加密密钥），测试结束恢复。
func setupRoutingTestDB(t *testing.T) {
	t.Helper()
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	oldCfg := config.AppConfig
	config.AppConfig = &config.Config{}
	config.AppConfig.DeepSeek.BaseURL = "https://api.deepseek.com/v1"
	config.AppConfig.Encryption.Key = "routing-test-encryption-key"
	oldRc := runtimeCfg
	ConfigureRuntime(RuntimeConfig{
		EncryptionKey:          func() string { return config.AppConfig.Encryption.Key },
		EncryptionFallbackKeys: func() []string { return config.EncryptionFallbackKeys },
		DeepSeekBaseURL:        func() string { return config.AppConfig.DeepSeek.BaseURL },
	})
	t.Cleanup(func() {
		config.AppConfig = oldCfg
		ConfigureRuntime(oldRc)
	})
}

func insertRoutingAPIKey(t *testing.T, provider, baseURL, format, plaintext string) {
	t.Helper()
	key := config.AppConfig.Encryption.Key
	if len(key) < 32 {
		key = key + strings.Repeat("0", 32-len(key))
	}
	encrypted, err := Encrypt(plaintext, []byte(key[:32]))
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	rec := models.APIKey{
		Provider:        provider,
		Name:            provider + "-key",
		APIKeyEncrypted: encrypted,
		BaseURL:         baseURL,
		ApiFormat:       format,
		IsActive:        true,
	}
	if err := database.Get().Register("APIKey").Insert(&rec); err != nil {
		t.Fatalf("insert api key: %v", err)
	}
}

func TestResolveUpstreamUnknownModelFallsBackToDeepseekConfig(t *testing.T) {
	setupRoutingTestDB(t)
	insertRoutingAPIKey(t, "deepseek", "", "", "sk-deepseek-plain")

	target, err := (&DeepSeekService{}).resolveUpstream("no-such-model")
	if err != nil {
		t.Fatalf("resolveUpstream: %v", err)
	}
	if target.Provider != "deepseek" {
		t.Fatalf("provider = %q, want deepseek", target.Provider)
	}
	if target.BaseURL != "https://api.deepseek.com/v1" {
		t.Fatalf("base url = %q, want config fallback", target.BaseURL)
	}
	if target.Format != ApiFormatOpenAI {
		t.Fatalf("format = %q, want openai", target.Format)
	}
	if target.APIKey != "sk-deepseek-plain" {
		t.Fatalf("api key not decrypted, got %q", target.APIKey)
	}
}

func TestResolveUpstreamRoutesGeminiModelToKeyBaseURL(t *testing.T) {
	setupRoutingTestDB(t)
	insertRoutingAPIKey(t, "deepseek", "", "", "sk-deepseek-plain")
	insertRoutingAPIKey(t, "gemini", "https://proxy.example.com/gemini/", "gemini", "sk-gemini-plain")
	price := models.ModelPrice{ModelID: "gemini-2.5-flash", ModelName: "Gemini 2.5 Flash", Provider: "gemini", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	target, err := (&DeepSeekService{}).resolveUpstream("gemini-2.5-flash")
	if err != nil {
		t.Fatalf("resolveUpstream: %v", err)
	}
	if target.Provider != "gemini" {
		t.Fatalf("provider = %q, want gemini", target.Provider)
	}
	if target.BaseURL != "https://proxy.example.com/gemini" {
		t.Fatalf("base url = %q, want key base_url (trailing slash trimmed)", target.BaseURL)
	}
	if target.Format != ApiFormatGemini {
		t.Fatalf("format = %q, want gemini", target.Format)
	}
	if target.APIKey != "sk-gemini-plain" {
		t.Fatalf("api key not decrypted, got %q", target.APIKey)
	}
}

func TestResolveUpstreamGeminiDefaultBaseURL(t *testing.T) {
	setupRoutingTestDB(t)
	insertRoutingAPIKey(t, "gemini", "", "gemini", "sk-gemini-plain")
	price := models.ModelPrice{ModelID: "gemini-2.5-flash", Provider: "gemini", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	target, err := (&DeepSeekService{}).resolveUpstream("gemini-2.5-flash")
	if err != nil {
		t.Fatalf("resolveUpstream: %v", err)
	}
	if target.BaseURL != DefaultGeminiBaseURL {
		t.Fatalf("base url = %q, want %q", target.BaseURL, DefaultGeminiBaseURL)
	}
}

func TestResolveUpstreamMissingProviderKey(t *testing.T) {
	setupRoutingTestDB(t)
	price := models.ModelPrice{ModelID: "gemini-2.5-flash", Provider: "gemini", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	_, err := (&DeepSeekService{}).resolveUpstream("gemini-2.5-flash")
	var cfgErr *UpstreamConfigError
	if !errors.As(err, &cfgErr) {
		t.Fatalf("error = %v, want UpstreamConfigError", err)
	}
}

func TestAdaptRequestForFormatGeminiStripsDeepSeekParams(t *testing.T) {
	req := &ChatCompletionRequest{
		Model:           "gemini-2.5-flash",
		ToolChoice:      "required",
		ReasoningEffort: "high",
		ExtraBody:       &ThinkingBody{Thinking: ThinkingConfig{Type: "enabled"}},
	}
	adapted := adaptRequestForFormat(req, ApiFormatGemini)
	if adapted.ExtraBody != nil {
		t.Fatal("ExtraBody should be stripped for gemini")
	}
	if adapted.ReasoningEffort != "" {
		t.Fatal("ReasoningEffort should be stripped for gemini")
	}
	if adapted.ToolChoice != "auto" {
		t.Fatalf("tool_choice = %v, want auto", adapted.ToolChoice)
	}
	// 原请求不应被修改
	if req.ExtraBody == nil || req.ReasoningEffort == "" || req.ToolChoice != "required" {
		t.Fatal("original request must not be mutated")
	}
	// openai 格式透传（同一指针）
	if got := adaptRequestForFormat(req, ApiFormatOpenAI); got != req {
		t.Fatal("openai format should pass the request through unchanged")
	}
}

func TestChatCompletionRoutesGeminiAndAdaptsPayload(t *testing.T) {
	setupRoutingTestDB(t)

	var gotAuth string
	var gotBody map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &gotBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"x","object":"chat.completion","created":1,"model":"gemini-2.5-flash","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, "gemini", server.URL, "gemini", "sk-gemini-plain")
	price := models.ModelPrice{ModelID: "gemini-2.5-flash", Provider: "gemini", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	req := &ChatCompletionRequest{
		Model:           "gemini-2.5-flash",
		Messages:        []ChatMessage{{Role: "user", Content: "hi"}},
		ToolChoice:      "required",
		ReasoningEffort: "high",
		ExtraBody:       &ThinkingBody{Thinking: ThinkingConfig{Type: "enabled"}},
	}
	if _, err := (&DeepSeekService{}).ChatCompletion(context.Background(), req); err != nil {
		t.Fatalf("ChatCompletion: %v", err)
	}
	if gotAuth != "Bearer sk-gemini-plain" {
		t.Fatalf("authorization = %q, want bearer gemini key", gotAuth)
	}
	if _, ok := gotBody["extra_body"]; ok {
		t.Fatal("extra_body should be stripped for gemini upstream")
	}
	if _, ok := gotBody["reasoning_effort"]; ok {
		t.Fatal("reasoning_effort should be stripped for gemini upstream")
	}
	if gotBody["tool_choice"] != "auto" {
		t.Fatalf("tool_choice = %v, want auto", gotBody["tool_choice"])
	}
}

func TestChatCompletionReturnsTypedUpstreamHTTPError(t *testing.T) {
	setupRoutingTestDB(t)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Retry-After", "7")
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":{"message":"Upstream rate limit exceeded","type":"rate_limit_exceeded","code":"upstream_error"}}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, "grok", server.URL, ApiFormatOpenAI, "sk-grok-plain")
	price := models.ModelPrice{ModelID: "grok4.5", Provider: "grok", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	_, err := (&DeepSeekService{}).ChatCompletion(context.Background(), &ChatCompletionRequest{
		Model:    "grok4.5",
		Messages: []ChatMessage{{Role: "user", Content: "hi"}},
	})
	if err == nil {
		t.Fatal("ChatCompletion error = nil, want upstream 429")
	}

	var upstreamErr *UpstreamHTTPError
	if !errors.As(err, &upstreamErr) {
		t.Fatalf("error = %T %v, want UpstreamHTTPError", err, err)
	}
	if upstreamErr.Provider != "grok" {
		t.Fatalf("provider = %q, want grok", upstreamErr.Provider)
	}
	if upstreamErr.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", upstreamErr.StatusCode, http.StatusTooManyRequests)
	}
	if upstreamErr.RetryAfter != "7" {
		t.Fatalf("retry-after = %q, want 7", upstreamErr.RetryAfter)
	}
	if !strings.Contains(upstreamErr.Body, "rate_limit_exceeded") {
		t.Fatalf("body = %q, want rate_limit_exceeded", upstreamErr.Body)
	}
}
