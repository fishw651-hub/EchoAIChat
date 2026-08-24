package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/hub"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func setupAiReviewTestDB(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	// decryptField 经 services.DecryptWithConfiguredKeys 解密，密钥由
	// services.ConfigureRuntime 注入；getter 形态保持对 config.AppConfig 的热读
	origCfg := config.AppConfig
	config.AppConfig = &config.Config{}
	services.ConfigureRuntime(services.RuntimeConfig{
		EncryptionKey:          func() string { return config.AppConfig.Encryption.Key },
		EncryptionFallbackKeys: func() []string { return config.EncryptionFallbackKeys },
	})
	t.Cleanup(func() {
		config.AppConfig = origCfg
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}

func doJSON(router *gin.Engine, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)
	return recorder
}

func TestAiReviewUpdatesChangesMarketStatus(t *testing.T) {
	tests := []struct {
		name             string
		verdict          services.AiReviewVerdict
		reviewErr        error
		wantAIStatus     string
		wantMarketStatus string
		wantRejectReason string
		wantStatusUpdate bool
	}{
		{
			name:             "pass publishes",
			verdict:          services.AiReviewVerdict{Pass: true, Reason: "内容正常"},
			wantAIStatus:     "pass",
			wantMarketStatus: "approved",
			wantStatusUpdate: true,
		},
		{
			name:             "reject records reason",
			verdict:          services.AiReviewVerdict{Pass: false, Reason: "含违规内容"},
			wantAIStatus:     "reject",
			wantMarketStatus: "rejected",
			wantRejectReason: "含违规内容",
			wantStatusUpdate: true,
		},
		{
			name:             "error keeps pending",
			reviewErr:        errors.New("timeout"),
			wantAIStatus:     "error",
			wantStatusUpdate: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			updates := aiReviewUpdates(tt.verdict, tt.reviewErr)
			if got := updates["AiReviewStatus"]; got != tt.wantAIStatus {
				t.Fatalf("AiReviewStatus = %v, want %q", got, tt.wantAIStatus)
			}
			gotStatus, hasStatus := updates["Status"]
			if hasStatus != tt.wantStatusUpdate {
				t.Fatalf("Status present = %v, want %v; updates=%+v", hasStatus, tt.wantStatusUpdate, updates)
			}
			if hasStatus && gotStatus != tt.wantMarketStatus {
				t.Fatalf("Status = %v, want %q", gotStatus, tt.wantMarketStatus)
			}
			if got := updates["RejectReason"]; got != nil && got != tt.wantRejectReason {
				t.Fatalf("RejectReason = %v, want %q", got, tt.wantRejectReason)
			}
		})
	}
}

func TestStaleAutoReviewCannotOverwriteNewVersion(t *testing.T) {
	setupAiReviewTestDB(t)

	tbl := database.Get().Register("NetworkAgent")
	agent := models.NetworkAgent{
		UploaderID: 1,
		Name:       "A",
		Status:     "pending",
		Version:    2,
	}
	if err := tbl.Insert(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}

	if err := applyAiReviewAgentResult(
		agent.ID,
		1,
		services.AiReviewVerdict{Pass: true, Reason: "旧结果"},
		nil,
	); err != nil {
		t.Fatalf("apply stale result: %v", err)
	}

	var after models.NetworkAgent
	if !tbl.FindByID(agent.ID, &after) {
		t.Fatal("agent disappeared")
	}
	if after.Status != "pending" || after.AiReviewStatus != "" {
		t.Fatalf("stale result overwrote version 2: status=%q ai=%q", after.Status, after.AiReviewStatus)
	}
}

func TestReviewPersonaIncludesOpeningLine(t *testing.T) {
	setupAiReviewTestDB(t)

	agent := models.NetworkAgent{
		Persona:     encryptField("智能体人设"),
		OpeningLine: encryptField("智能体开场白"),
	}
	if got := agentReviewPersona(agent); !strings.Contains(got, "智能体开场白") {
		t.Fatalf("agent review persona missing opening line: %q", got)
	}

	group := models.NetworkGroup{
		GroupPersona: encryptField("群聊人设"),
		OpeningLine:  encryptField("群聊开场白"),
	}
	if got := groupReviewPersona(group); !strings.Contains(got, "群聊开场白") {
		t.Fatalf("group review persona missing opening line: %q", got)
	}
}

func TestAiReviewConfigHandlerDefaultsAndUpdate(t *testing.T) {
	setupAiReviewTestDB(t)

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.GET("/cfg", handler.GetConfig)
	router.PUT("/cfg", handler.UpdateConfig)

	// GET 默认：关闭 + 默认提示词
	recorder := doJSON(router, http.MethodGet, "/cfg", "")
	var getResp struct {
		Code int `json:"code"`
		Data struct {
			Enabled bool   `json:"enabled"`
			Auto    bool   `json:"auto"`
			Prompt  string `json:"prompt"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &getResp); err != nil {
		t.Fatal(err)
	}
	if getResp.Code != utils.CodeSuccess || getResp.Data.Enabled || getResp.Data.Auto {
		t.Fatalf("默认配置错误: %+v", getResp)
	}
	if getResp.Data.Prompt != services.DefaultAiReviewPrompt {
		t.Fatal("默认应返回内置审核提示词")
	}

	// PUT enabled 但 prompt 为空 → 校验失败
	recorder = doJSON(router, http.MethodPut, "/cfg", `{"enabled":true,"auto":false,"prompt":"  "}`)
	var badResp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &badResp); err != nil {
		t.Fatal(err)
	}
	if badResp.Code != utils.CodeBadRequest {
		t.Fatalf("enabled 且 prompt 空应返回 40000, got %d (%s)", badResp.Code, recorder.Body.String())
	}

	// PUT 合法配置 → 成功并持久化
	recorder = doJSON(router, http.MethodPut, "/cfg", `{"enabled":true,"auto":true,"prompt":"自定义提示词"}`)
	var okResp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &okResp); err != nil {
		t.Fatal(err)
	}
	if okResp.Code != utils.CodeSuccess {
		t.Fatalf("PUT 失败: %s", recorder.Body.String())
	}
	enabled, auto, prompt := services.GetAiReviewConfig()
	if !enabled || !auto || prompt != "自定义提示词" {
		t.Fatalf("配置未持久化: enabled=%v auto=%v prompt=%q", enabled, auto, prompt)
	}
}

func TestAiReviewAgentDisabled(t *testing.T) {
	setupAiReviewTestDB(t)

	tbl := database.Get().Register("NetworkAgent")
	agent := models.NetworkAgent{UploaderID: 1, Name: "测试", Status: "pending"}
	if err := tbl.Insert(&agent); err != nil {
		t.Fatal(err)
	}

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.POST("/agents/:id/ai-review", handler.ReviewAgent)

	recorder := doJSON(router, http.MethodPost, "/agents/1/ai-review", "")
	var resp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("未启用时应返回 40000, got %d (%s)", resp.Code, recorder.Body.String())
	}

	// 未启用时不应写回记录
	var after models.NetworkAgent
	tbl.FindByID(agent.ID, &after)
	if after.AiReviewStatus != "" {
		t.Fatalf("未启用时不应写回 AI 审核状态, got %q", after.AiReviewStatus)
	}
}

func TestAiReviewAgentManualReviewWritesBack(t *testing.T) {
	setupAiReviewTestDB(t)

	cfgTbl := database.Get().Register("SystemConfig")
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewEnabledConfigKey, Value: "true"})

	tbl := database.Get().Register("NetworkAgent")
	agent := models.NetworkAgent{UploaderID: 1, Name: "正常智能体", Description: "d", Persona: "p", Status: "pending"}
	if err := tbl.Insert(&agent); err != nil {
		t.Fatal(err)
	}

	// 注入假模型
	origChat := aiReviewService.Chat
	t.Cleanup(func() { aiReviewService.Chat = origChat })
	var mockResp services.ChatCompletionResponse
	if err := json.Unmarshal([]byte(`{"choices":[{"message":{"content":"{\"pass\":true,\"risk_level\":\"none\",\"reason\":\"内容正常\"}"}}]}`), &mockResp); err != nil {
		t.Fatal(err)
	}
	aiReviewService.Chat = func(_ context.Context, req *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
		return &mockResp, nil
	}

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.POST("/agents/:id/ai-review", handler.ReviewAgent)

	recorder := doJSON(router, http.MethodPost, "/agents/1/ai-review", "")
	var resp struct {
		Code int `json:"code"`
		Data struct {
			Pass      bool   `json:"pass"`
			RiskLevel string `json:"risk_level"`
			Reason    string `json:"reason"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Code != utils.CodeSuccess || !resp.Data.Pass || resp.Data.RiskLevel != "none" {
		t.Fatalf("响应错误: %s", recorder.Body.String())
	}

	var updated models.NetworkAgent
	tbl.FindByID(agent.ID, &updated)
	if updated.AiReviewStatus != "pass" || updated.AiReviewReason != "内容正常" || updated.AiReviewedAt == "" || updated.Status != "approved" {
		t.Fatalf("写回错误: ai=%q market=%q reason=%q at=%q", updated.AiReviewStatus, updated.Status, updated.AiReviewReason, updated.AiReviewedAt)
	}
}

func TestAiReviewGroupManualReviewReject(t *testing.T) {
	setupAiReviewTestDB(t)

	cfgTbl := database.Get().Register("SystemConfig")
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewEnabledConfigKey, Value: "true"})

	tbl := database.Get().Register("NetworkGroup")
	group := models.NetworkGroup{UploaderID: 1, Name: "违规群", Description: "d", Status: "pending"}
	if err := tbl.Insert(&group); err != nil {
		t.Fatal(err)
	}

	origChat := aiReviewService.Chat
	t.Cleanup(func() { aiReviewService.Chat = origChat })
	var mockResp services.ChatCompletionResponse
	if err := json.Unmarshal([]byte(`{"choices":[{"message":{"content":"{\"pass\":false,\"risk_level\":\"high\",\"reason\":\"含违规内容\"}"}}]}`), &mockResp); err != nil {
		t.Fatal(err)
	}
	aiReviewService.Chat = func(_ context.Context, req *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
		return &mockResp, nil
	}

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.POST("/groups/:id/ai-review", handler.ReviewGroup)

	recorder := doJSON(router, http.MethodPost, "/groups/1/ai-review", "")
	var resp struct {
		Code int `json:"code"`
		Data struct {
			Pass bool `json:"pass"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Code != utils.CodeSuccess || resp.Data.Pass {
		t.Fatalf("响应错误: %s", recorder.Body.String())
	}

	var updated models.NetworkGroup
	tbl.FindByID(group.ID, &updated)
	if updated.AiReviewStatus != "reject" || updated.AiReviewReason != "含违规内容" || updated.Status != "rejected" || updated.RejectReason != "含违规内容" {
		t.Fatalf("写回错误: ai=%q market=%q reason=%q reject=%q", updated.AiReviewStatus, updated.Status, updated.AiReviewReason, updated.RejectReason)
	}
}

func TestAiReviewAgentNotFound(t *testing.T) {
	setupAiReviewTestDB(t)

	cfgTbl := database.Get().Register("SystemConfig")
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewEnabledConfigKey, Value: "true"})

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.POST("/agents/:id/ai-review", handler.ReviewAgent)

	recorder := doJSON(router, http.MethodPost, "/agents/999/ai-review", "")
	var resp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Code != utils.CodeNotFound {
		t.Fatalf("记录不存在应返回 40400, got %d", resp.Code)
	}
}

func TestTriggerAutoAiReviewAgentWritesBack(t *testing.T) {
	setupAiReviewTestDB(t)
	originalHub := hub.Hub
	hub.Hub = hub.NewSyncHub()
	services.SetEventPublisher(hub.Hub)
	client := &hub.SyncClient{
		UserID:   1,
		DeviceID: "test-device",
		Send:     make(chan []byte, 4),
		Hub:      hub.Hub,
	}
	hub.Hub.RegisterClient(client)
	t.Cleanup(func() {
		hub.Hub = originalHub
		services.SetEventPublisher(nil)
	})

	cfgTbl := database.Get().Register("SystemConfig")
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewEnabledConfigKey, Value: "true"})
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewAutoConfigKey, Value: "true"})

	tbl := database.Get().Register("NetworkAgent")
	agent := models.NetworkAgent{UploaderID: 1, Name: "自动预审", Status: "pending"}
	if err := tbl.Insert(&agent); err != nil {
		t.Fatal(err)
	}

	origChat := aiReviewService.Chat
	t.Cleanup(func() { aiReviewService.Chat = origChat })
	var mockResp services.ChatCompletionResponse
	if err := json.Unmarshal([]byte(`{"choices":[{"message":{"content":"{\"pass\":true,\"risk_level\":\"low\",\"reason\":\"基本正常\"}"}}]}`), &mockResp); err != nil {
		t.Fatal(err)
	}
	aiReviewService.Chat = func(_ context.Context, req *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
		return &mockResp, nil
	}

	TriggerAutoAiReviewAgent(agent.ID)

	// 异步 goroutine 写回，轮询等待
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		var updated models.NetworkAgent
		tbl.FindByID(agent.ID, &updated)
		if updated.AiReviewStatus != "" {
			if updated.AiReviewStatus != "pass" || updated.AiReviewReason != "基本正常" || updated.Status != "approved" {
				t.Fatalf("自动预审写回错误: ai=%q market=%q reason=%q", updated.AiReviewStatus, updated.Status, updated.AiReviewReason)
			}
			select {
			case payload := <-client.Send:
				var message hub.SyncMessage
				if err := json.Unmarshal(payload, &message); err != nil {
					t.Fatal(err)
				}
				if message.Type != "app_event" || message.Scope != hub.AppEventScopeMyUploads || message.Status != "approved" {
					t.Fatalf("自动预审事件错误: %#v", message)
				}
			case <-time.After(time.Second):
				t.Fatal("自动预审完成后未发送上传状态事件")
			}
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("自动预审未在超时内写回记录")
}

func TestTriggerAutoAiReviewSkippedWhenAutoOff(t *testing.T) {
	setupAiReviewTestDB(t)

	cfgTbl := database.Get().Register("SystemConfig")
	cfgTbl.Insert(&models.SystemConfig{Key: services.AiReviewEnabledConfigKey, Value: "true"})
	// auto 未开启

	tbl := database.Get().Register("NetworkAgent")
	agent := models.NetworkAgent{UploaderID: 1, Name: "不预审", Status: "pending"}
	if err := tbl.Insert(&agent); err != nil {
		t.Fatal(err)
	}

	origChat := aiReviewService.Chat
	t.Cleanup(func() { aiReviewService.Chat = origChat })
	called := false
	aiReviewService.Chat = func(_ context.Context, req *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error) {
		called = true
		return nil, nil
	}

	TriggerAutoAiReviewAgent(agent.ID)
	time.Sleep(100 * time.Millisecond)
	if called {
		t.Fatal("auto 关闭时不应发起 AI 审核")
	}
}

func TestAiReviewConfigModelValidation(t *testing.T) {
	setupAiReviewTestDB(t)

	database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID: "gemini-2.5-flash", ModelName: "Gemini", Provider: "gemini", Status: 1,
	})

	router := gin.New()
	handler := &NetworkAiReviewHandler{}
	router.GET("/cfg", handler.GetConfig)
	router.PUT("/cfg", handler.UpdateConfig)

	// PUT 不存在的模型 → 40000
	recorder := doJSON(router, http.MethodPut, "/cfg", `{"enabled":false,"auto":false,"prompt":"p","model":"no-such-model"}`)
	var badResp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &badResp); err != nil {
		t.Fatal(err)
	}
	if badResp.Code != utils.CodeBadRequest {
		t.Fatalf("不存在的模型应返回 40000, got %d (%s)", badResp.Code, recorder.Body.String())
	}

	// PUT 合法模型 → 成功并持久化，GET 返回该字段
	recorder = doJSON(router, http.MethodPut, "/cfg", `{"enabled":false,"auto":false,"prompt":"p","model":"gemini-2.5-flash"}`)
	var okResp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &okResp); err != nil {
		t.Fatal(err)
	}
	if okResp.Code != utils.CodeSuccess {
		t.Fatalf("合法模型 PUT 失败: %s", recorder.Body.String())
	}
	if got := services.GetAiReviewModel(); got != "gemini-2.5-flash" {
		t.Fatalf("模型未持久化, got %q", got)
	}
	recorder = doJSON(router, http.MethodGet, "/cfg", "")
	var getResp struct {
		Code int `json:"code"`
		Data struct {
			Model string `json:"model"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &getResp); err != nil {
		t.Fatal(err)
	}
	if getResp.Data.Model != "gemini-2.5-flash" {
		t.Fatalf("GET 应返回已配置模型, got %q", getResp.Data.Model)
	}

	// PUT 空值（自动）→ 允许并清空
	recorder = doJSON(router, http.MethodPut, "/cfg", `{"enabled":false,"auto":false,"prompt":"p","model":""}`)
	if err := json.Unmarshal(recorder.Body.Bytes(), &okResp); err != nil {
		t.Fatal(err)
	}
	if okResp.Code != utils.CodeSuccess {
		t.Fatalf("空模型 PUT 失败: %s", recorder.Body.String())
	}
	if got := services.GetAiReviewModel(); got != "" {
		t.Fatalf("空值应清空配置, got %q", got)
	}
}
