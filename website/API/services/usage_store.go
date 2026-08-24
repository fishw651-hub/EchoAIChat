package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// usage_store.go — UsageRecord / Agent 表数据访问薄封装，供 handlers 层使用。

// ListUsageRecordsByUser 列出用户全部用量记录（ID desc，UserID 走索引下推）。
func ListUsageRecordsByUser(userID uint) []models.UsageRecord {
	var records []models.UsageRecord
	database.Get().Register("UsageRecord").FindAll(&records, database.FilterEq("UserID", userID), "ID desc", 0, 0)
	return records
}

// SumTotalUsageCost 全部用量成本合计（SUM 下推 SQL）。
func SumTotalUsageCost() (float64, error) {
	return database.Get().Register("UsageRecord").SumWhere("Cost", nil)
}

// SumUsageCostOn 指定日期（YYYY-MM-DD 前缀）用量成本合计。
func SumUsageCostOn(date string) (float64, error) {
	return database.Get().Register("UsageRecord").SumWhere("Cost", database.FilterDate("CreatedAt", date))
}

// CountAgentsTotal 智能体总数（COUNT(*) 下推 SQL），供后台 Dashboard 使用。
func CountAgentsTotal() (int64, error) {
	return database.Get().Register("Agent").CountWhere(nil)
}
