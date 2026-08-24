package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// user_store.go — User 表数据访问薄封装，供 handlers 层使用。
// 约定：单条查询找不到返回 (nil, nil)，出错返回 (nil, err)，不再把错误吞成 bool。

// FindUserByID 按主键查用户；未找到返回 (nil, nil)。
func FindUserByID(id uint) (*models.User, error) {
	var user models.User
	found, err := database.Get().Register("User").FindByIDE(id, &user)
	if err != nil || !found {
		return nil, err
	}
	return &user, nil
}

// FindUserByUsername 按用户名查用户；未找到返回 (nil, nil)。
func FindUserByUsername(username string) (*models.User, error) {
	var user models.User
	found, err := database.Get().Register("User").FindOneE(database.FilterEq("Username", username), &user)
	if err != nil || !found {
		return nil, err
	}
	return &user, nil
}

// FindUserByEmail 按邮箱查用户；未找到返回 (nil, nil)。
func FindUserByEmail(email string) (*models.User, error) {
	var user models.User
	found, err := database.Get().Register("User").FindOneE(database.FilterEq("Email", email), &user)
	if err != nil || !found {
		return nil, err
	}
	return &user, nil
}

// ListUsers 列出全部用户；order 传 "" 或 "ID desc"。
func ListUsers(order string) []models.User {
	var users []models.User
	database.Get().Register("User").FindAll(&users, nil, order, 0, 0)
	return users
}

// InsertUser 新建用户。
func InsertUser(user *models.User) error {
	return database.Get().Register("User").Insert(user)
}

// UpdateUserByID 按主键更新用户字段。
func UpdateUserByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("User").UpdateWhere(database.FilterEq("ID", id), updates)
}

// IncrementUserField 原子增减用户数值字段（如 OcrUsedToday）。
func IncrementUserField(id uint, field string, delta float64) error {
	return database.Get().Register("User").IncrementField(database.FilterEq("ID", id), field, delta)
}

// DeleteUserByID 按主键删除用户；返回是否实际删除。
func DeleteUserByID(id uint) bool {
	return database.Get().Register("User").Delete(id)
}

// CountUsers 用户总数（COUNT(*) 下推 SQL）。
func CountUsers() (int64, error) {
	return database.Get().Register("User").CountWhere(nil)
}

// CountUsersCreatedOn 指定日期（YYYY-MM-DD 前缀）新增用户数。
func CountUsersCreatedOn(date string) (int64, error) {
	return database.Get().Register("User").CountWhere(database.FilterDate("CreatedAt", date))
}
