package models

import (
	"time"
)

type ModelPrice struct {
	ID                              uint    `json:"id"`
	ModelID                         string  `json:"model_id"`
	ModelName                       string  `json:"model_name"`
	InputPricePer1M                 float64 `json:"input_price_per_1m"`
	InputCacheHitPricePer1M         float64 `json:"input_cache_hit_price_per_1m"`
	OutputPricePer1M                float64 `json:"output_price_per_1m"`
	ThinkingInputPricePer1M         float64 `json:"thinking_input_price_per_1m"`
	ThinkingInputCacheHitPricePer1M float64 `json:"thinking_input_cache_hit_price_per_1m"`
	ThinkingOutputPricePer1M        float64 `json:"thinking_output_price_per_1m"`
	// ProOnly 保留仅用于兼容旧 JSON 记录，不再暴露、编辑或参与权限判断。
	ProOnly bool `json:"-"`
	// PricePerCall 按次计费价格（元/次）。>0 时每次调用固定扣费、不再按
	// token 计价，活动折扣与思考模式倍率不适用；分时定价倍率仍然生效。
	PricePerCall float64 `json:"price_per_call"`
	// Provider 空值默认 "deepseek"，用于按模型路由到不同上游站点。
	Provider string `json:"provider"`
	// NativeVision 表示模型本身支持视觉（图片输入）。
	NativeVision bool `json:"native_vision"`
	// VisionModelID 是非原生视觉模型绑定的视觉模型 ID，空值表示未绑定。
	VisionModelID  string    `json:"vision_model_id"`
	Status         int       `json:"status"`
	ThinkingStatus int       `json:"thinking_status"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}
