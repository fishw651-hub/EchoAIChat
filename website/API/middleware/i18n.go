package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// I18nLang 解析当前请求的语言偏好并写入 c.Set("lang", ...)。
//
// 解析顺序：
//  1. 查询参数 ?lang=（"en"/"zh" 精确匹配）
//  2. Accept-Language 请求头（前缀以 "en" 开头视为英文）
//  3. 回退到 "zh"
//
// 建议作为首个全局中间件注册，后续所有 handler 均可通过 utils.ResolveLang(c) 读取。
func I18nLang() gin.HandlerFunc {
	return func(c *gin.Context) {
		lang := resolveRequestLang(c)
		c.Set("lang", lang)
		c.Next()
	}
}

// resolveRequestLang 实现解析优先级：query → Accept-Language → 默认 zh。
func resolveRequestLang(c *gin.Context) string {
	// 1) 查询参数优先：客户端可显式覆盖
	if q := strings.TrimSpace(c.Query("lang")); q != "" {
		q = strings.ToLower(q)
		if q == "en" || strings.HasPrefix(q, "en") {
			return "en"
		}
		if q == "zh" || strings.HasPrefix(q, "zh") {
			return "zh"
		}
	}

	// 2) Accept-Language 头
	accept := strings.TrimSpace(c.GetHeader("Accept-Language"))
	if accept != "" {
		// Accept-Language 形如 "en-US,en;q=0.9,zh-CN;q=0.8"
		first := strings.ToLower(strings.TrimSpace(accept))
		if strings.HasPrefix(first, "en") {
			return "en"
		}
	}

	// 3) 默认中文
	return "zh"
}
