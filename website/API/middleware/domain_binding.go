package middleware

import (
	"net/http"
	"net/url"
	"strings"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func checkDomainWhitelist(hostname string, whitelist []string) bool {
	for _, d := range whitelist {
		d = strings.TrimSpace(d)
		if d == "" {
			continue
		}
		if hostname == d || strings.HasSuffix(hostname, "."+d) {
			return true
		}
	}
	return false
}

// DomainBinding 域名绑定校验。staticWhitelist 为 config.yaml 静态白名单的 getter，
// 由装配方（routes/main）传入；getter 形态保留原"每请求读全局"的热读语义。
func DomainBinding(staticWhitelist func() []string) gin.HandlerFunc {
	return func(c *gin.Context) {
		var domainBinding models.SystemConfig
		db := database.Get()

		origin := c.GetHeader("Origin")
		if origin == "" {
			origin = c.GetHeader("Referer")
		}
		if origin == "" {
			c.Next()
			return
		}

		hostname := extractHostname(origin)
		if hostname == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"code":    -1,
				"message": utils.T(c, "err.domain.unresolvable"),
			})
			return
		}

		// 优先检查静态白名单（config.yaml）
		if staticWhitelist != nil && checkDomainWhitelist(hostname, staticWhitelist()) {
			c.Next()
			return
		}

		// 再检查 DB 动态白名单（仅当 domain_binding_enabled 开启）
		if !db.Register("SystemConfig").FindOne(database.FilterEq("Key", "domain_binding_enabled"), &domainBinding) || domainBinding.Value != "true" {
			c.Next()
			return
		}

		var allowedDomains models.SystemConfig
		if !db.Register("SystemConfig").FindOne(database.FilterEq("Key", "allowed_domains"), &allowedDomains) || allowedDomains.Value == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"code": -1, "message": utils.T(c, "err.domain.whitelist_empty")})
			return
		}

		allowed := strings.Split(allowedDomains.Value, ",")
		matched := false
		for _, d := range allowed {
			d = strings.TrimSpace(d)
			if d == "" {
				continue
			}
			if hostname == d || strings.HasSuffix(hostname, "."+d) {
				matched = true
				break
			}
		}

		if !matched {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"code":    -1,
				"message": utils.TP(c, "err.domain.not_whitelisted", map[string]string{"host": hostname}),
			})
			return
		}

		c.Next()
	}
}

func extractHostname(raw string) string {
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	host := u.Hostname()
	return host
}
