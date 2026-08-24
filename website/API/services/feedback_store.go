package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// feedback_store.go — Feedback 表数据访问薄封装，供 handlers 层使用。

// ListFeedback 列出全部反馈（ID desc）。
func ListFeedback() []models.Feedback {
	var all []models.Feedback
	database.Get().Register("Feedback").FindAll(&all, nil, "ID desc", 0, 0)
	return all
}

// InsertFeedback 新建反馈。
func InsertFeedback(feedback *models.Feedback) error {
	return database.Get().Register("Feedback").Insert(feedback)
}

// UpdateFeedbackByID 按主键更新反馈字段。
func UpdateFeedbackByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("Feedback").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteFeedbackByID 按主键删除反馈；bool 表示是否实际删除（不存在返回 false）。
// 底层 Delete 不暴露错误细节，仅回传其删除结果。
func DeleteFeedbackByID(id uint) (bool, error) {
	return database.Get().Register("Feedback").Delete(id), nil
}
