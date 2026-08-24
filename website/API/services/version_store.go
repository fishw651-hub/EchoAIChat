package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// version_store.go — AppVersion 表数据访问薄封装，供 handlers 层使用。

// ListAppVersions 列出全部应用版本；order 传 "VersionCode desc" 或 "ID desc"。
func ListAppVersions(order string) []models.AppVersion {
	var versions []models.AppVersion
	database.Get().Register("AppVersion").FindAll(&versions, nil, order, 0, 0)
	return versions
}

// FindAppVersionByID 按主键查应用版本；未找到返回 (nil, nil)。
func FindAppVersionByID(id uint) (*models.AppVersion, error) {
	var v models.AppVersion
	found, err := database.Get().Register("AppVersion").FindByIDE(id, &v)
	if err != nil || !found {
		return nil, err
	}
	return &v, nil
}

// InsertAppVersion 新建应用版本。
func InsertAppVersion(v *models.AppVersion) error {
	return database.Get().Register("AppVersion").Insert(v)
}

// UpdateAppVersionByID 按主键更新应用版本字段。
func UpdateAppVersionByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("AppVersion").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteAppVersionByID 按主键删除应用版本；返回是否实际删除。
func DeleteAppVersionByID(id uint) bool {
	return database.Get().Register("AppVersion").Delete(id)
}
