package services

import (
	"fmt"

	"aichat-api/database"
	"aichat-api/models"
)

// activity_store.go — Activity / ActivityModelRule 表数据访问薄封装，供 handlers 层使用。

// ListActivities 列出全部活动；order 传 "" 或 "ID desc"。
func ListActivities(order string) []models.Activity {
	var activities []models.Activity
	database.Get().Register("Activity").FindAll(&activities, nil, order, 0, 0)
	return activities
}

// InsertActivity 新建活动。
func InsertActivity(activity *models.Activity) error {
	return database.Get().Register("Activity").Insert(activity)
}

// UpdateActivityByID 按主键更新活动字段。
func UpdateActivityByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("Activity").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DisableOtherActivitiesInScope 禁用同适用范围的其他已上架活动（排除 excludeID）。
// 记录字段经 fmt 文本化比较，与原 handlers 实现语义一致（内存过滤，不下推）。
func DisableOtherActivitiesInScope(applyScope string, excludeID uint) error {
	exclude := fmt.Sprintf("%v", excludeID)
	return database.Get().Register("Activity").UpdateWhere(database.FilterFunc(func(m map[string]interface{}) bool {
		return fmt.Sprintf("%v", m["ApplyScope"]) == applyScope &&
			fmt.Sprintf("%v", m["Status"]) == "1" &&
			fmt.Sprintf("%v", m["ID"]) != exclude
	}), map[string]interface{}{"Status": 0})
}

// DeleteActivityByID 按主键删除活动；返回是否实际删除。
func DeleteActivityByID(id uint) bool {
	return database.Get().Register("Activity").Delete(id)
}

// ListActivityModelRules 列出某活动的全部模型规则。
func ListActivityModelRules(activityID uint) []models.ActivityModelRule {
	var rules []models.ActivityModelRule
	database.Get().Register("ActivityModelRule").FindAll(&rules, database.FilterEq("ActivityID", activityID), "", 0, 0)
	return rules
}

// InsertActivityModelRule 新建活动模型规则。
func InsertActivityModelRule(rule *models.ActivityModelRule) error {
	return database.Get().Register("ActivityModelRule").Insert(rule)
}

// DeleteActivityModelRuleByID 按主键删除活动模型规则；返回是否实际删除。
func DeleteActivityModelRuleByID(id uint) bool {
	return database.Get().Register("ActivityModelRule").Delete(id)
}
