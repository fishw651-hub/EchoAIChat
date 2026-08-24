package services

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

type upstreamRetryWait func(context.Context, time.Duration) error

type DeepSeekService struct {
	completionClient *http.Client
	retryWait        upstreamRetryWait
	now              func() time.Time
}

func (s *DeepSeekService) client() *http.Client {
	if s.completionClient != nil {
		return s.completionClient
	}
	return getUpstreamClients().completion
}

func (s *DeepSeekService) clock() func() time.Time {
	if s.now != nil {
		return s.now
	}
	return time.Now
}

func (s *DeepSeekService) wait(ctx context.Context, delay time.Duration) error {
	if s.retryWait != nil {
		return s.retryWait(ctx, delay)
	}
	return waitForUpstreamRetry(ctx, delay)
}

type ChatMessage struct {
	Role       string      `json:"role"`
	Content    interface{} `json:"content,omitempty"`
	ToolCallID string      `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall  `json:"tool_calls,omitempty"`
	Name       string      `json:"name,omitempty"`
}

type ChatCompletionRequest struct {
	Model           string                   `json:"model"`
	Messages        []ChatMessage            `json:"messages"`
	Stream          bool                     `json:"stream,omitempty"`
	MaxTokens       int                      `json:"max_tokens,omitempty"`
	Temperature     float64                  `json:"temperature,omitempty"`
	TopP            float64                  `json:"top_p,omitempty"`
	Tools           []map[string]interface{} `json:"tools,omitempty"`
	ToolChoice      interface{}              `json:"tool_choice,omitempty"`
	StreamOptions   *StreamOptions           `json:"stream_options,omitempty"`
	ReasoningEffort string                   `json:"reasoning_effort,omitempty"`
	ExtraBody       *ThinkingBody            `json:"extra_body,omitempty"`
}

type StreamOptions struct {
	IncludeUsage bool `json:"include_usage"`
}

type ToolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Function ToolFunction `json:"function"`
}

type ToolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type ThinkingBody struct {
	Thinking ThinkingConfig `json:"thinking"`
}

type ThinkingConfig struct {
	Type string `json:"type"`
}

type ChatCompletionResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index   int `json:"index"`
		Message struct {
			Role             string     `json:"role"`
			Content          string     `json:"content"`
			ReasoningContent string     `json:"reasoning_content"`
			ToolCalls        []ToolCall `json:"tool_calls,omitempty"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
		PromptTokens          int `json:"prompt_tokens"`
		CompletionTokens      int `json:"completion_tokens"`
		TotalTokens           int `json:"total_tokens"`
		PromptCacheHitTokens  int `json:"prompt_cache_hit_tokens"`
		PromptCacheMissTokens int `json:"prompt_cache_miss_tokens"`
	} `json:"usage"`
}

type DeepSeekModel struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	OwnedBy string `json:"owned_by"`
}

type ModelsResponse struct {
	Object string          `json:"object"`
	Data   []DeepSeekModel `json:"data"`
}

func (s *DeepSeekService) getActiveAPIKey() (string, error) {
	var keys []models.APIKey
	database.Get().Register("APIKey").FindAll(&keys, nil, "", 0, 0)
	for _, k := range keys {
		if k.Provider == "deepseek" && k.IsActive {
			decrypted, err := DecryptWithConfiguredKeys(k.APIKeyEncrypted)
			if err != nil {
				return "", fmt.Errorf("API Key解密失败")
			}
			return decrypted, nil
		}
	}
	return "", fmt.Errorf("没有可用的DeepSeek API Key，请在后台配置")
}

const (
	// ApiFormatOpenAI 透传 OpenAI chat/completions 报文（现状行为）。
	ApiFormatOpenAI = "openai"
	// ApiFormatGemini 走 Gemini 的 OpenAI 兼容端点，需剥离 DeepSeek 特有参数。
	ApiFormatGemini = "gemini"
	// DefaultGeminiBaseURL 是 gemini 格式 key 未配置 BaseURL 时的回退站点。
	DefaultGeminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
)

// upstreamTarget 是按模型路由出的上游站点信息。
type upstreamTarget struct {
	Provider string
	BaseURL  string
	APIKey   string
	Format   string
}

// UpstreamConfigError 表示上游路由配置缺失（如模型对应的 provider 没有可用 key），
// 与上游返回的业务错误区分，handler 层据此返回 502。
type UpstreamConfigError struct {
	Message string
}

func (e *UpstreamConfigError) Error() string { return e.Message }

// UpstreamHTTPError 保留供应商 HTTP 错误的状态与重试信息，供 handler
// 在写响应头之前映射为稳定的客户端业务码。
type UpstreamHTTPError struct {
	Provider   string
	StatusCode int
	Body       string
	RetryAfter string
}

func (e *UpstreamHTTPError) Error() string {
	return fmt.Sprintf("%s上游返回错误(%d): %s", e.Provider, e.StatusCode, e.Body)
}

func readUpstreamHTTPError(provider string, resp *http.Response) error {
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取%s上游错误响应失败: %w", provider, err)
	}
	return &UpstreamHTTPError{
		Provider:   provider,
		StatusCode: resp.StatusCode,
		Body:       string(body),
		RetryAfter: resp.Header.Get("Retry-After"),
	}
}

// resolveUpstream 按模型解析上游：模型 → ModelPrice.Provider（查不到/空 → deepseek）
// → 该 provider 第一个 active 的 APIKey → 站点 + 解密 key + api_format。
func (s *DeepSeekService) resolveUpstream(model string) (*upstreamTarget, error) {
	provider := "deepseek"
	var price models.ModelPrice
	if database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", model), &price) {
		if p := strings.TrimSpace(price.Provider); p != "" {
			provider = p
		}
	}

	var keys []models.APIKey
	database.Get().Register("APIKey").FindAll(&keys, nil, "", 0, 0)
	for _, k := range keys {
		if k.Provider != provider || !k.IsActive {
			continue
		}
		decrypted, err := DecryptWithConfiguredKeys(k.APIKeyEncrypted)
		if err != nil {
			return nil, fmt.Errorf("API Key解密失败")
		}
		format := strings.TrimSpace(k.ApiFormat)
		if format == "" {
			format = ApiFormatOpenAI
		}
		baseURL := strings.TrimRight(strings.TrimSpace(k.BaseURL), "/")
		if baseURL == "" {
			if format == ApiFormatGemini {
				baseURL = DefaultGeminiBaseURL
			} else {
				baseURL = strings.TrimRight(runtimeDeepSeekBaseURL(), "/")
			}
		}
		return &upstreamTarget{
			Provider: provider,
			BaseURL:  baseURL,
			APIKey:   decrypted,
			Format:   format,
		}, nil
	}
	return nil, &UpstreamConfigError{
		Message: fmt.Sprintf("模型 %s 的供应商 %s 没有可用的 API Key，请在后台配置", model, provider),
	}
}

// ResolveUpstream 按模型解析上游站点，供 handler 在写 SSE 响应头之前预检路由配置。
func (s *DeepSeekService) ResolveUpstream(model string) error {
	_, err := s.resolveUpstream(model)
	return err
}

// adaptRequestForFormat 按上游 api_format 适配请求报文。
// gemini 格式剥离 DeepSeek 特有参数（thinking ExtraBody、reasoning_effort），
// tool_choice 为 'required' 时降级为 'auto'；openai 格式透传。
func adaptRequestForFormat(req *ChatCompletionRequest, format string) *ChatCompletionRequest {
	if format != ApiFormatGemini {
		return req
	}
	adapted := *req
	adapted.ExtraBody = nil
	adapted.ReasoningEffort = ""
	if tc, ok := adapted.ToolChoice.(string); ok && tc == "required" {
		adapted.ToolChoice = "auto"
	}
	return &adapted
}

// ChatCompletion 非流式调用上游。ctx 来自客户端请求：客户端断开/超时后上游请求随之取消，不再空耗 token。
func (s *DeepSeekService) ChatCompletion(ctx context.Context, req *ChatCompletionRequest) (*ChatCompletionResponse, error) {
	target, err := s.resolveUpstream(req.Model)
	if err != nil {
		return nil, err
	}
	return s.chatCompletionWithTarget(ctx, adaptRequestForFormat(req, target.Format), target)
}

func (s *DeepSeekService) chatCompletionWithTarget(ctx context.Context, req *ChatCompletionRequest, target *upstreamTarget) (*ChatCompletionResponse, error) {
	req.Stream = false
	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("序列化%s上游请求失败: %w", target.Provider, err)
	}

	var lastErr error
	for attempt := 0; attempt < maxUpstreamAttempts; attempt++ {
		result, err := s.chatCompletionAttempt(ctx, target, jsonData)
		if err == nil {
			return result, nil
		}
		lastErr = err
		if attempt+1 == maxUpstreamAttempts {
			break
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}

		delay, retry := upstreamRetryDelay(err, s.clock()())
		if !retry {
			return nil, err
		}
		log.Printf("[upstream retry] provider=%s model=%s next_attempt=%d category=%s delay=%s", target.Provider, req.Model, attempt+2, upstreamRetryCategory(err), delay)
		if err := s.wait(ctx, delay); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
	}

	return nil, lastErr
}

func (s *DeepSeekService) chatCompletionAttempt(ctx context.Context, target *upstreamTarget, jsonData []byte) (*ChatCompletionResponse, error) {
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, target.BaseURL+"/chat/completions", bytes.NewReader(jsonData))
	if err != nil {
		return nil, fmt.Errorf("创建%s上游请求失败: %w", target.Provider, err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+target.APIKey)

	resp, err := s.client().Do(httpReq)
	if err != nil {
		return nil, &upstreamTransportError{Provider: target.Provider, Err: err}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, readUpstreamHTTPError(target.Provider, resp)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取%s上游响应失败: %w", target.Provider, err)
	}

	var result ChatCompletionResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("解析%s上游响应失败: %w", target.Provider, err)
	}
	return &result, nil
}

func upstreamRetryCategory(err error) string {
	var httpErr *UpstreamHTTPError
	if errors.As(err, &httpErr) {
		return fmt.Sprintf("http_%d", httpErr.StatusCode)
	}
	var transportErr *upstreamTransportError
	if errors.As(err, &transportErr) {
		return "transport"
	}
	return "other"
}

// ChatCompletionStream 流式调用上游。ctx 来自客户端请求：客户端中途断开 SSE 后上游流随之取消。
func (s *DeepSeekService) ChatCompletionStream(ctx context.Context, req *ChatCompletionRequest, writer io.Writer) (*ChatCompletionResponse, error) {
	target, err := s.resolveUpstream(req.Model)
	if err != nil {
		return nil, err
	}
	req = adaptRequestForFormat(req, target.Format)

	req.Stream = true
	req.StreamOptions = &StreamOptions{IncludeUsage: true}

	jsonData, _ := json.Marshal(req)
	httpReq, _ := http.NewRequestWithContext(ctx, "POST", target.BaseURL+"/chat/completions", bytes.NewBuffer(jsonData))
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+target.APIKey)
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := getUpstreamClients().stream.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("请求%s上游失败: %w", target.Provider, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, readUpstreamHTTPError(target.Provider, resp)
	}

	var finalUsage *ChatCompletionResponse
	// 已流出的内容字节数：流中途截断时据此估算部分用量做结算，
	// 防止"反复触发中断→全额退预留"的白嫖上游 token 路径
	streamedBytes := 0
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		data := strings.TrimPrefix(line, "data: ")
		if data == "[DONE]" {
			break
		}

		var chunk map[string]interface{}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}

		if usage, ok := chunk["usage"]; ok && usage != nil {
			usageJSON, _ := json.Marshal(chunk)
			var final ChatCompletionResponse
			json.Unmarshal(usageJSON, &final)
			finalUsage = &final
		}

		streamedBytes += len(data)
		fmt.Fprintf(writer, "data: %s\n\n", data)
		if f, ok := writer.(http.Flusher); ok {
			f.Flush()
		}
	}

	// 必须检查扫描错误：上游单行超过缓冲区上限（1MB）或连接中断时 Scan 循环会静默结束。
	// 此时不得补写 [DONE] 假装正常收尾。已流出部分内容的，返回部分用量估算
	//（prompt 取已见 usage 或按请求体粗估，completion 按流出字节/4 粗估）供部分结算；
	// 什么都没流出的返回 nil result，handler 全额释放预留。
	if err := scanner.Err(); err != nil {
		if streamedBytes > 0 {
			partial := &ChatCompletionResponse{}
			promptEstimate := 0
			for _, m := range req.Messages {
				// Content 为 string 或视觉数组（interface{}），统一按字节粗估
				if s, ok := m.Content.(string); ok {
					promptEstimate += len(s) / 4
				} else if b, jerr := json.Marshal(m.Content); jerr == nil {
					promptEstimate += len(b) / 4
				}
			}
			if finalUsage != nil {
				partial.Usage = finalUsage.Usage
			} else {
				partial.Usage.PromptTokens = promptEstimate
				partial.Usage.CompletionTokens = streamedBytes / 4
			}
			partial.Model = req.Model
			return partial, fmt.Errorf("读取%s上游流失败（响应被截断）: %w", target.Provider, err)
		}
		return nil, fmt.Errorf("读取%s上游流失败（响应被截断）: %w", target.Provider, err)
	}

	fmt.Fprintf(writer, "data: [DONE]\n\n")
	if f, ok := writer.(http.Flusher); ok {
		f.Flush()
	}

	if finalUsage == nil {
		finalUsage = &ChatCompletionResponse{}
		log.Printf("[billing] 上游 %s 未返回 usage，流式响应按零 token 结算（price_per_call 仍适用）", target.Provider)
		finalUsage.Model = req.Model
	}

	return finalUsage, nil
}

func (s *DeepSeekService) FetchModels() ([]DeepSeekModel, error) {
	apiKey, err := s.getActiveAPIKey()
	if err != nil {
		return nil, err
	}

	httpReq, _ := http.NewRequest("GET", runtimeDeepSeekBaseURL()+"/models", nil)
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := getUpstreamClients().metadata.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("获取模型列表失败: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("获取模型列表失败(%d): %s", resp.StatusCode, string(body))
	}

	var result ModelsResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("解析模型列表失败: %w", err)
	}

	return result.Data, nil
}

func (s *DeepSeekService) SyncModelPrices() error {
	dsModels, err := s.FetchModels()
	if err != nil {
		return err
	}

	tbl := database.Get().Register("ModelPrice")
	defaultPrices := map[string]struct {
		input      float64
		inputCache float64
		output     float64
	}{
		"deepseek-v4-flash": {1, 0.02, 2},
		"deepseek-v4-pro":   {3, 0.025, 6},
	}

	for _, dsModel := range dsModels {
		var existing models.ModelPrice
		if !tbl.FindOne(database.FilterEq("ModelID", dsModel.ID), &existing) {
			price := models.ModelPrice{
				ModelID:                         dsModel.ID,
				ModelName:                       dsModel.ID,
				InputPricePer1M:                 1,
				InputCacheHitPricePer1M:         0.02,
				OutputPricePer1M:                2,
				ThinkingInputPricePer1M:         3,
				ThinkingInputCacheHitPricePer1M: 0.025,
				ThinkingOutputPricePer1M:        6,
				Status:                          1,
				ThinkingStatus:                  1,
			}
			if dp, ok := defaultPrices[dsModel.ID]; ok {
				price.InputPricePer1M = dp.input
				price.InputCacheHitPricePer1M = dp.inputCache
				price.OutputPricePer1M = dp.output
				price.ThinkingInputPricePer1M = dp.input * 3
				price.ThinkingInputCacheHitPricePer1M = dp.inputCache * 1.25
				price.ThinkingOutputPricePer1M = dp.output * 3
			}
			tbl.Insert(&price)
		}
	}

	log.Printf("模型价格同步完成，共处理%d个模型", len(dsModels))
	return nil
}
