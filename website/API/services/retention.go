package services

import (
	"log"
	"sync"
	"time"

	"aichat-api/database"
)

var retentionOnce sync.Once

// StartRetentionJob 每日清理增长型表，防止 JSON-in-SQLite 单表无限膨胀：
//   - AuditLog：保留 90 天
//   - BillingReservation：已 settled/released 的保留 90 天（pending 由配额任务的
//     CleanupStaleReservations 兜底释放，不在此删除）
//   - DeviceAccountLog：保留 30 天（设备封禁窗口 14 天，30 天足够兜底）
//
// UsageRecord / PaymentOrder 涉及计费与订单历史，不在自动清理范围。
func StartRetentionJob() {
	retentionOnce.Do(func() {
		go func() {
			ticker := time.NewTicker(time.Hour)
			defer ticker.Stop()
			var lastRun time.Time
			for range ticker.C {
				if time.Since(lastRun) < 24*time.Hour {
					continue
				}
				lastRun = time.Now()
				RunRetention()
			}
		}()
	})
}

// RunRetention 执行一轮清理（导出以便测试与手动触发）
func RunRetention() {
	db := database.Get()
	now := time.Now().UTC()
	cutoff90 := now.AddDate(0, 0, -90).Format(time.RFC3339Nano)
	cutoff30 := now.AddDate(0, 0, -30).Format(time.RFC3339Nano)

	// payload 内时间为 RFC3339Nano 字符串，字典序即时间序
	if n, err := db.Register("AuditLog").DeleteWhereRaw(
		"json_extract(CAST(payload AS TEXT),'$.CreatedAt') < ?", cutoff90); err != nil {
		log.Printf("[保留策略] 审计日志清理失败: %v", err)
	} else if n > 0 {
		log.Printf("[保留策略] 清理审计日志 %d 条", n)
	}

	if n, err := db.Register("BillingReservation").DeleteWhereRaw(
		"json_extract(CAST(payload AS TEXT),'$.Status') IN ('settled','released') AND json_extract(CAST(payload AS TEXT),'$.CreatedAt') < ?",
		cutoff90); err != nil {
		log.Printf("[保留策略] 计费预留清理失败: %v", err)
	} else if n > 0 {
		log.Printf("[保留策略] 清理历史计费预留 %d 条", n)
	}

	if n, err := db.Register("DeviceAccountLog").DeleteWhereRaw(
		"json_extract(CAST(payload AS TEXT),'$.LoginAt') < ?", cutoff30); err != nil {
		log.Printf("[保留策略] 设备登录记录清理失败: %v", err)
	} else if n > 0 {
		log.Printf("[保留策略] 清理设备登录记录 %d 条", n)
	}
}
