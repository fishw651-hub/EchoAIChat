package services

import (
	"encoding/json"
	"fmt"
	"math"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

const timeOfUsePricingKey = "time_of_use_pricing"

type TimeOfUsePricing struct {
	ValleyStart      string  `json:"valley_start"`
	ValleyEnd        string  `json:"valley_end"`
	PeakMultiplier   float64 `json:"peak_multiplier"`
	ValleyMultiplier float64 `json:"valley_multiplier"`
}

func DefaultTimeOfUsePricing() TimeOfUsePricing {
	return TimeOfUsePricing{
		ValleyStart:      "00:00",
		ValleyEnd:        "08:00",
		PeakMultiplier:   1,
		ValleyMultiplier: 1,
	}
}

func (p TimeOfUsePricing) Validate() error {
	start, err := parseTimeOfDay(p.ValleyStart)
	if err != nil {
		return fmt.Errorf("谷开始时间无效: %w", err)
	}
	end, err := parseTimeOfDay(p.ValleyEnd)
	if err != nil {
		return fmt.Errorf("谷结束时间无效: %w", err)
	}
	if start == end {
		return fmt.Errorf("谷开始和结束时间不能相同")
	}
	if !isPositiveFinite(p.PeakMultiplier) || !isPositiveFinite(p.ValleyMultiplier) {
		return fmt.Errorf("峰谷倍率必须为大于零的有限数")
	}
	return nil
}

func (p TimeOfUsePricing) MultiplierAt(at time.Time) (string, float64, error) {
	if err := p.Validate(); err != nil {
		return "", 0, err
	}
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return "", 0, err
	}
	local := at.In(location)
	minute := local.Hour()*60 + local.Minute()
	start, _ := parseTimeOfDay(p.ValleyStart)
	end, _ := parseTimeOfDay(p.ValleyEnd)

	inValley := start < end
	if inValley {
		inValley = minute >= start && minute < end
	} else {
		inValley = minute >= start || minute < end
	}
	if inValley {
		return "valley", p.ValleyMultiplier, nil
	}
	return "peak", p.PeakMultiplier, nil
}

func LoadTimeOfUsePricing() (TimeOfUsePricing, error) {
	var config models.SystemConfig
	if !database.Get().Register("SystemConfig").FindOne(database.FilterEq("Key", timeOfUsePricingKey), &config) {
		return DefaultTimeOfUsePricing(), nil
	}

	var pricing TimeOfUsePricing
	if err := json.Unmarshal([]byte(config.Value), &pricing); err != nil {
		return DefaultTimeOfUsePricing(), fmt.Errorf("解析峰谷配置失败: %w", err)
	}
	if err := pricing.Validate(); err != nil {
		return DefaultTimeOfUsePricing(), err
	}
	return pricing, nil
}

func SaveTimeOfUsePricing(pricing TimeOfUsePricing) error {
	if err := pricing.Validate(); err != nil {
		return err
	}
	value, err := json.Marshal(pricing)
	if err != nil {
		return err
	}
	table := database.Get().Register("SystemConfig")
	var existing models.SystemConfig
	if table.FindOne(database.FilterEq("Key", timeOfUsePricingKey), &existing) {
		return table.UpdateWhere(database.FilterEq("ID", existing.ID), map[string]interface{}{
			"Value": string(value),
		})
	}
	return table.Insert(&models.SystemConfig{
		Key:         timeOfUsePricingKey,
		Value:       string(value),
		Description: "按上海时区计算的聊天峰谷价格倍率",
	})
}

func parseTimeOfDay(value string) (int, error) {
	parsed, err := time.Parse("15:04", value)
	if err != nil || parsed.Format("15:04") != value {
		return 0, fmt.Errorf("应为 HH:mm")
	}
	return parsed.Hour()*60 + parsed.Minute(), nil
}

func isPositiveFinite(value float64) bool {
	return value > 0 && !math.IsNaN(value) && !math.IsInf(value, 0)
}
