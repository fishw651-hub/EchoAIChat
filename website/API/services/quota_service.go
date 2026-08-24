package services

import (
	"aichat-api/utils"
	"fmt"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

// quotaJobOnce 确保配额重置定时任务只启动一次，避免多次调用产生多个 goroutine
var quotaJobOnce sync.Once

func ResetDailyQuotas() {
	db := database.Get()
	today := utils.TodayCN()
	userNeedsReset := database.FilterFunc(func(m map[string]interface{}) bool {
		return fmt.Sprintf("%v", m["QuotaResetDate"]) != today
	})
	var resetUsers []models.User
	db.Register("User").FindAll(&resetUsers, userNeedsReset, "", 0, 0)

	// 重置 User 表上的聚合当日计数（跨天未刷新的）
	db.Register("User").UpdateWhere(userNeedsReset, map[string]interface{}{
		"DailyQuotaUsed":        0,
		"DailyCheckInBonus":     0,
		"SubscriptionQuotaUsed": 0,
		"OcrUsedToday":          0,
		"RealReplyUsedToday":    0,
		"QuotaResetDate":        today,
	})

	// 重置所有有效订阅的 per-subscription 当日计数
	db.Register("UserSubscription").UpdateWhere(database.FilterFunc(func(m map[string]interface{}) bool {
		s := fmt.Sprintf("%v", m["Status"])
		expires := fmt.Sprintf("%v", m["ExpiresAt"])
		reset := fmt.Sprintf("%v", m["QuotaResetDate"])
		// 仅重置有效订阅中跨天未刷新的；过期的另外标记 Status=0
		return s == "1" && expires >= today && reset != today
	}), map[string]interface{}{
		"OcrUsedToday":       0,
		"RealReplyUsedToday": 0,
		"QuotaResetDate":     today,
	})

	// 过期订阅标记为 Status=0，并通知在线客户端刷新订阅权限。
	expiredSubscriptionFilter := database.FilterFunc(func(m map[string]interface{}) bool {
		s := fmt.Sprintf("%v", m["Status"])
		expires := fmt.Sprintf("%v", m["ExpiresAt"])
		return s == "1" && expires < today
	})
	var expiredSubscriptions []models.UserSubscription
	db.Register("UserSubscription").FindAll(
		&expiredSubscriptions, expiredSubscriptionFilter, "", 0, 0,
	)
	db.Register("UserSubscription").UpdateWhere(expiredSubscriptionFilter, map[string]interface{}{
		"Status": 0,
	})

	for _, user := range resetUsers {
		PublishQuotaChanged(user.ID)
	}
	notifiedSubscriptionUsers := make(map[uint]struct{})
	for _, subscription := range expiredSubscriptions {
		if _, exists := notifiedSubscriptionUsers[subscription.UserID]; exists {
			continue
		}
		notifiedSubscriptionUsers[subscription.UserID] = struct{}{}
		PublishSubscriptionChanged(subscription.UserID)
		PublishQuotaChanged(subscription.UserID)
	}
}

func StartQuotaResetJob() {
	quotaJobOnce.Do(func() {
		ticker := time.NewTicker(5 * time.Minute)
		go func() {
			for range ticker.C {
				// ResetDailyQuotas 内部通过 QuotaResetDate != today 条件过滤，
				// 同一天重复调用时 UpdateWhere 匹配 0 行，是无害的空操作。
				// 这样避免了 lastResetDate 包级变量在多实例部署下的竞态问题。
				ResetDailyQuotas()
				// 清理超过 30 分钟仍处于 pending 的计费预留，退还用户配额
				// 防止 chat.go 中 Settle 失败或进程崩溃导致的 reservation 永久泄漏
				CleanupStaleReservations()
			}
		}()
	})
}

// CleanupStaleReservations 清理超时未结算的 pending reservation
// 超过 30 分钟的 pending 视为异常（正常聊天应在数秒内 Settle），Release 退还配额
func CleanupStaleReservations() {
	db := database.Get()
	resTbl := db.Register("BillingReservation")
	// 自定义 filter：status=pending 且创建超过 30 分钟
	threshold := time.Now().UTC().Add(-30 * time.Minute)
	var rows []map[string]interface{}
	resTbl.FindAll(&rows, database.FilterFunc(func(m map[string]interface{}) bool {
		status, _ := m["Status"].(string)
		if status != "pending" {
			return false
		}
		createdAtStr, _ := m["CreatedAt"].(string)
		createdAt, err := time.Parse(time.RFC3339Nano, createdAtStr)
		if err != nil {
			return false
		}
		return createdAt.Before(threshold)
	}), "", 0, 0)

	billing := &BillingService{}
	for _, r := range rows {
		if id, ok := r["ReservationID"].(string); ok && id != "" {
			_ = billing.Release(id)
		}
	}
}
