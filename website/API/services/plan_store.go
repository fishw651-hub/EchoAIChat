package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// plan_store.go — SubscriptionPlan / UserSubscription 表数据访问薄封装，供 handlers 层使用。

// ListSubscriptionPlans 列出全部订阅计划（SortOrder asc）。
func ListSubscriptionPlans() []models.SubscriptionPlan {
	var plans []models.SubscriptionPlan
	database.Get().Register("SubscriptionPlan").FindAll(&plans, nil, "SortOrder asc", 0, 0)
	return plans
}

// FindSubscriptionPlanByID 按主键查订阅计划；未找到返回 (nil, nil)。
func FindSubscriptionPlanByID(id uint) (*models.SubscriptionPlan, error) {
	var plan models.SubscriptionPlan
	found, err := database.Get().Register("SubscriptionPlan").FindByIDE(id, &plan)
	if err != nil || !found {
		return nil, err
	}
	return &plan, nil
}

// CountSubscriptionPlans 订阅计划总数（COUNT(*) 下推 SQL）。
func CountSubscriptionPlans() (int64, error) {
	return database.Get().Register("SubscriptionPlan").CountWhere(nil)
}

// InsertSubscriptionPlan 新建订阅计划。
func InsertSubscriptionPlan(plan *models.SubscriptionPlan) error {
	return database.Get().Register("SubscriptionPlan").Insert(plan)
}

// UpdateSubscriptionPlanByID 按主键更新订阅计划字段。
func UpdateSubscriptionPlanByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("SubscriptionPlan").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteSubscriptionPlanByID 按主键删除订阅计划；返回是否实际删除。
func DeleteSubscriptionPlanByID(id uint) bool {
	return database.Get().Register("SubscriptionPlan").Delete(id)
}

// ListUserSubscriptionsByUser 列出用户全部订阅（ID desc）。
func ListUserSubscriptionsByUser(userID uint) []models.UserSubscription {
	var subs []models.UserSubscription
	database.Get().Register("UserSubscription").FindAll(&subs, database.FilterEq("UserID", userID), "ID desc", 0, 0)
	return subs
}

// FindActiveUserSubscription 查用户对某计划的有效订阅（status=1 且未过期），
// 用于管理员续期场景；未找到返回 (nil, nil)。
func FindActiveUserSubscription(userID, planID uint, today string) (*models.UserSubscription, error) {
	var sub models.UserSubscription
	found, err := database.Get().Register("UserSubscription").FindOneE(
		database.FilterAll(
			database.FilterEq("UserID", userID),
			database.FilterEq("PlanID", planID),
			database.FilterEq("Status", 1),
			database.FilterGte("ExpiresAt", today),
		),
		&sub,
	)
	if err != nil || !found {
		return nil, err
	}
	return &sub, nil
}

// InsertUserSubscription 新建用户订阅。
func InsertUserSubscription(sub *models.UserSubscription) error {
	return database.Get().Register("UserSubscription").Insert(sub)
}

// UpdateUserSubscriptionByID 按主键更新用户订阅字段。
func UpdateUserSubscriptionByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("UserSubscription").UpdateWhere(database.FilterEq("ID", id), updates)
}

// IncrementUserSubscriptionField 原子增减用户订阅数值字段（如 OcrUsedToday）。
func IncrementUserSubscriptionField(id uint, field string, delta float64) error {
	return database.Get().Register("UserSubscription").IncrementField(database.FilterEq("ID", id), field, delta)
}
