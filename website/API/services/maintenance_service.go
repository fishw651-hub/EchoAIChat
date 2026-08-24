package services

import (
	"crypto/rand"
	"encoding/hex"

	"aichat-api/database"
	"aichat-api/models"
)

// 站点维护模式的系统配置键
const (
	MaintenanceEnabledConfigKey   = "maintenance_enabled"
	MaintenanceBypassKeyConfigKey = "maintenance_bypass_key"
)

// GetMaintenanceConfig 读取维护模式配置；未配置时默认关闭、旁路 Key 为空
func GetMaintenanceConfig() (enabled bool, bypassKey string) {
	db := database.Get()
	if db == nil {
		return false, ""
	}
	tbl := db.Register("SystemConfig")
	var sc models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", MaintenanceEnabledConfigKey), &sc) {
		enabled = sc.Value == "true"
	}
	var kc models.SystemConfig
	if tbl.FindOne(database.FilterEq("Key", MaintenanceBypassKeyConfigKey), &kc) {
		bypassKey = kc.Value
	}
	return enabled, bypassKey
}

// GenerateMaintenanceBypassKey 生成加密安全的随机旁路 Key（24 位十六进制字符）
func GenerateMaintenanceBypassKey() string {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	return hex.EncodeToString(b)
}
