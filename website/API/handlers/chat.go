package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type ChatHandler struct {
	deepseekService chatCompletionService
	billingService  chatBillingService
}

type chatCompletionService interface {
	ChatCompletion(context.Context, *services.ChatCompletionRequest) (*services.ChatCompletionResponse, error)
}

type chatBillingService interface {
	Reserve(uint, string, []services.ChatMessage, int, bool) (*services.BillingReservation, error)
	Release(string) error
	Settle(string, string, string, int, int, int, int, bool) (float64, error)
}

func NewChatHandler() *ChatHandler {
	return &ChatHandler{
		deepseekService: &services.DeepSeekService{},
		billingService:  &services.BillingService{},
	}
}

func writeChatUpstreamError(c *gin.Context, err error) bool {
	var upstreamErr *services.UpstreamHTTPError
	if errors.As(err, &upstreamErr) {
		if upstreamErr.RetryAfter != "" {
			c.Header("Retry-After", upstreamErr.RetryAfter)
		}
		if upstreamErr.StatusCode == http.StatusTooManyRequests {
			c.JSON(http.StatusTooManyRequests, utils.Response{
				Code:    utils.CodeTooManyReqs,
				Message: "上游请求过于频繁，请稍后重试",
				Data:    nil,
			})
			return true
		}
		c.JSON(http.StatusBadGateway, utils.Response{
			Code:    utils.CodeBadGateway,
			Message: "上游服务暂时不可用，请稍后重试",
			Data:    nil,
		})
		return true
	}

	var cfgErr *services.UpstreamConfigError
	if errors.As(err, &cfgErr) {
		c.JSON(http.StatusBadGateway, utils.Response{
			Code:    utils.CodeBadGateway,
			Message: cfgErr.Error(),
			Data:    nil,
		})
		return true
	}
	return false
}

func legacyCompletionChunk(result *services.ChatCompletionResponse) gin.H {
	choices := make([]gin.H, 0, len(result.Choices))
	for _, choice := range result.Choices {
		delta := gin.H{"role": choice.Message.Role}
		if choice.Message.Content != "" {
			delta["content"] = choice.Message.Content
		}
		if choice.Message.ReasoningContent != "" {
			delta["reasoning_content"] = choice.Message.ReasoningContent
		}
		if len(choice.Message.ToolCalls) > 0 {
			toolCalls := make([]gin.H, 0, len(choice.Message.ToolCalls))
			for index, call := range choice.Message.ToolCalls {
				toolCalls = append(toolCalls, gin.H{
					"index": index,
					"id":    call.ID,
					"type":  call.Type,
					"function": gin.H{
						"name":      call.Function.Name,
						"arguments": call.Function.Arguments,
					},
				})
			}
			delta["tool_calls"] = toolCalls
		}
		choices = append(choices, gin.H{
			"index":         choice.Index,
			"delta":         delta,
			"finish_reason": choice.FinishReason,
		})
	}
	return gin.H{
		"id":      result.ID,
		"object":  "chat.completion.chunk",
		"created": result.Created,
		"model":   result.Model,
		"choices": choices,
		"usage":   result.Usage,
	}
}

type ChatRequest struct {
	ClientAgentID       string                   `json:"client_agent_id"`
	RequestKind         string                   `json:"request_kind" binding:"required,oneof=chat group_chat proactive_care utility"`
	ProactiveClaimToken string                   `json:"proactive_claim_token,omitempty"`
	Model               string                   `json:"model" binding:"required"`
	Messages            []services.ChatMessage   `json:"messages" binding:"required"`
	MaxTokens           int                      `json:"max_tokens"`
	Temperature         float64                  `json:"temperature"`
	TopP                float64                  `json:"top_p"`
	Tools               []map[string]interface{} `json:"tools"`
	ToolChoice          interface{}              `json:"tool_choice"`
	Thinking            *struct {
		Type string `json:"type"`
	} `json:"thinking"`
	ReasoningEffort string `json:"reasoning_effort"`
}

func (h *ChatHandler) ChatCompletions(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.TP(c, "err.auth.param_error_detail", map[string]string{"detail": err.Error()}))
		return
	}

	userID := c.GetUint("user_id")
	var ownedAgent *models.UserAgent
	if req.RequestKind != "utility" {
		var ownershipErr error
		ownedAgent, ownershipErr = services.RequireOwnedAgent(userID, req.ClientAgentID)
		if ownershipErr != nil {
			utils.Forbidden(c, utils.T(c, "err.chat.agent_not_owned"))
			return
		}
	}
	var proactiveClaim *models.ProactiveCareClaim
	if req.RequestKind == "proactive_care" {
		var claimErr error
		proactiveClaim, claimErr = services.FindProactiveCareClaim(userID, req.ClientAgentID, req.ProactiveClaimToken)
		if claimErr != nil {
			utils.Forbidden(c, utils.T(c, "err.chat.proactive_claim_invalid"))
			return
		}
	}
	thinkingEnabled := req.Thinking != nil && req.Thinking.Type == "enabled"
	if errData := checkModelAllowed(userID, req.Model, thinkingEnabled); errData != nil {
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
		utils.FailWithData(c, utils.CodeBadRequest, utils.TP(c, "err.chat.model_not_allowed", map[string]string{"model": req.Model}), errData)
		return
	}

	username := ""
	if u, err := services.FindUserByID(userID); err == nil && u != nil {
		username = u.Username
	}
	reservation, err := h.billingService.Reserve(userID, req.Model, req.Messages, req.MaxTokens, thinkingEnabled)
	if err != nil {
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
		var tooLarge *services.RequestTooLargeError
		if errors.As(err, &tooLarge) {
			utils.BadRequest(c, tooLarge.Error())
			return
		}
		if billingErr, ok := err.(*services.BillingError); ok {
			c.JSON(http.StatusPaymentRequired, gin.H{"code": http.StatusPaymentRequired, "message": billingErr.Error(), "data": billingErr.ToMap()})
			return
		}
		utils.Internal(c, utils.T(c, "err.chat.reserve_failed"))
		return
	}
	var featureReservation *models.FeatureQuotaReservation
	if req.RequestKind == "chat" && ownedAgent != nil && ownedAgent.RealInfoEnabled {
		featureReservation, err = services.ReserveFeatureQuota(userID, "real_reply")
		if err != nil {
			_ = h.billingService.Release(reservation.ID)
			var quotaErr *services.FeatureQuotaExceededError
			if errors.As(err, &quotaErr) {
				c.JSON(http.StatusPaymentRequired, gin.H{"code": http.StatusPaymentRequired, "message": quotaErr.Error()})
				return
			}
			utils.Internal(c, utils.T(c, "err.chat.real_reply_reserve_failed"))
			return
		}
	}
	releaseFeature := func() {
		if featureReservation != nil {
			_ = services.ReleaseFeatureQuota(featureReservation.ReservationID)
		}
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
	}
	commitFeature := func() error {
		if featureReservation != nil {
			return services.CommitFeatureQuota(featureReservation.ReservationID)
		}
		if proactiveClaim != nil {
			return services.CommitProactiveCare(proactiveClaim.ClaimToken)
		}
		return nil
	}

	dsReq := &services.ChatCompletionRequest{
		Model:       req.Model,
		Messages:    req.Messages,
		MaxTokens:   req.MaxTokens,
		Temperature: req.Temperature,
		TopP:        req.TopP,
	}
	if len(req.Tools) > 0 {
		dsReq.Tools = req.Tools
		dsReq.ToolChoice = req.ToolChoice
	}

	if req.Thinking != nil && req.Thinking.Type == "enabled" {
		dsReq.ExtraBody = &services.ThinkingBody{
			Thinking: services.ThinkingConfig{Type: "enabled"},
		}
		if req.ReasoningEffort != "" {
			dsReq.ReasoningEffort = req.ReasoningEffort
		}
	}

	result, err := h.deepseekService.ChatCompletion(c.Request.Context(), dsReq)
	if err != nil {
		_ = h.billingService.Release(reservation.ID)
		releaseFeature()
		if writeChatUpstreamError(c, err) {
			return
		}
		utils.Internal(c, utils.T(c, "err.chat.upstream_failed"))
		return
	}

	cost, err := h.billingService.Settle(
		reservation.ID, username, req.Model,
		result.Usage.PromptTokens,
		result.Usage.PromptCacheHitTokens,
		result.Usage.PromptCacheMissTokens,
		result.Usage.CompletionTokens,
		thinkingEnabled,
	)
	if err != nil {
		// Settle 失败时必须 Release，否则 reservation 永久 pending，用户配额永久被占用
		_ = h.billingService.Release(reservation.ID)
		releaseFeature()
		utils.Internal(c, utils.T(c, "err.chat.settle_failed"))
		return
	}
	if err := commitFeature(); err != nil {
		utils.Internal(c, utils.T(c, "err.chat.real_reply_commit_failed"))
		return
	}

	utils.Success(c, gin.H{
		"id":      result.ID,
		"model":   result.Model,
		"choices": result.Choices,
		"usage":   result.Usage,
		"cost":    cost,
	})
}

func (h *ChatHandler) ChatCompletionsStream(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.TP(c, "err.auth.param_error_detail", map[string]string{"detail": err.Error()}))
		return
	}

	userID := c.GetUint("user_id")
	var ownedAgent *models.UserAgent
	if req.RequestKind != "utility" {
		var ownershipErr error
		ownedAgent, ownershipErr = services.RequireOwnedAgent(userID, req.ClientAgentID)
		if ownershipErr != nil {
			utils.Forbidden(c, utils.T(c, "err.chat.agent_not_owned"))
			return
		}
	}
	var proactiveClaim *models.ProactiveCareClaim
	if req.RequestKind == "proactive_care" {
		var claimErr error
		proactiveClaim, claimErr = services.FindProactiveCareClaim(userID, req.ClientAgentID, req.ProactiveClaimToken)
		if claimErr != nil {
			utils.Forbidden(c, utils.T(c, "err.chat.proactive_claim_invalid"))
			return
		}
	}
	thinkingEnabled := req.Thinking != nil && req.Thinking.Type == "enabled"
	if errData := checkModelAllowed(userID, req.Model, thinkingEnabled); errData != nil {
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
		utils.FailWithData(c, utils.CodeBadRequest, utils.TP(c, "err.chat.model_not_allowed", map[string]string{"model": req.Model}), errData)
		return
	}

	username := ""
	if u, err := services.FindUserByID(userID); err == nil && u != nil {
		username = u.Username
	}
	reservation, err := h.billingService.Reserve(userID, req.Model, req.Messages, req.MaxTokens, thinkingEnabled)
	if err != nil {
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
		var tooLarge *services.RequestTooLargeError
		if errors.As(err, &tooLarge) {
			utils.BadRequest(c, tooLarge.Error())
			return
		}
		if billingErr, ok := err.(*services.BillingError); ok {
			c.JSON(http.StatusPaymentRequired, gin.H{"code": http.StatusPaymentRequired, "message": billingErr.Error(), "data": billingErr.ToMap()})
			return
		}
		utils.Internal(c, utils.T(c, "err.chat.reserve_failed"))
		return
	}
	var featureReservation *models.FeatureQuotaReservation
	if req.RequestKind == "chat" && ownedAgent != nil && ownedAgent.RealInfoEnabled {
		featureReservation, err = services.ReserveFeatureQuota(userID, "real_reply")
		if err != nil {
			_ = h.billingService.Release(reservation.ID)
			var quotaErr *services.FeatureQuotaExceededError
			if errors.As(err, &quotaErr) {
				c.JSON(http.StatusPaymentRequired, gin.H{"code": http.StatusPaymentRequired, "message": quotaErr.Error()})
				return
			}
			utils.Internal(c, utils.T(c, "err.chat.real_reply_reserve_failed"))
			return
		}
	}
	releaseFeature := func() {
		if featureReservation != nil {
			_ = services.ReleaseFeatureQuota(featureReservation.ReservationID)
		}
		if proactiveClaim != nil {
			_ = services.ReleaseProactiveCare(proactiveClaim.ClaimToken)
		}
	}
	commitFeature := func() error {
		if featureReservation != nil {
			return services.CommitFeatureQuota(featureReservation.ReservationID)
		}
		if proactiveClaim != nil {
			return services.CommitProactiveCare(proactiveClaim.ClaimToken)
		}
		return nil
	}

	dsReq := &services.ChatCompletionRequest{
		Model:       req.Model,
		Messages:    req.Messages,
		MaxTokens:   req.MaxTokens,
		Temperature: req.Temperature,
		TopP:        req.TopP,
	}
	if len(req.Tools) > 0 {
		dsReq.Tools = req.Tools
		dsReq.ToolChoice = req.ToolChoice
	}

	if req.Thinking != nil && req.Thinking.Type == "enabled" {
		dsReq.ExtraBody = &services.ThinkingBody{
			Thinking: services.ThinkingConfig{Type: "enabled"},
		}
		if req.ReasoningEffort != "" {
			dsReq.ReasoningEffort = req.ReasoningEffort
		}
	}

	// 旧 /stream 路由只保留传输兼容：先用非流式上游拿到完整结果，
	// 确认结算成功后再一次性编码为 SSE，避免提前写 200 丢失真实错误状态。
	result, err := h.deepseekService.ChatCompletion(c.Request.Context(), dsReq)
	if err != nil {
		_ = h.billingService.Release(reservation.ID)
		releaseFeature()
		if writeChatUpstreamError(c, err) {
			return
		}
		utils.Internal(c, utils.T(c, "err.chat.upstream_failed"))
		return
	}
	if result == nil {
		_ = h.billingService.Release(reservation.ID)
		releaseFeature()
		utils.Internal(c, utils.T(c, "err.chat.upstream_empty"))
		return
	}

	cost, billingErr := h.billingService.Settle(
		reservation.ID, username, req.Model,
		result.Usage.PromptTokens,
		result.Usage.PromptCacheHitTokens,
		result.Usage.PromptCacheMissTokens,
		result.Usage.CompletionTokens,
		thinkingEnabled,
	)
	if billingErr != nil {
		_ = h.billingService.Release(reservation.ID)
		releaseFeature()
		utils.Internal(c, utils.T(c, "err.chat.settle_failed"))
		return
	}
	if err := commitFeature(); err != nil {
		releaseFeature()
		utils.Internal(c, utils.T(c, "err.chat.real_reply_commit_failed"))
		return
	}

	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.WriteHeader(http.StatusOK)

	chunkData, _ := json.Marshal(legacyCompletionChunk(result))
	finalData, _ := json.Marshal(gin.H{"finish_reason": "stop", "cost": cost})
	_, _ = fmt.Fprintf(c.Writer, "data: %s\n\ndata: [DONE]\n\ndata: %s\n\n", chunkData, finalData)
	c.Writer.Flush()
}

func (h *ChatHandler) GetModels(c *gin.Context) {
	prices := services.ListModelPrices()

	activePrices := []models.ModelPrice{}
	for _, p := range prices {
		if p.Status == 1 {
			activePrices = append(activePrices, p)
		}
	}

	// 仅当一张定价记录都没有（全新部署）时才回退到上游拉模型；
	// 管理员把全部模型隐藏时返回空列表，不能绕过定价体系暴露上游模型。
	if len(prices) == 0 {
		dsService := &services.DeepSeekService{}
		models, err := dsService.FetchModels()
		if err != nil {
			if be, ok := err.(*services.BillingError); ok {
				utils.FailWithData(c, utils.CodeInternal, be.Error(), be.ToMap())
			} else {
				utils.Internal(c, err.Error())
			}
			return
		}
		var mapped []gin.H
		for _, m := range models {
			mapped = append(mapped, gin.H{"id": m.ID, "name": m.ID, "owned_by": m.OwnedBy})
		}
		utils.Success(c, gin.H{"models": mapped})
		return
	}

	var result []gin.H
	for _, p := range activePrices {
		result = append(result, gin.H{
			"id":                           p.ModelID,
			"name":                         p.ModelName,
			"input_price_per_1m":           p.InputPricePer1M,
			"input_cache_hit_price_per_1m": p.InputCacheHitPricePer1M,
			"output_price_per_1m":          p.OutputPricePer1M,
			"price_per_call":               p.PricePerCall,
			"thinking_status":              p.ThinkingStatus,
			"native_vision":                p.NativeVision,
			"vision_model_id":              p.VisionModelID,
		})
	}

	utils.Success(c, gin.H{"models": result})
}

var _ = time.Now()

func checkModelAllowed(userID uint, requestModel string, thinkingEnabled bool) gin.H {
	price, err := services.FindModelPriceByModelID(requestModel)
	if err != nil || price == nil {
		return nil
	}
	if price.Status != 1 {
		return gin.H{
			"mistake":        utils.MistakeModelNotAllowed,
			"model":          requestModel,
			"allowed_models": []string{},
			"thinking":       thinkingEnabled,
		}
	}
	if thinkingEnabled && price.ThinkingStatus != 1 {
		return gin.H{
			"mistake":        utils.MistakeThinkingNotAllowed,
			"model":          requestModel,
			"allowed_models": []string{},
			"thinking":       true,
		}
	}

	return nil
}
