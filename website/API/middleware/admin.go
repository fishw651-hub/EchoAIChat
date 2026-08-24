package middleware

import (
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			utils.Unauthorized(c, utils.T(c, "err.auth.login_required"))
			c.Abort()
			return
		}

		r := role.(string)
		if r != "admin" && r != "super_admin" {
			utils.Forbidden(c, utils.T(c, "err.auth.admin_required"))
			c.Abort()
			return
		}

		c.Next()
	}
}

func SuperAdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			utils.Unauthorized(c, utils.T(c, "err.auth.login_required"))
			c.Abort()
			return
		}

		if role.(string) != "super_admin" {
			utils.Forbidden(c, utils.T(c, "err.auth.super_admin_required"))
			c.Abort()
			return
		}

		c.Next()
	}
}
