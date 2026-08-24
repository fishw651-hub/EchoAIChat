package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// api_key_store.go — APIKey 表数据访问薄封装，供 handlers 层使用。

// ListAPIKeys 列出全部 API Key 记录。
func ListAPIKeys() []models.APIKey {
	var keys []models.APIKey
	database.Get().Register("APIKey").FindAll(&keys, nil, "", 0, 0)
	return keys
}

// FindAPIKeyByProvider 按 provider 查 API Key；未找到返回 (nil, nil)。
func FindAPIKeyByProvider(provider string) (*models.APIKey, error) {
	var key models.APIKey
	found, err := database.Get().Register("APIKey").FindOneE(database.FilterEq("Provider", provider), &key)
	if err != nil || !found {
		return nil, err
	}
	return &key, nil
}

// InsertAPIKey 新建 API Key 记录。
func InsertAPIKey(key *models.APIKey) error {
	return database.Get().Register("APIKey").Insert(key)
}

// UpdateAPIKeyByID 按主键更新 API Key 字段。
func UpdateAPIKeyByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("APIKey").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteAPIKeyByID 按主键删除 API Key；返回是否实际删除。
func DeleteAPIKeyByID(id uint) bool {
	return database.Get().Register("APIKey").Delete(id)
}
