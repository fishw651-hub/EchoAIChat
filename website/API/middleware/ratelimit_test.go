package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// 同一 CF-Connecting-IP、不同 RemoteAddr（不同 CF 边缘节点）必须计入同一登录限流桶，
// 否则攻击者经多节点分散请求即可稀释限流。
func TestLoginRateLimitSharesBucketByCFConnectingIP(t *testing.T) {
	gin.SetMode(gin.TestMode)

	oldLimiter := perIPLoginLimiter
	perIPLoginLimiter = newIPRateLimiter(func() *rate.Limiter {
		return rate.NewLimiter(rate.Limit(2)/60, 2)
	})
	t.Cleanup(func() { perIPLoginLimiter = oldLimiter })

	router := gin.New()
	router.SetTrustedProxies(nil) // 与生产 main.go 一致：ClientIP = TCP 对端（CF 边缘节点）
	router.POST("/login", LoginRateLimit(), func(c *gin.Context) { c.Status(http.StatusNoContent) })

	do := func(remoteAddr string) int {
		req := httptest.NewRequest(http.MethodPost, "/login", nil)
		req.RemoteAddr = remoteAddr
		req.Header.Set("CF-Connecting-IP", "203.0.113.10")
		resp := httptest.NewRecorder()
		router.ServeHTTP(resp, req)

		// 放行时 handler 返回 204 空体，视为 code 0；限流时才有 JSON 错误体
		if resp.Body.Len() == 0 {
			return 0
		}
		var body utils.Response
		if err := json.Unmarshal(resp.Body.Bytes(), &body); err != nil {
			t.Fatalf("unmarshal response: %v", err)
		}
		return body.Code
	}

	// 前两次来自不同边缘节点（不同 RemoteAddr），同一真实 IP，均应放行
	if code := do("198.51.100.1:10001"); code != 0 {
		t.Fatalf("第 1 次请求 code = %d, want 放行", code)
	}
	if code := do("198.51.100.2:10002"); code != 0 {
		t.Fatalf("第 2 次请求 code = %d, want 放行", code)
	}
	// 第 3 次又换一个边缘节点，仍应命中同一桶被限流
	if code := do("198.51.100.3:10003"); code != utils.CodeTooManyReqs {
		t.Fatalf("第 3 次请求 code = %d, want %d（同桶限流）", code, utils.CodeTooManyReqs)
	}
}

// 无 CF-Connecting-IP（或头非法）时回退 c.ClientIP()。
func TestRealClientIPFallback(t *testing.T) {
	gin.SetMode(gin.TestMode)

	newCtx := func(remoteAddr, cfHeader string) *gin.Context {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = remoteAddr
		if cfHeader != "" {
			req.Header.Set("CF-Connecting-IP", cfHeader)
		}
		c.Request = req
		return c
	}

	if ip := realClientIP(newCtx("192.0.2.1:5555", "203.0.113.7")); ip != "203.0.113.7" {
		t.Fatalf("CF 头优先, got %q", ip)
	}
	if ip := realClientIP(newCtx("192.0.2.1:5555", "")); ip != "192.0.2.1" {
		t.Fatalf("无 CF 头应回退 RemoteAddr, got %q", ip)
	}
	if ip := realClientIP(newCtx("192.0.2.1:5555", "not-an-ip")); ip != "192.0.2.1" {
		t.Fatalf("非法 CF 头应回退 RemoteAddr, got %q", ip)
	}
}

// TTL 淘汰：超过 limiterEntryTTL 未活跃的条目在懒清扫时被删除，map 不无界增长。
func TestIPRateLimiterEvictsStaleEntries(t *testing.T) {
	l := newIPRateLimiter(func() *rate.Limiter { return rate.NewLimiter(1, 1) })

	l.get("203.0.113.1")
	l.get("203.0.113.2")

	l.mu.Lock()
	// 203.0.113.1 沉寂 11 分钟（应淘汰）；203.0.113.2 保持活跃（应保留）
	l.entries["203.0.113.1"].lastSeen = time.Now().Add(-11 * time.Minute)
	l.lastSweep = time.Now().Add(-2 * time.Minute) // 确保下一次访问触发清扫
	l.mu.Unlock()

	l.get("203.0.113.3") // 触发懒清扫

	l.mu.Lock()
	defer l.mu.Unlock()
	if _, ok := l.entries["203.0.113.1"]; ok {
		t.Fatal("沉寂 11 分钟的条目应被 TTL 淘汰")
	}
	if _, ok := l.entries["203.0.113.2"]; !ok {
		t.Fatal("活跃条目不应被淘汰")
	}
	if _, ok := l.entries["203.0.113.3"]; !ok {
		t.Fatal("新访问的 IP 应已入桶")
	}
}
