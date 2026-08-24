package middleware

import (
	"log"
	"strings"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

var dailyActiveTracker = services.NewDailyActiveService()

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			utils.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			utils.Unauthorized(c, "认证格式错误")
			c.Abort()
			return
		}

		claims, err := utils.ParseToken(parts[1])
		if err != nil {
			utils.Unauthorized(c, "登录已过期，请重新登录")
			c.Abort()
			return
		}
		var user models.User
		found, err := database.Get().Register("User").FindByIDE(claims.UserID, &user)
		if err != nil {
			// DB 故障不能误判为"账户不存在"（401 会强制用户登出），返回 500 让客户端重试
			log.Printf("auth: user lookup failed: %v", err)
			utils.Internal(c, "服务器内部错误，请稍后重试")
			c.Abort()
			return
		}
		if !found || user.Status != 1 {
			utils.Unauthorized(c, "账户不存在或已被禁用")
			c.Abort()
			return
		}
		// 令牌版本必须匹配：改密/重置密码后旧 token 立即失效
		if claims.TokenVersion != user.TokenVersion {
			utils.Unauthorized(c, "登录状态已变更，请重新登录")
			c.Abort()
			return
		}

		c.Set("user_id", user.ID)
		c.Set("role", user.Role)
		if err := dailyActiveTracker.Track(user.ID, user.Role, time.Now()); err != nil {
			log.Printf("daily active tracking failed: %v", err)
		}
		c.Next()
	}
}
