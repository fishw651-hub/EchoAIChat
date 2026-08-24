package services

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

// imageURLBody 模拟客户端发送的含数组型 content（image_url）的聊天请求体。
const imageURLBody = `{
	"model": "PLACEHOLDER",
	"messages": [
		{"role": "user", "content": [
			{"type": "text", "text": "图里有什么？"},
			{"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="}}
		]}
	]
}`

// runImageURLPassthrough 以指定 api_format 配置上游站点，验证 image_url
// 请求体能绑定为 ChatCompletionRequest 并原样转发到上游。
func runImageURLPassthrough(t *testing.T, model, provider, format string) {
	t.Helper()

	var gotBody map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &gotBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"x","object":"chat.completion","created":1,"model":"` + model + `","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}`))
	}))
	defer server.Close()

	insertRoutingAPIKey(t, provider, server.URL, format, "sk-"+provider)
	price := models.ModelPrice{ModelID: model, Provider: provider, Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	// 与 handler 层 ShouldBindJSON 相同的绑定路径：同一 ChatMessage 结构。
	var req ChatCompletionRequest
	if err := json.Unmarshal([]byte(imageURLBody), &req); err != nil {
		t.Fatalf("bind image_url body: %v", err)
	}
	req.Model = model

	if _, err := (&DeepSeekService{}).ChatCompletion(context.Background(), &req); err != nil {
		t.Fatalf("ChatCompletion: %v", err)
	}

	messages, ok := gotBody["messages"].([]interface{})
	if !ok || len(messages) != 1 {
		t.Fatalf("upstream messages = %v, want 1 message", gotBody["messages"])
	}
	msg := messages[0].(map[string]interface{})
	content, ok := msg["content"].([]interface{})
	if !ok || len(content) != 2 {
		t.Fatalf("upstream content = %v, want 2 content parts", msg["content"])
	}
	imagePart, ok := content[1].(map[string]interface{})
	if !ok || imagePart["type"] != "image_url" {
		t.Fatalf("second content part = %v, want image_url part", content[1])
	}
	imageURL, ok := imagePart["image_url"].(map[string]interface{})
	if !ok || imageURL["url"] != "data:image/png;base64,iVBORw0KGgo=" {
		t.Fatalf("image_url = %v, want passthrough data url", imagePart["image_url"])
	}
}

// TestImageURLPassthroughOpenAI 验证 openai 格式站点原样转发 image_url 内容。
func TestImageURLPassthroughOpenAI(t *testing.T) {
	setupRoutingTestDB(t)
	runImageURLPassthrough(t, "vision-openai", "deepseek", "openai")
}

// TestImageURLPassthroughGemini 验证 gemini 格式适配不会剥离 image_url 内容
//（adaptRequestForFormat 只剥 thinking/extra_body/reasoning_effort/tool_choice）。
func TestImageURLPassthroughGemini(t *testing.T) {
	setupRoutingTestDB(t)
	runImageURLPassthrough(t, "vision-gemini", "gemini", "gemini")
}
