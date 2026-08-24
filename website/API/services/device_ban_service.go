package services

import (
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

// 设备账号切换封禁规则：
//   - 窗口期 DeviceBanWindowDays 天内登录过 ≥ DeviceBanMaxAccounts 个不同账号 → 封禁
//   - 第 N 次封禁 = 2^(N-1) 天（1、2、4、8…，封顶 DeviceBanMaxDays 天）
//   - 到期自动解封；解封后再犯封禁天数继续递增
//   - 有激活订阅的账号不计入、不受限
const (
	DeviceBanWindowDays  = 14
	DeviceBanMaxAccounts = 3
	DeviceBanMaxDays     = 365
)

// DeviceBanDaysForCount 第 N 次封禁的天数：1、2、4、8…，封顶 DeviceBanMaxDays
func DeviceBanDaysForCount(count int) int {
	if count <= 0 {
		return 0
	}
	days := 1 << (count - 1)
	if days > DeviceBanMaxDays || days <= 0 {
		days = DeviceBanMaxDays
	}
	return days
}

// HasActiveSubscription 用户当前是否有激活订阅
func HasActiveSubscription(userID uint) bool {
	return HasActiveSubscriptionForUser(userID)
}

// deviceBanLocks 分片锁：RecordDeviceLogin 的 读快照→清理→判封→插入 全程
// 无锁时，同设备并发登录会基于过期快照判封（多封/漏封），按 deviceID 串行化
var deviceBanLocks = utils.NewStripedLock()

// RecordDeviceLogin 登录成功后记录设备账号切换。
// 触发封禁时返回 banned=true 及封禁信息；订阅账号直接豁免不记录。
func RecordDeviceLogin(deviceID string, userID uint) (banned bool, banUntil time.Time, banDays int) {
	if deviceID == "" {
		return false, time.Time{}, 0
	}
	if HasActiveSubscription(userID) {
		return false, time.Time{}, 0
	}

	defer deviceBanLocks.Lock(deviceID)()

	db := database.Get()
	now := time.Now()
	cutoff := now.AddDate(0, 0, -DeviceBanWindowDays)

	// 裁剪窗口期内的该设备记录，统计不同账号
	logsTable := db.Register("DeviceAccountLog")
	var logs []models.DeviceAccountLog
	logsTable.FindAll(&logs, database.FilterEq("DeviceID", deviceID), "", 0, 0)

	distinct := map[uint]bool{userID: true}
	for _, l := range logs {
		if l.LoginAt.Before(cutoff) {
			// 过期记录清理
			logsTable.Delete(l.ID)
			continue
		}
		distinct[l.UserID] = true
	}

	if len(distinct) >= DeviceBanMaxAccounts {
		bansTable := db.Register("DeviceBan")
		var ban models.DeviceBan
		count := 1
		if bansTable.FindOne(database.FilterEq("DeviceID", deviceID), &ban) {
			count = ban.BanCount + 1
		}
		days := DeviceBanDaysForCount(count)
		until := now.AddDate(0, 0, days)
		if ban.ID == 0 {
			bansTable.Insert(&models.DeviceBan{
				DeviceID: deviceID,
				BanUntil: until,
				BanCount: count,
			})
		} else {
			bansTable.UpdateWhere(database.FilterEq("DeviceID", deviceID), map[string]interface{}{
				"BanUntil": until.UTC().Format(time.RFC3339Nano),
				"BanCount": count,
			})
		}
		// 封禁后清空该设备记录，解封后重新累计
		for _, l := range logs {
			logsTable.Delete(l.ID)
		}
		return true, until, days
	}

	logsTable.Insert(&models.DeviceAccountLog{
		DeviceID: deviceID,
		UserID:   userID,
		LoginAt:  now,
	})
	return false, time.Time{}, 0
}

// CheckDeviceBan 查询设备当前封禁状态；到期自动解封（BanCount 保留，再犯继续递增）
func CheckDeviceBan(deviceID string) (banned bool, banUntil time.Time, banDays int) {
	if deviceID == "" {
		return false, time.Time{}, 0
	}
	var ban models.DeviceBan
	if !database.Get().Register("DeviceBan").FindOne(database.FilterEq("DeviceID", deviceID), &ban) {
		return false, time.Time{}, 0
	}
	if !time.Now().Before(ban.BanUntil) {
		return false, time.Time{}, 0
	}
	return true, ban.BanUntil, DeviceBanDaysForCount(ban.BanCount)
}
