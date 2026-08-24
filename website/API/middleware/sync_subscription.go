package middleware

import (
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

// HasSyncSubscription 检查用户是否有有效订阅（status==1 且未过期）
func HasSyncSubscription(userID uint) bool {
	return services.HasActiveSubscriptionForUser(userID)
}

// RequireSyncSubscription 多端同步订阅校验中间件
func RequireSyncSubscription() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetUint("user_id")
		if !HasSyncSubscription(userID) {
			utils.Forbidden(c, utils.T(c, "err.sync.subscription_required"))
			c.Abort()
			return
		}
		c.Next()
	}
}
