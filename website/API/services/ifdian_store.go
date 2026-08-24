package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// ifdian_store.go — IfdianPlan / IfdianRecord 表数据访问薄封装，供 handlers 层使用。

// ListIfdianPlans 列出全部爱发电方案。
func ListIfdianPlans() []models.IfdianPlan {
	var plans []models.IfdianPlan
	database.Get().Register("IfdianPlan").FindAll(&plans, nil, "", 0, 0)
	return plans
}

// FindIfdianPlanByPlanID 按爱发电侧方案 ID 查方案；未找到返回 (nil, nil)。
func FindIfdianPlanByPlanID(ifdianPlanID string) (*models.IfdianPlan, error) {
	var plan models.IfdianPlan
	found, err := database.Get().Register("IfdianPlan").FindOneE(database.FilterEq("IfdianPlanID", ifdianPlanID), &plan)
	if err != nil || !found {
		return nil, err
	}
	return &plan, nil
}

// UpdateIfdianPlanByID 按主键更新爱发电方案字段。
func UpdateIfdianPlanByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("IfdianPlan").UpdateWhere(database.FilterEq("ID", id), updates)
}

// ListIfdianRecords 列出全部爱发电订单记录（ID desc）。
func ListIfdianRecords() []models.IfdianRecord {
	var records []models.IfdianRecord
	database.Get().Register("IfdianRecord").FindAll(&records, nil, "ID desc", 0, 0)
	return records
}

// FindIfdianRecordByOutTradeNo 按外部交易号查爱发电记录；未找到返回 (nil, nil)。
func FindIfdianRecordByOutTradeNo(outTradeNo string) (*models.IfdianRecord, error) {
	var record models.IfdianRecord
	found, err := database.Get().Register("IfdianRecord").FindOneE(database.FilterEq("OutTradeNo", outTradeNo), &record)
	if err != nil || !found {
		return nil, err
	}
	return &record, nil
}

// InsertIfdianRecord 新建爱发电订单记录。
func InsertIfdianRecord(record *models.IfdianRecord) error {
	return database.Get().Register("IfdianRecord").Insert(record)
}
