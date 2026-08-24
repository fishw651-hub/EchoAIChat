package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

const clientVersionCodeHeader = "X-Client-Version-Code"

// RequireClientVersion rejects clients that do not implement the current
// security-sensitive API contract.
func RequireClientVersion(minimumVersionCode int) gin.HandlerFunc {
	return func(c *gin.Context) {
		versionCode, err := strconv.Atoi(c.GetHeader(clientVersionCodeHeader))
		if err != nil || versionCode < minimumVersionCode {
			c.AbortWithStatusJSON(http.StatusUpgradeRequired, gin.H{
				"code":                 "upgrade_required",
				"message":              "客户端版本过低，请更新后重试",
				"minimum_version_code": minimumVersionCode,
			})
			return
		}
		c.Next()
	}
}
