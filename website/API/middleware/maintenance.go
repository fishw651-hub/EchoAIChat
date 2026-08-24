package middleware

import (
	"crypto/subtle"
	"net/http"
	"path"
	"strings"
	"sync"

	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

// MaintenancePageKind 维护模式下被拦截的页面类型
type MaintenancePageKind int

const (
	// MaintenancePageLanding 落地页首页及 landing/* 页面（不支持旁路）
	MaintenancePageLanding MaintenancePageKind = iota
	// MaintenancePageAdmin 后台入口页（index.html / login.html，支持 ?maint_key= 旁路）
	MaintenancePageAdmin
)

const maintenanceBypassCookie = "maint_key"

// 默认维护页：main.go 启动时会用内嵌的 maintenance.html 覆盖（SetMaintenancePageHTML）
var defaultMaintenancePage = `<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8">` +
	`<meta name="viewport" content="width=device-width, initial-scale=1"><title>站点更新维护中</title></head>` +
	`<body style="font-family:system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0">` +
	`<div style="text-align:center"><h1>站点更新维护中</h1><p>我们正在进行站点更新维护，请稍后再来。</p></div></body></html>`

var (
	maintenancePageMu   sync.RWMutex
	maintenancePageHTML = []byte(defaultMaintenancePage)
)

// SetMaintenancePageHTML 设置维护模式开启时返回的页面内容（由 main 包内嵌 maintenance.html 注入）
func SetMaintenancePageHTML(html []byte) {
	if len(html) == 0 {
		return
	}
	maintenancePageMu.Lock()
	maintenancePageHTML = html
	maintenancePageMu.Unlock()
}

// MaintenanceGuard 站点维护模式拦截。
// 开启维护模式后，被保护的 HTML 入口页返回维护页（503）；
// 其余请求（/api、/uploads、js/css 等静态资源）一律放行。
// admin 入口页支持 ?maint_key=<key> 旁路，命中后写 cookie，
// 以便后台 login.html → index.html 跳转后仍保持旁路。
func MaintenanceGuard(kind MaintenancePageKind) gin.HandlerFunc {
	return func(c *gin.Context) {
		enabled, bypassKey := services.GetMaintenanceConfig()
		if !enabled {
			c.Next()
			return
		}
		if !isGuardedPageRequest(kind, c.Param("filepath")) {
			c.Next()
			return
		}
		if kind == MaintenancePageAdmin && bypassKey != "" && hasValidBypassKey(c, bypassKey) {
			c.Next()
			return
		}
		maintenancePageMu.RLock()
		page := maintenancePageHTML
		maintenancePageMu.RUnlock()
		c.Header("Cache-Control", "no-store")
		c.Header("Retry-After", "300")
		c.Data(http.StatusServiceUnavailable, "text/html; charset=utf-8", page)
		c.Abort()
	}
}

// isGuardedPageRequest 判断当前请求是否为需要拦截的 HTML 入口页。
// filepath 为 gin 通配符参数（如 /admin/*filepath 中的 /index.html）；
// 空字符串表示非通配符路由（"/"、"/landing" 重定向路由），直接视为页面请求。
func isGuardedPageRequest(kind MaintenancePageKind, filepath string) bool {
	if filepath == "" {
		return true
	}
	clean := path.Clean("/" + filepath)
	switch kind {
	case MaintenancePageLanding:
		// 拦截 landing 首页与各 HTML 页面，放行 css/js/图片等静态资源
		if strings.HasSuffix(clean, "/") {
			return true
		}
		ext := strings.ToLower(path.Ext(clean))
		return ext == "" || ext == ".html" || ext == ".htm"
	case MaintenancePageAdmin:
		// 只拦截后台 3 个入口页面（/ 即 index.html），放行 admin/js、admin/css 等资源
		return clean == "/" || clean == "/index.html" || clean == "/login.html"
	}
	return false
}

func hasValidBypassKey(c *gin.Context, key string) bool {
	if q := c.Query("maint_key"); subtle.ConstantTimeCompare([]byte(q), []byte(key)) == 1 {
		http.SetCookie(c.Writer, &http.Cookie{
			Name:     maintenanceBypassCookie,
			Value:    key,
			Path:     "/admin",
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
		})
		return true
	}
	if cookie, err := c.Cookie(maintenanceBypassCookie); err == nil &&
		subtle.ConstantTimeCompare([]byte(cookie), []byte(key)) == 1 {
		return true
	}
	return false
}
