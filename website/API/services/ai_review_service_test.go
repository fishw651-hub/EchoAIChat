package services

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

func TestParseAiReviewVerdictNormal(t *testing.T) {
	t.Parallel()
	v, err := ParseAiReviewVerdict(`{"pass": true, "risk_level": "none", "reason": "内容正常"}`)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !v.Pass || v.RiskLevel != "none" || v.Reason != "内容正常" {
		t.Fatalf("verdict = %+v", v)
	}
}

func TestParseAiReviewVerdictMarkdownFence(t *testing.T) {
	t.Parallel()
	raw := "好的，审核结果如下：\n```json\n{\"pass\": false, \"risk_level\": \"high\", \"reason\": \"含暴力内容\"}\n```\n以上。"
	v, err := ParseAiReviewVerdict(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if v.Pass || v.RiskLevel != "high" || v.Reason != "含暴力内容" {
		t.Fatalf("verdict = %+v", v)
	}
}

func TestParseAiReviewVerdictDirtyTextAndNestedBraces(t *testing.T) {
	t.Parallel()
	// reason 内含花括号/引号转义，提取必须括号配平且字符串感知
	raw := `前缀垃圾 {"pass": false, "risk_level": "MEDIUM", "reason": "含{广告}链接\"x\""} 后缀 {"other": 1}`
	v, err := ParseAiReviewVerdict(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if v.Pass || v.RiskLevel != "medium" || !strings.Contains(v.Reason, "{广告}") {
		t.Fatalf("verdict = %+v", v)
	}
}

func TestParseAiReviewVerdictNoJSON(t *testing.T) {
	t.Parallel()
	if _, err := ParseAiReviewVerdict("完全没有任何 JSON"); err == nil {
		t.Fatal("expected error for content without JSON object")
	}
	if _, err := ParseAiReviewVerdict("{\"pass\": true"); err == nil {
		t.Fatal("expected error for unterminated JSON object")
	}
}

func TestParseAiReviewVerdictInvalidRiskLevelFallback(t *testing.T) {
	t.Parallel()
	pass, err := ParseAiReviewVerdict(`{"pass": true, "risk_level": "bogus", "reason": "r"}`)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if pass.RiskLevel != "none" {
		t.Fatalf("pass=true 非法等级应回落 none, got %q", pass.RiskLevel)
	}
	fail, err := ParseAiReviewVerdict(`{"pass": false, "reason": "r"}`)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if fail.RiskLevel != "high" {
		t.Fatalf("pass=false 缺省等级应回落 high, got %q", fail.RiskLevel)
	}
}

func TestParseAiReviewVerdictEmptyReasonFallback(t *testing.T) {
	t.Parallel()
	v, err := ParseAiReviewVerdict(`{"pass": true, "risk_level": "low"}`)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if v.Reason == "" {
		t.Fatal("空 reason 应有兜底文案")
	}
}

func TestGetAiReviewConfigDefaults(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	enabled, auto, prompt := GetAiReviewConfig()
	if enabled || auto {
		t.Fatalf("默认应关闭, got enabled=%v auto=%v", enabled, auto)
	}
	if prompt != DefaultAiReviewPrompt {
		t.Fatal("prompt 未配置时应回落默认提示词")
	}
}

func TestReviewNetworkContentDisabled(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	svc := &AiReviewService{}
	if _, err := svc.ReviewNetworkContent(context.Background(), "n", "d", "p", "w"); err == nil || !strings.Contains(err.Error(), "未启用") {
		t.Fatalf("disabled 时应返回明确错误, got %v", err)
	}
}

func TestReviewNetworkContentWithInjectedChat(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := database.Get().Register("SystemConfig")
	tbl.Insert(&models.SystemConfig{Key: AiReviewEnabledConfigKey, Value: "true"})

	var resp ChatCompletionResponse
	if err := json.Unmarshal([]byte(`{"choices":[{"message":{"content":"{\"pass\":false,\"risk_level\":\"medium\",\"reason\":\"疑似广告\"}"}}]}`), &resp); err != nil {
		t.Fatal(err)
	}
	var gotReq *ChatCompletionRequest
	svc := &AiReviewService{
		Chat: func(ctx context.Context, req *ChatCompletionRequest) (*ChatCompletionResponse, error) {
			gotReq = req
			return &resp, nil
		},
	}

	v, err := svc.ReviewNetworkContent(context.Background(), "名称", "描述", "人设", "世界观")
	if err != nil {
		t.Fatalf("review: %v", err)
	}
	if v.Pass || v.RiskLevel != "medium" || v.Reason != "疑似广告" {
		t.Fatalf("verdict = %+v", v)
	}
	if gotReq == nil {
		t.Fatal("未调用注入的 Chat")
	}
	if len(gotReq.Messages) != 2 || gotReq.Messages[0].Role != "system" || gotReq.Messages[1].Role != "user" {
		t.Fatalf("messages = %+v", gotReq.Messages)
	}
	if gotReq.Messages[0].Content != DefaultAiReviewPrompt {
		t.Fatal("system 应使用默认审核提示词")
	}
	userContent, _ := gotReq.Messages[1].Content.(string)
	for _, want := range []string{"名称", "描述", "人设", "世界观"} {
		if !strings.Contains(userContent, want) {
			t.Fatalf("user 内容缺少 %q: %s", want, userContent)
		}
	}
	// 非思考模式：不得带思考参数
	if gotReq.ReasoningEffort != "" || gotReq.ExtraBody != nil {
		t.Fatal("审核请求不应携带思考模式参数")
	}
}

func TestPickAiReviewModelPrefersFlash(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := database.Get().Register("ModelPrice")
	tbl.Insert(&models.ModelPrice{ModelID: "deepseek-v4-pro", ModelName: "pro", Status: 1})
	tbl.Insert(&models.ModelPrice{ModelID: "deepseek-v4-flash", ModelName: "flash", Status: 1})
	tbl.Insert(&models.ModelPrice{ModelID: "disabled-model", ModelName: "off", Status: 0})

	if got := pickAiReviewModel(); got != "deepseek-v4-flash" {
		t.Fatalf("应优先 deepseek-v4-flash, got %q", got)
	}
}

func TestResolveAiReviewModelConfigOverridesFallback(t *testing.T) {
	setupRoutingTestDB(t)

	tbl := database.Get().Register("ModelPrice")
	tbl.Insert(&models.ModelPrice{ModelID: "deepseek-v4-flash", ModelName: "flash", Status: 1})

	// 未配置 → 回退链不变（优先 deepseek-v4-flash）
	if got := resolveAiReviewModel(); got != "deepseek-v4-flash" {
		t.Fatalf("未配置时应走回退链, got %q", got)
	}

	// 配置指定模型 → 直接用配置值（含空白 trim）
	cfg := database.Get().Register("SystemConfig")
	cfg.Insert(&models.SystemConfig{Key: AiReviewModelConfigKey, Value: " gemini-2.5-flash "})
	if got := resolveAiReviewModel(); got != "gemini-2.5-flash" {
		t.Fatalf("配置模型应优先, got %q", got)
	}
}

// 配置 gemini 模型后，审核请求（Chat 未注入，走真实 defaultAiReviewChat）
// 应路由到 gemini provider 站点，且 gemini 格式剥离 DeepSeek 特有参数
func TestReviewNetworkContentRoutesConfiguredModel(t *testing.T) {
	setupRoutingTestDB(t)

	var gotAuth string
	var gotBody map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &gotBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"{\"pass\":true,\"risk_level\":\"none\",\"reason\":\"内容正常\"}"}}]}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, "gemini", server.URL, "gemini", "sk-gemini-plain")
	database.Get().Register("ModelPrice").Insert(&models.ModelPrice{ModelID: "gemini-2.5-flash", Provider: "gemini", Status: 1})
	cfg := database.Get().Register("SystemConfig")
	cfg.Insert(&models.SystemConfig{Key: AiReviewEnabledConfigKey, Value: "true"})
	cfg.Insert(&models.SystemConfig{Key: AiReviewModelConfigKey, Value: "gemini-2.5-flash"})

	svc := &AiReviewService{} // Chat=nil → 真实路由调用
	v, err := svc.ReviewNetworkContent(context.Background(), "名称", "描述", "人设", "世界观")
	if err != nil {
		t.Fatalf("review: %v", err)
	}
	if !v.Pass || v.RiskLevel != "none" || v.Reason != "内容正常" {
		t.Fatalf("verdict = %+v", v)
	}
	if gotAuth != "Bearer sk-gemini-plain" {
		t.Fatalf("应携带 gemini provider 的 key, got %q", gotAuth)
	}
	if gotBody["model"] != "gemini-2.5-flash" {
		t.Fatalf("上游收到 model = %v, want gemini-2.5-flash", gotBody["model"])
	}
	if _, ok := gotBody["extra_body"]; ok {
		t.Fatal("gemini 格式不应携带 extra_body")
	}
	if _, ok := gotBody["reasoning_effort"]; ok {
		t.Fatal("gemini 格式不应携带 reasoning_effort")
	}
}

// defaultAiReviewChat 对 gemini 上游剥离 thinking 参数，tool_choice required 降级 auto
func TestDefaultAiReviewChatStripsDeepSeekParamsForGemini(t *testing.T) {
	setupRoutingTestDB(t)

	var gotBody map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &gotBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"ok"}}]}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, "gemini", server.URL, "gemini", "sk-gemini-plain")
	database.Get().Register("ModelPrice").Insert(&models.ModelPrice{ModelID: "gemini-2.5-flash", Provider: "gemini", Status: 1})

	req := &ChatCompletionRequest{
		Model:           "gemini-2.5-flash",
		Messages:        []ChatMessage{{Role: "user", Content: "hi"}},
		ToolChoice:      "required",
		ReasoningEffort: "high",
		ExtraBody:       &ThinkingBody{Thinking: ThinkingConfig{Type: "enabled"}},
	}
	if _, err := defaultAiReviewChat(context.Background(), req); err != nil {
		t.Fatalf("defaultAiReviewChat: %v", err)
	}
	if _, ok := gotBody["extra_body"]; ok {
		t.Fatal("extra_body 应被剥离")
	}
	if _, ok := gotBody["reasoning_effort"]; ok {
		t.Fatal("reasoning_effort 应被剥离")
	}
	if gotBody["tool_choice"] != "auto" {
		t.Fatalf("tool_choice = %v, want auto", gotBody["tool_choice"])
	}
}

// 空配置时回退链保持 deepseek 路由：请求打到 deepseek provider key 对应站点
func TestReviewNetworkContentEmptyModelFallsBackToDeepseek(t *testing.T) {
	setupRoutingTestDB(t)

	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if got := r.Header.Get("Authorization"); got != "Bearer sk-deepseek-plain" {
			t.Errorf("应携带 deepseek key, got %q", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"{\"pass\":true}"}}]}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, "deepseek", server.URL, "", "sk-deepseek-plain")
	database.Get().Register("ModelPrice").Insert(&models.ModelPrice{ModelID: "deepseek-v4-flash", Provider: "deepseek", Status: 1})
	cfg := database.Get().Register("SystemConfig")
	cfg.Insert(&models.SystemConfig{Key: AiReviewEnabledConfigKey, Value: "true"})
	// 不写 ai_review_model → 回退链

	svc := &AiReviewService{}
	if _, err := svc.ReviewNetworkContent(context.Background(), "n", "d", "p", "w"); err != nil {
		t.Fatalf("review: %v", err)
	}
	if !called {
		t.Fatal("回退链应路由到 deepseek provider 站点")
	}
}
