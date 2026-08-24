package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// config_store.go — SystemConfig 表数据访问薄封装，供 handlers 层使用。

// FindSystemConfig 按 Key 查配置；未找到返回 (nil, nil)。
func FindSystemConfig(key string) (*models.SystemConfig, error) {
	var sc models.SystemConfig
	found, err := database.Get().Register("SystemConfig").FindOneE(database.FilterEq("Key", key), &sc)
	if err != nil || !found {
		return nil, err
	}
	return &sc, nil
}

// ListSystemConfigs 列出全部系统配置。
func ListSystemConfigs() []models.SystemConfig {
	var configs []models.SystemConfig
	database.Get().Register("SystemConfig").FindAll(&configs, nil, "", 0, 0)
	return configs
}

// SaveSystemConfig upsert 一条配置：Key 已存在则更新 Value，否则插入新记录。
func SaveSystemConfig(key, value, desc string) error {
	tbl := database.Get().Register("SystemConfig")
	var existing models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", key), &existing) {
		return tbl.UpdateWhere(database.FilterEq("Key", key), map[string]interface{}{"Value": value})
	}
	return tbl.Insert(&models.SystemConfig{Key: key, Value: value, Description: desc})
}
