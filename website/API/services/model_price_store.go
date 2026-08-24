package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// model_price_store.go — ModelPrice 表数据访问薄封装，供 handlers 层使用。

// ListModelPrices 列出全部模型定价。
func ListModelPrices() []models.ModelPrice {
	var prices []models.ModelPrice
	database.Get().Register("ModelPrice").FindAll(&prices, nil, "", 0, 0)
	return prices
}

// FindModelPriceByID 按主键查模型定价；未找到返回 (nil, nil)。
func FindModelPriceByID(id uint) (*models.ModelPrice, error) {
	var price models.ModelPrice
	found, err := database.Get().Register("ModelPrice").FindByIDE(id, &price)
	if err != nil || !found {
		return nil, err
	}
	return &price, nil
}

// FindModelPriceByModelID 按 model_id 查模型定价；未找到返回 (nil, nil)。
func FindModelPriceByModelID(modelID string) (*models.ModelPrice, error) {
	var price models.ModelPrice
	found, err := database.Get().Register("ModelPrice").FindOneE(database.FilterEq("ModelID", modelID), &price)
	if err != nil || !found {
		return nil, err
	}
	return &price, nil
}

// InsertModelPrice 新建模型定价。
func InsertModelPrice(price *models.ModelPrice) error {
	return database.Get().Register("ModelPrice").Insert(price)
}

// UpdateModelPriceByID 按主键更新模型定价字段。
func UpdateModelPriceByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("ModelPrice").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteModelPriceByID 按主键删除模型定价；返回是否实际删除。
func DeleteModelPriceByID(id uint) bool {
	return database.Get().Register("ModelPrice").Delete(id)
}
