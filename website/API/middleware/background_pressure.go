package middleware

import (
	"net/http"
	"time"

	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

func BackgroundPressure(limiter *services.AdaptiveLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !limiter.TryAcquire() {
			c.Header("Retry-After", "1")
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"code":    http.StatusTooManyRequests,
				"message": "服务器正在处理较多同步任务，请稍后重试",
			})
			return
		}
		startedAt := time.Now()
		defer func() {
			status := c.Writer.Status()
			if recovered := recover(); recovered != nil {
				status = http.StatusInternalServerError
				limiter.Release(status, time.Since(startedAt))
				panic(recovered)
			}
			limiter.Release(status, time.Since(startedAt))
		}()
		c.Next()
	}
}
