package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/models"
)

// AI 内容审核的系统配置键
const (
	AiReviewEnabledConfigKey = "ai_review_enabled"
	AiReviewAutoConfigKey    = "ai_review_auto"
	AiReviewPromptConfigKey  = "ai_review_prompt"
	// AiReviewModelConfigKey 指定审核模型（ModelPrice 表的 model_id），空 = 自动回退链
	AiReviewModelConfigKey = "ai_review_model"
)

// DefaultAiReviewPrompt 默认内容审核提示词（PUT 配置时留空 prompt 也会回落到此值）
const DefaultAiReviewPrompt = `你是一个内容安全审核员。请审核用户上传到 AI 角色市场的内容（名称、描述、人设、世界观）。

检查以下违规类别：
1. 色情、性暗示或性交易内容（含未成年人不当内容）
2. 暴力、血腥、恐怖主义内容
3. 违法违规内容（赌博、毒品、诈骗、侵权等）
4. 广告、引流、营销内容
5. 仇恨、歧视、侮辱性内容

只输出一个 JSON 对象，不要输出任何其他文字、解释或 markdown 标记：
{"pass": true 或 false, "risk_level": "none|low|medium|high", "reason": "简短中文理由"}

pass=true 表示内容可以发布；risk_level 表示风险等级（none 无风险、low 轻微、medium 中等、high 严重）。`

// AiReviewVerdict AI 审核结论
type AiReviewVerdict struct {
	Pass      bool   `json:"pass"`
	RiskLevel string `json:"risk_level"` // none/low/medium/high
	Reason    string `json:"reason"`
}

// GetAiReviewConfig 读取 AI 审核配置；prompt 未配置时回落到默认提示词
func GetAiReviewConfig() (enabled bool, auto bool, prompt string) {
	prompt = DefaultAiReviewPrompt
	db := database.Get()
	if db == nil {
		return false, false, prompt
	}
	tbl := db.Register("SystemConfig")
	var sc models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", AiReviewEnabledConfigKey), &sc) {
		enabled = sc.Value == "true"
	}
	var ac models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", AiReviewAutoConfigKey), &ac) {
		auto = ac.Value == "true"
	}
	var pc models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", AiReviewPromptConfigKey), &pc) && strings.TrimSpace(pc.Value) != "" {
		prompt = pc.Value
	}
	return enabled, auto, prompt
}

// GetAiReviewModel 读取配置的审核模型；空串表示自动（走 pickAiReviewModel 回退链）
func GetAiReviewModel() string {
	db := database.Get()
	if db == nil {
		return ""
	}
	var sc models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", AiReviewModelConfigKey), &sc) {
		return strings.TrimSpace(sc.Value)
	}
	return ""
}

// AiReviewService 网络市场内容 AI 审核
type AiReviewService struct {
	// Chat 可注入（测试用）；nil 时走真实上游调用（按模型路由，30s 超时）
	Chat func(ctx context.Context, req *ChatCompletionRequest) (*ChatCompletionResponse, error)
}

// aiReviewHTTPClient 独立的 30s 超时客户端（共享 completion 客户端为 120s，不符合审核场景）
var aiReviewHTTPClient = &http.Client{
	Timeout:   30 * time.Second,
	Transport: NewUpstreamTransport(config.NetworkConfig{}),
}

// pickAiReviewModel 选一个可用的非思考模型：优先 deepseek-v4-flash（便宜快速），
// 否则取 ModelPrice 表中第一个 Status==1 的模型，表为空时回落常量
func pickAiReviewModel() string {
	const fallbackModel = "deepseek-v4-flash"
	db := database.Get()
	if db == nil {
		return fallbackModel
	}
	var prices []models.ModelPrice
	db.Register("ModelPrice").FindAll(&prices, nil, "ID asc", 0, 0)
	first := ""
	for _, p := range prices {
		if p.Status != 1 {
			continue
		}
		if p.ModelID == fallbackModel {
			return p.ModelID
		}
		if first == "" {
			first = p.ModelID
		}
	}
	if first != "" {
		return first
	}
	return fallbackModel
}

// resolveAiReviewModel 决定审核用模型：配置了 ai_review_model 就用它，
// 否则走 pickAiReviewModel 回退链（deepseek-v4-flash → 第一个启用模型 → 常量）
func resolveAiReviewModel() string {
	if m := GetAiReviewModel(); m != "" {
		return m
	}
	return pickAiReviewModel()
}

// defaultAiReviewChat 真实上游调用（非思考模式，30s 超时）。
// 按 req.Model 经 resolveUpstream 路由到对应 provider 站点（base_url + key + api_format），
// gemini 格式由 adaptRequestForFormat 剥离 DeepSeek 特有参数。ctx 取消时上游请求随之终止。
func defaultAiReviewChat(ctx context.Context, req *ChatCompletionRequest) (*ChatCompletionResponse, error) {
	ds := &DeepSeekService{}
	target, err := ds.resolveUpstream(req.Model)
	if err != nil {
		return nil, err
	}
	if target.BaseURL == "" {
		return nil, fmt.Errorf("模型 %s 的上游站点未配置", req.Model)
	}
	req = adaptRequestForFormat(req, target.Format)

	jsonData, _ := json.Marshal(req)
	httpReq, err := http.NewRequestWithContext(ctx, "POST", target.BaseURL+"/chat/completions", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("审核请求地址无效: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+target.APIKey)

	resp, err := aiReviewHTTPClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("请求%s上游失败: %w", target.Provider, err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("%s上游返回错误(%d)", target.Provider, resp.StatusCode)
	}
	var result ChatCompletionResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("解析上游响应失败: %w", err)
	}
	return &result, nil
}

// truncateRunes 截断过长字段，避免审核 prompt 爆炸
func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max]) + "…(已截断)"
}

// buildReviewUserContent 组装待审核内容
func buildReviewUserContent(name, description, persona, worldview string) string {
	var sb strings.Builder
	sb.WriteString("【名称】\n" + truncateRunes(name, 200) + "\n\n")
	sb.WriteString("【描述】\n" + truncateRunes(description, 2000) + "\n\n")
	sb.WriteString("【人设】\n" + truncateRunes(persona, 4000) + "\n\n")
	sb.WriteString("【世界观】\n" + truncateRunes(worldview, 4000))
	return sb.String()
}

// ReviewNetworkContent 审核网络市场内容。enabled=false 时返回明确错误。
// ctx 来自调用方：同步审核（管理端手动触发）传请求 ctx；异步预审传 context.Background()。
func (s *AiReviewService) ReviewNetworkContent(ctx context.Context, name, description, persona, worldview string) (AiReviewVerdict, error) {
	enabled, _, prompt := GetAiReviewConfig()
	if !enabled {
		return AiReviewVerdict{}, fmt.Errorf("AI 内容审核未启用")
	}

	chat := s.Chat
	if chat == nil {
		chat = defaultAiReviewChat
	}
	resp, err := chat(ctx, &ChatCompletionRequest{
		Model: resolveAiReviewModel(),
		Messages: []ChatMessage{
			{Role: "system", Content: prompt},
			{Role: "user", Content: buildReviewUserContent(name, description, persona, worldview)},
		},
		MaxTokens:   512,
		Temperature: 0.1,
	})
	if err != nil {
		return AiReviewVerdict{}, err
	}
	if len(resp.Choices) == 0 {
		return AiReviewVerdict{}, fmt.Errorf("上游响应缺少 choices")
	}
	return ParseAiReviewVerdict(resp.Choices[0].Message.Content)
}

// extractFirstJSONObject 容错提取文本中的第一个 JSON 对象（括号配平 + 字符串感知），
// 兼容 markdown 围栏（```json ... ```）与前后脏文本
func extractFirstJSONObject(s string) string {
	start := strings.IndexByte(s, '{')
	if start < 0 {
		return ""
	}
	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(s); i++ {
		ch := s[i]
		if inString {
			if escaped {
				escaped = false
			} else if ch == '\\' {
				escaped = true
			} else if ch == '"' {
				inString = false
			}
			continue
		}
		switch ch {
		case '"':
			inString = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return s[start : i+1]
			}
		}
	}
	return ""
}

// ParseAiReviewVerdict 解析模型输出为审核结论；提取不到合法 JSON 时返回 err
func ParseAiReviewVerdict(content string) (AiReviewVerdict, error) {
	raw := extractFirstJSONObject(strings.TrimSpace(content))
	if raw == "" {
		return AiReviewVerdict{}, fmt.Errorf("AI 审核输出中未找到 JSON 结论")
	}
	var verdict AiReviewVerdict
	if err := json.Unmarshal([]byte(raw), &verdict); err != nil {
		return AiReviewVerdict{}, fmt.Errorf("AI 审核结论 JSON 解析失败: %w", err)
	}
	verdict.RiskLevel = strings.ToLower(strings.TrimSpace(verdict.RiskLevel))
	switch verdict.RiskLevel {
	case "none", "low", "medium", "high":
	default:
		// 模型输出了非法等级时按 pass 结果兜底
		if verdict.Pass {
			verdict.RiskLevel = "none"
		} else {
			verdict.RiskLevel = "high"
		}
	}
	verdict.Reason = strings.TrimSpace(verdict.Reason)
	if verdict.Reason == "" {
		verdict.Reason = "（AI 未给出理由）"
	}
	return verdict, nil
}
