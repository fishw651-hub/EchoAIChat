package handlers

import (
	"fmt"
	"strconv"
	"strings"

	"aichat-api/config"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type ConfigHandler struct{}

func (h *ConfigHandler) GetTLSConfig(c *gin.Context) {
	cfg := config.GetTLSConfig()
	utils.Success(c, gin.H{
		"enabled": cfg.Enabled, "port": cfg.Port, "auto_acme": cfg.AutoACME,
		"acme_email": cfg.ACMEEmail, "acme_domains": cfg.ACMEDomains,
		"cache_dir": cfg.CacheDir, "cert_file": cfg.CertFile, "key_file": cfg.KeyFile,
		"restart_required": true,
	})
}

func (h *ConfigHandler) UpdateTLSConfig(c *gin.Context) {
	var req config.TLSConfig
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "TLS 配置参数错误")
		return
	}
	if err := config.SaveTLSConfig(req); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	utils.SuccessMsg(c, "TLS 配置已保存，重启服务后生效")
}

func (h *ConfigHandler) GetTimeOfUsePricing(c *gin.Context) {
	pricing, err := services.LoadTimeOfUsePricing()
	if err != nil {
		utils.Internal(c, "读取峰谷价格配置失败: "+err.Error())
		return
	}
	utils.Success(c, pricing)
}

func (h *ConfigHandler) UpdateTimeOfUsePricing(c *gin.Context) {
	var pricing services.TimeOfUsePricing
	if err := c.ShouldBindJSON(&pricing); err != nil {
		utils.BadRequest(c, "峰谷价格参数错误")
		return
	}
	if err := services.SaveTimeOfUsePricing(pricing); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	utils.SuccessMsg(c, "峰谷价格配置已更新")
}

func (h *ConfigHandler) ListAPIKeys(c *gin.Context) {
	keys := services.ListAPIKeys()

	var result []gin.H
	for _, k := range keys {
		masked := k.Name + "****"
		if len(k.Name) > 4 {
			masked = k.Name[:4] + "****"
		}
		result = append(result, gin.H{
			"id":         k.ID,
			"provider":   k.Provider,
			"name":       k.Name,
			"masked_key": masked,
			"base_url":   k.BaseURL,
			"api_format": normalizeAPIFormat(k.ApiFormat),
			"is_active":  k.IsActive,
		})
	}

	utils.Success(c, result)
}

// normalizeAPIFormat 空值回退 openai，供列表输出与入参默认值共用。
func normalizeAPIFormat(format string) string {
	format = strings.TrimSpace(format)
	if format == "" {
		return services.ApiFormatOpenAI
	}
	return format
}

// validateAPIFormat 校验 api_format 白名单（openai/gemini，空默认 openai）。
func validateAPIFormat(format string) (string, bool) {
	format = normalizeAPIFormat(format)
	switch format {
	case services.ApiFormatOpenAI, services.ApiFormatGemini:
		return format, true
	}
	return "", false
}

func (h *ConfigHandler) CreateAPIKey(c *gin.Context) {
	var req struct {
		Provider  string `json:"provider" binding:"required"`
		Name      string `json:"name" binding:"required"`
		APIKey    string `json:"api_key" binding:"required"`
		BaseURL   string `json:"base_url"`
		ApiFormat string `json:"api_format"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	format, ok := validateAPIFormat(req.ApiFormat)
	if !ok {
		utils.BadRequest(c, "api_format 仅支持 openai / gemini")
		return
	}

	encKey := config.AppConfig.Encryption.Key
	if len(encKey) < 32 {
		encKey = encKey + "00000000000000000000000000000000"
	}
	encrypted, err := services.Encrypt(req.APIKey, []byte(encKey[:32]))
	if err != nil {
		utils.Internal(c, "API Key加密失败")
		return
	}

	apiKey := models.APIKey{
		Provider:        req.Provider,
		Name:            req.Name,
		APIKeyEncrypted: encrypted,
		BaseURL:         strings.TrimSpace(req.BaseURL),
		ApiFormat:       format,
		IsActive:        true,
	}

	if err := services.InsertAPIKey(&apiKey); err != nil {
		utils.Internal(c, "创建失败")
		return
	}

	utils.Success(c, gin.H{"id": apiKey.ID, "masked_key": apiKey.Name + "****"})
}

func (h *ConfigHandler) UpdateAPIKey(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		Name      string  `json:"name"`
		APIKey    string  `json:"api_key"`
		BaseURL   *string `json:"base_url"`
		ApiFormat *string `json:"api_format"`
		IsActive  *bool   `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != "" {
		updates["Name"] = req.Name
	}
	if req.BaseURL != nil {
		updates["BaseURL"] = strings.TrimSpace(*req.BaseURL)
	}
	if req.ApiFormat != nil {
		format, ok := validateAPIFormat(*req.ApiFormat)
		if !ok {
			utils.BadRequest(c, "api_format 仅支持 openai / gemini")
			return
		}
		updates["ApiFormat"] = format
	}
	if req.APIKey != "" {
		encKey := config.AppConfig.Encryption.Key
		if len(encKey) < 32 {
			encKey = encKey + "00000000000000000000000000000000"
		}
		encrypted, err := services.Encrypt(req.APIKey, []byte(encKey[:32]))
		if err != nil {
			utils.Internal(c, "API Key加密失败")
			return
		}
		updates["APIKeyEncrypted"] = encrypted
	}
	if req.IsActive != nil {
		updates["IsActive"] = *req.IsActive
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "没有需要更新的字段")
		return
	}

	services.UpdateAPIKeyByID(uint(id), updates)
	utils.SuccessMsg(c, "更新成功")
}

func (h *ConfigHandler) DeleteAPIKey(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	services.DeleteAPIKeyByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}

func (h *ConfigHandler) ListModelPrices(c *gin.Context) {
	prices := services.ListModelPrices()

	// 按 provider 索引站点信息（每个 provider 取第一条 APIKey 记录），
	// 补充 base_url/api_format/has_key 供编辑弹窗展示，绝不返回 key 原文。
	keys := services.ListAPIKeys()
	siteByProvider := map[string]models.APIKey{}
	for _, k := range keys {
		if _, ok := siteByProvider[k.Provider]; !ok {
			siteByProvider[k.Provider] = k
		}
	}

	result := make([]gin.H, 0, len(prices))
	for _, p := range prices {
		provider := strings.TrimSpace(p.Provider)
		if provider == "" {
			provider = "deepseek"
		}
		entry := gin.H{
			"id":                              p.ID,
			"model_id":                        p.ModelID,
			"model_name":                      p.ModelName,
			"provider":                        p.Provider,
			"input_price_per_1m":              p.InputPricePer1M,
			"input_cache_hit_price_per_1m":    p.InputCacheHitPricePer1M,
			"output_price_per_1m":             p.OutputPricePer1M,
			"thinking_input_price_per_1m":     p.ThinkingInputPricePer1M,
			"thinking_cache_hit_price_per_1m": p.ThinkingInputCacheHitPricePer1M,
			"thinking_output_price_per_1m":    p.ThinkingOutputPricePer1M,
			"price_per_call":                  p.PricePerCall,
			"status":                          p.Status,
			"thinking_status":                 p.ThinkingStatus,
			"native_vision":                   p.NativeVision,
			"vision_model_id":                 p.VisionModelID,
			"base_url":                        "",
			"api_format":                      "",
			"has_key":                         false,
		}
		if k, ok := siteByProvider[provider]; ok {
			entry["base_url"] = k.BaseURL
			entry["api_format"] = normalizeAPIFormat(k.ApiFormat)
			entry["has_key"] = k.APIKeyEncrypted != ""
		}
		result = append(result, entry)
	}
	utils.Success(c, result)
}

func (h *ConfigHandler) UpdateModelPrice(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		InputPricePer1M            float64 `json:"input_price_per_1m"`
		InputCacheHitPricePer1M    float64 `json:"input_cache_hit_price_per_1m"`
		OutputPricePer1M           float64 `json:"output_price_per_1m"`
		ThinkingInputPricePer1M    float64 `json:"thinking_input_price_per_1m"`
		ThinkingCacheHitPricePer1M float64 `json:"thinking_cache_hit_price_per_1m"`
		ThinkingOutputPricePer1M   float64 `json:"thinking_output_price_per_1m"`
		PricePerCall               float64 `json:"price_per_call"`
		Status                     *int    `json:"status"`
		ThinkingStatus             *int    `json:"thinking_status"`
		NativeVision               *bool   `json:"native_vision"`
		VisionModelID              *string `json:"vision_model_id"`
		// 可选：同步修改该模型 provider 站点的连接配置（key 留空不覆盖）。
		BaseURL   *string `json:"base_url"`
		ApiFormat *string `json:"api_format"`
		APIKey    string  `json:"api_key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{
		"InputPricePer1M":            req.InputPricePer1M,
		"InputCacheHitPricePer1M":    req.InputCacheHitPricePer1M,
		"OutputPricePer1M":           req.OutputPricePer1M,
		"ThinkingInputPricePer1M":    req.ThinkingInputPricePer1M,
		"ThinkingCacheHitPricePer1M": req.ThinkingCacheHitPricePer1M,
		"ThinkingOutputPricePer1M":   req.ThinkingOutputPricePer1M,
		"PricePerCall":               req.PricePerCall,
	}
	if req.Status != nil {
		updates["Status"] = *req.Status
	}
	if req.ThinkingStatus != nil {
		updates["ThinkingStatus"] = *req.ThinkingStatus
	}
	if req.NativeVision != nil {
		updates["NativeVision"] = *req.NativeVision
		// 原生视觉开启时自动清空绑定，保持字段语义单一。
		if *req.NativeVision {
			updates["VisionModelID"] = ""
		}
	}
	if req.VisionModelID != nil {
		updates["VisionModelID"] = strings.TrimSpace(*req.VisionModelID)
	}

	// 携带站点字段时，同步 upsert 该模型 provider 的 APIKey 记录。
	if req.BaseURL != nil || req.ApiFormat != nil || req.APIKey != "" {
		price, err := services.FindModelPriceByID(uint(id))
		if err != nil || price == nil {
			utils.NotFound(c, "模型定价不存在")
			return
		}
		baseURL := ""
		if req.BaseURL != nil {
			baseURL = *req.BaseURL
		}
		format := ""
		if req.ApiFormat != nil {
			format = *req.ApiFormat
		}
		if err := upsertProviderAPIKey(price.Provider, baseURL, format, req.APIKey); err != nil {
			utils.BadRequest(c, err.Error())
			return
		}
	}

	services.UpdateModelPriceByID(uint(id), updates)
	utils.SuccessMsg(c, "价格更新成功")
}

// UpdateModelPriceStatus 仅切换模型上线/隐藏状态，不动价格等其他字段。
// 隐藏后客户端 /models 列表不再返回该模型，checkModelAllowed 同步拦截其聊天请求。
func (h *ConfigHandler) UpdateModelPriceStatus(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		Status *int `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Status == nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if *req.Status != 0 && *req.Status != 1 {
		utils.BadRequest(c, "status 仅支持 0（隐藏）/ 1（上线）")
		return
	}

	price, err := services.FindModelPriceByID(uint(id))
	if err != nil || price == nil {
		utils.NotFound(c, "模型定价不存在")
		return
	}
	services.UpdateModelPriceByID(uint(id), map[string]interface{}{"Status": *req.Status})
	if *req.Status == 1 {
		utils.SuccessMsg(c, "模型已恢复上线")
	} else {
		utils.SuccessMsg(c, "模型已隐藏")
	}
}

// FetchRemoteModels 代理拉取远程站点的模型列表（OpenAI /models 格式）。
func (h *ConfigHandler) FetchRemoteModels(c *gin.Context) {
	var req struct {
		BaseURL   string `json:"base_url"`
		APIKey    string `json:"api_key"`
		ApiFormat string `json:"api_format"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if _, err := services.ValidateRemoteBaseURL(req.BaseURL); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	ids, err := services.FetchRemoteModels(req.BaseURL, req.APIKey)
	if err != nil {
		utils.Fail(c, utils.CodeBadGateway, "拉取模型失败: "+err.Error())
		return
	}
	utils.Success(c, gin.H{"models": ids})
}

// upsertProviderAPIKey 保存模型时同步维护 provider 站点的 APIKey 记录：
// 已存在 → 更新 base_url/api_format（api_key 非空才覆盖）；不存在 → 需提供 api_key 新建。
func upsertProviderAPIKey(provider, baseURL, apiFormat, apiKey string) error {
	provider = strings.TrimSpace(provider)
	if provider == "" {
		provider = "deepseek"
	}
	baseURL = strings.TrimSpace(baseURL)
	apiKey = strings.TrimSpace(apiKey)

	keys := services.ListAPIKeys()
	var existing *models.APIKey
	for i := range keys {
		if keys[i].Provider == provider {
			existing = &keys[i]
			break
		}
	}

	format := strings.TrimSpace(apiFormat)
	if format == "" && existing != nil {
		format = existing.ApiFormat // 未显式指定时保留站点已有格式
	}
	normalized, ok := validateAPIFormat(format)
	if !ok {
		return fmt.Errorf("api_format 仅支持 openai / gemini")
	}

	if existing != nil {
		updates := map[string]interface{}{
			"BaseURL":   baseURL,
			"ApiFormat": normalized,
		}
		if apiKey != "" {
			encrypted, err := services.Encrypt(apiKey, services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key))
			if err != nil {
				return fmt.Errorf("API Key加密失败")
			}
			updates["APIKeyEncrypted"] = encrypted
		}
		return services.UpdateAPIKeyByID(existing.ID, updates)
	}

	if apiKey == "" {
		return fmt.Errorf("站点 %s 还没有 API Key，请填写", provider)
	}
	encrypted, err := services.Encrypt(apiKey, services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key))
	if err != nil {
		return fmt.Errorf("API Key加密失败")
	}
	return services.InsertAPIKey(&models.APIKey{
		Provider:        provider,
		Name:            provider,
		APIKeyEncrypted: encrypted,
		BaseURL:         baseURL,
		ApiFormat:       normalized,
		IsActive:        true,
	})
}

func (h *ConfigHandler) SyncModels(c *gin.Context) {
	dsService := &services.DeepSeekService{}
	if err := dsService.SyncModelPrices(); err != nil {
		utils.Internal(c, "同步失败: "+err.Error())
		return
	}
	utils.SuccessMsg(c, "模型同步成功")
}

func (h *ConfigHandler) CreateModelPrice(c *gin.Context) {
	var req struct {
		ModelID                    string  `json:"model_id" binding:"required"`
		ModelName                  string  `json:"model_name"`
		Provider                   string  `json:"provider"`
		InputPricePer1M            float64 `json:"input_price_per_1m"`
		InputCacheHitPricePer1M    float64 `json:"input_cache_hit_price_per_1m"`
		OutputPricePer1M           float64 `json:"output_price_per_1m"`
		ThinkingInputPricePer1M    float64 `json:"thinking_input_price_per_1m"`
		ThinkingCacheHitPricePer1M float64 `json:"thinking_cache_hit_price_per_1m"`
		ThinkingOutputPricePer1M   float64 `json:"thinking_output_price_per_1m"`
		PricePerCall               float64 `json:"price_per_call"`
		Status                     int     `json:"status"`
		ThinkingStatus             int     `json:"thinking_status"`
		NativeVision               bool    `json:"native_vision"`
		VisionModelID              string  `json:"vision_model_id"`
		// 可选：同时维护 provider 站点的连接配置（站点 upsert）。
		BaseURL   string `json:"base_url"`
		ApiFormat string `json:"api_format"`
		APIKey    string `json:"api_key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误：模型 ID 不能为空")
		return
	}

	prices := []float64{
		req.InputPricePer1M, req.InputCacheHitPricePer1M, req.OutputPricePer1M,
		req.ThinkingInputPricePer1M, req.ThinkingCacheHitPricePer1M, req.ThinkingOutputPricePer1M,
		req.PricePerCall,
	}
	for _, p := range prices {
		if p < 0 {
			utils.BadRequest(c, "价格不能为负数")
			return
		}
	}

	modelID := strings.TrimSpace(req.ModelID)
	existing, err := services.FindModelPriceByModelID(modelID)
	if err == nil && existing != nil {
		utils.Fail(c, utils.CodeConflict, "模型 "+modelID+" 已存在")
		return
	}

	// 先完成站点 upsert（全部校验通过后才动数据），再创建模型定价。
	if req.BaseURL != "" || req.ApiFormat != "" || req.APIKey != "" {
		if err := upsertProviderAPIKey(req.Provider, req.BaseURL, req.ApiFormat, req.APIKey); err != nil {
			utils.BadRequest(c, err.Error())
			return
		}
	}

	modelName := strings.TrimSpace(req.ModelName)
	if modelName == "" {
		modelName = modelID
	}
	price := models.ModelPrice{
		ModelID:                         modelID,
		ModelName:                       modelName,
		Provider:                        strings.TrimSpace(req.Provider),
		InputPricePer1M:                 req.InputPricePer1M,
		InputCacheHitPricePer1M:         req.InputCacheHitPricePer1M,
		OutputPricePer1M:                req.OutputPricePer1M,
		ThinkingInputPricePer1M:         req.ThinkingInputPricePer1M,
		ThinkingInputCacheHitPricePer1M: req.ThinkingCacheHitPricePer1M,
		ThinkingOutputPricePer1M:        req.ThinkingOutputPricePer1M,
		PricePerCall:                    req.PricePerCall,
		Status:                          req.Status,
		ThinkingStatus:                  req.ThinkingStatus,
		NativeVision:                    req.NativeVision,
	}
	// 非原生视觉模型才保留绑定（勾选原生视觉时忽略传入的绑定值）。
	if !req.NativeVision {
		price.VisionModelID = strings.TrimSpace(req.VisionModelID)
	}
	if err := services.InsertModelPrice(&price); err != nil {
		utils.Internal(c, "创建失败")
		return
	}
	utils.Success(c, gin.H{"id": price.ID, "model_id": price.ModelID})
}

func (h *ConfigHandler) DeleteModelPrice(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	existing, err := services.FindModelPriceByID(uint(id))
	if err != nil || existing == nil {
		utils.NotFound(c, "模型定价不存在")
		return
	}
	services.DeleteModelPriceByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}
