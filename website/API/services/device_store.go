package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// device_store.go — Device / SyncSetting 表数据访问薄封装，供 handlers 层使用。

// FindDevice 按用户 + 客户端设备 ID 查设备；未找到返回 (nil, nil)。
func FindDevice(userID uint, deviceID string) (*models.Device, error) {
	var device models.Device
	found, err := database.Get().Register("Device").FindOneE(database.FilterAll(
		database.FilterEq("UserID", userID),
		database.FilterEq("DeviceID", deviceID),
	), &device)
	if err != nil || !found {
		return nil, err
	}
	return &device, nil
}

// ListDevicesByUser 列出用户全部设备。
func ListDevicesByUser(userID uint) []models.Device {
	var devices []models.Device
	database.Get().Register("Device").FindAll(&devices, database.FilterEq("UserID", userID), "", 0, 0)
	return devices
}

// ListDevicesByUserAndRole 列出用户指定角色（master/slave）的设备。
func ListDevicesByUserAndRole(userID uint, role string) []models.Device {
	var devices []models.Device
	database.Get().Register("Device").FindAll(&devices, database.FilterAll(
		database.FilterEq("UserID", userID),
		database.FilterEq("Role", role),
	), "", 0, 0)
	return devices
}

// CountDevicesByUser 用户设备总数。
func CountDevicesByUser(userID uint) (int64, error) {
	return database.Get().Register("Device").CountWhere(database.FilterEq("UserID", userID))
}

// CountDevicesByUserAndRole 用户指定角色设备数。
func CountDevicesByUserAndRole(userID uint, role string) (int64, error) {
	return database.Get().Register("Device").CountWhere(database.FilterAll(
		database.FilterEq("UserID", userID),
		database.FilterEq("Role", role),
	))
}

// InsertDevice 注册新设备。
func InsertDevice(device *models.Device) error {
	return database.Get().Register("Device").Insert(device)
}

// UpdateDeviceByID 按主键更新设备字段。
func UpdateDeviceByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("Device").UpdateWhere(database.FilterEq("ID", id), updates)
}

// UpdateDeviceByUserAndDeviceID 按用户 + 客户端设备 ID 更新设备字段。
func UpdateDeviceByUserAndDeviceID(userID uint, deviceID string, updates map[string]interface{}) error {
	return database.Get().Register("Device").UpdateWhere(database.FilterAll(
		database.FilterEq("UserID", userID),
		database.FilterEq("DeviceID", deviceID),
	), updates)
}

// DeleteDeviceByID 按主键删除设备；返回是否实际删除。
func DeleteDeviceByID(id uint) bool {
	return database.Get().Register("Device").Delete(id)
}

// FindSyncSettingByUser 查用户同步设置；未找到返回 (nil, nil)。
func FindSyncSettingByUser(userID uint) (*models.SyncSetting, error) {
	var setting models.SyncSetting
	found, err := database.Get().Register("SyncSetting").FindOneE(database.FilterEq("UserID", userID), &setting)
	if err != nil || !found {
		return nil, err
	}
	return &setting, nil
}

// InsertSyncSetting 新建用户同步设置。
func InsertSyncSetting(setting *models.SyncSetting) error {
	return database.Get().Register("SyncSetting").Insert(setting)
}
