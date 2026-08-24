package handlers

import (
	"time"

	"aichat-api/hub"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type DeviceHandler struct{}

var deviceRoleLocks = utils.NewStripedLock()

// RegisterDevice 注册/更新当前设备信息（每次 App 启动调用）
// POST /api/v1/sync/devices/register
func (h *DeviceHandler) RegisterDevice(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req struct {
		DeviceID   string `json:"device_id" binding:"required"`
		DeviceName string `json:"device_name"`
		ClientKind string `json:"client_kind"`
		Platform   string `json:"platform"`
		Browser    string `json:"browser"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	// 查找是否已存在该设备
	existing, err := services.FindDevice(userID, req.DeviceID)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.device.query_failed"))
		return
	}

	now := time.Now()
	if existing != nil {
		// 已存在 → 更新名称、平台、活跃时间
		updates := map[string]interface{}{
			"ClientKind":   req.ClientKind,
			"Platform":     req.Platform,
			"Browser":      req.Browser,
			"LastActiveAt": now,
			"UpdatedAt":    now,
		}
		if req.DeviceName != "" {
			updates["DeviceName"] = req.DeviceName
			existing.DeviceName = req.DeviceName
		}
		if err := services.UpdateDeviceByID(existing.ID, updates); err != nil {
			utils.Internal(c, utils.T(c, "err.device.update_failed"))
			return
		}
		existing.ClientKind = req.ClientKind
		existing.Platform = req.Platform
		existing.Browser = req.Browser
		existing.LastActiveAt = now
		existing.UpdatedAt = now
		utils.Success(c, existing)
		return
	}

	// 不存在 → 新建设备，默认为副机
	// 如果该用户还没有任何设备，则这台自动成为主机
	count, err := services.CountDevicesByUser(userID)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.device.query_failed"))
		return
	}
	role := "slave"
	if count == 0 {
		role = "master"
	}
	device := models.Device{
		UserID:       userID,
		DeviceID:     req.DeviceID,
		DeviceName:   req.DeviceName,
		ClientKind:   req.ClientKind,
		Platform:     req.Platform,
		Browser:      req.Browser,
		Role:         role,
		LastActiveAt: now,
	}
	if err := services.InsertDevice(&device); err != nil {
		utils.Internal(c, utils.T(c, "err.device.register_failed"))
		return
	}

	// 如果是该用户的第一台设备，自动创建同步设置（默认关闭100%同步）
	if setting, err := services.FindSyncSettingByUser(userID); err == nil && setting == nil {
		services.InsertSyncSetting(&models.SyncSetting{
			UserID:           userID,
			ScopeMode:        "all",
			SelectedAgentIDs: []string{},
			PolicyVersion:    1,
		})
	}

	utils.Success(c, device)
}

// ListDevices 列出当前账号所有设备
// GET /api/v1/sync/devices
func (h *DeviceHandler) ListDevices(c *gin.Context) {
	userID := c.GetUint("user_id")
	devices := services.ListDevicesByUser(userID)

	// 同时返回同步设置
	setting, err := services.FindSyncSettingByUser(userID)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.sync.setting_read_failed"))
		return
	}

	result := gin.H{
		"devices":           devices,
		"full_sync":         false,
		"current_device_id": c.Query("device_id"),
	}
	if setting != nil {
		result["full_sync"] = setting.FullSyncEnabled
	}
	utils.Success(c, result)
}

// SetDeviceRole 设置设备角色（主机/副机）。一个账号只能有一个主机。
// PUT /api/v1/sync/devices/:device_id/role
func (h *DeviceHandler) SetDeviceRole(c *gin.Context) {
	userID := c.GetUint("user_id")
	deviceID := c.Param("device_id")
	var req struct {
		Role string `json:"role" binding:"required"` // master / slave
	}
	if err := c.ShouldBindJSON(&req); err != nil || (req.Role != "master" && req.Role != "slave") {
		utils.BadRequest(c, utils.T(c, "err.device.role_invalid"))
		return
	}

	// 加锁保证"降级其他主机 → 更新目标设备"的原子性，防止并发导致多主机或无主机
	unlock := deviceRoleLocks.LockUint(userID)
	defer unlock()

	// 验证设备属于该用户
	target, err := services.FindDevice(userID, deviceID)
	if err != nil || target == nil {
		utils.NotFound(c, utils.T(c, "err.device.not_found"))
		return
	}

	// 降级校验：如果目标是当前主机且要设为副机，需确保还有其他设备可升为主机
	if req.Role == "slave" && target.Role == "master" {
		masterCount, err := services.CountDevicesByUserAndRole(userID, "master")
		if err != nil {
			utils.Internal(c, utils.T(c, "err.device.query_failed"))
			return
		}
		totalCount, err := services.CountDevicesByUser(userID)
		if err != nil {
			utils.Internal(c, utils.T(c, "err.device.query_failed"))
			return
		}
		if masterCount <= 1 && totalCount > 1 {
			utils.BadRequest(c, utils.T(c, "err.device.master_demote_required"))
			return
		}
	}

	now := time.Now()

	// 如果设为主机，先把该用户的其他主机降级为副机
	if req.Role == "master" {
		for _, d := range services.ListDevicesByUserAndRole(userID, "master") {
			if d.DeviceID != deviceID {
				services.UpdateDeviceByID(d.ID, map[string]interface{}{
					"Role":      "slave",
					"UpdatedAt": now,
				})
			}
		}
	}

	// 更新目标设备角色
	services.UpdateDeviceByID(target.ID, map[string]interface{}{
		"Role":      req.Role,
		"UpdatedAt": now,
	})
	target.Role = req.Role
	target.UpdatedAt = now

	// 通知该用户所有在线设备角色变更
	if hub.Hub != nil {
		hub.Hub.NotifySyncChange(userID, "device_role")
	}

	utils.Success(c, target)
}

// UpdateDeviceName 更新设备名称
// PUT /api/v1/sync/devices/:device_id/name
func (h *DeviceHandler) UpdateDeviceName(c *gin.Context) {
	userID := c.GetUint("user_id")
	deviceID := c.Param("device_id")
	var req struct {
		DeviceName string `json:"device_name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	target, err := services.FindDevice(userID, deviceID)
	if err != nil || target == nil {
		utils.NotFound(c, utils.T(c, "err.device.not_found"))
		return
	}

	now := time.Now()
	services.UpdateDeviceByID(target.ID, map[string]interface{}{
		"DeviceName": req.DeviceName,
		"UpdatedAt":  now,
	})
	target.DeviceName = req.DeviceName
	target.UpdatedAt = now
	utils.Success(c, target)
}

// DeleteDevice 删除设备
// DELETE /api/v1/sync/devices/:device_id
func (h *DeviceHandler) DeleteDevice(c *gin.Context) {
	userID := c.GetUint("user_id")
	deviceID := c.Param("device_id")

	target, err := services.FindDevice(userID, deviceID)
	if err != nil || target == nil {
		utils.NotFound(c, utils.T(c, "err.device.not_found"))
		return
	}

	// 不允许删除当前主机（需先切换其他设备为主机）
	if target.Role == "master" {
		slaveCount, err := services.CountDevicesByUserAndRole(userID, "slave")
		if err != nil {
			utils.Internal(c, utils.T(c, "err.device.query_failed"))
			return
		}
		if slaveCount > 0 {
			utils.BadRequest(c, utils.T(c, "err.device.delete_master_first"))
			return
		}
		// 只有一台设备时允许删除（会清空设备列表）
	}

	services.DeleteDeviceByID(target.ID)
	utils.Success(c, gin.H{"message": "已删除"})
}

// SetFullSync 设置 100% 同步开关
// PUT /api/v1/sync/devices/full_sync
func (h *DeviceHandler) SetFullSync(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	current, err := services.DefaultSyncPolicyService.Get(userID)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.sync.setting_read_failed"))
		return
	}
	updated, err := services.DefaultSyncPolicyService.Update(userID, models.SyncPolicyUpdate{
		ScopeMode:        current.ScopeMode,
		SelectedAgentIDs: current.SelectedAgentIDs,
		RealtimeEnabled:  req.Enabled,
		ExpectedVersion:  current.Version,
	})
	if err != nil {
		utils.Internal(c, utils.T(c, "err.sync.setting_update_failed"))
		return
	}
	utils.Success(c, gin.H{"full_sync": req.Enabled, "policy": updated})
}
