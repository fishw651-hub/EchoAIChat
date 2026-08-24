package middleware

import (
	"net"
	"strings"
	"sync"
	"time"

	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// realClientIP 提取真实客户端 IP。
// 源站位于 Cloudflare 之后时（SetTrustedProxies(nil)），c.ClientIP() 是 CF 边缘节点 IP，
// 按它限流会把同节点的所有用户聚合成一桶、且攻击者分散到多节点即可稀释限流。
// CF 回源必带 CF-Connecting-IP 头（值为最终客户端 IP，由 CF 覆写、客户端无法经 CF 伪造），优先采用。
// 注意：若源站可被绕过 CF 直连，此头可伪造——部署层应只放行 CF IP 段回源（运维事项，不在代码内处理）。
func realClientIP(c *gin.Context) string {
	if ip := strings.TrimSpace(c.GetHeader("CF-Connecting-IP")); ip != "" {
		if net.ParseIP(ip) != nil {
			return ip
		}
	}
	return c.ClientIP()
}

// RealClientIP 导出版：供中间件之外的 handler（如分享码防爆破）按真实客户端 IP 限流
func RealClientIP(c *gin.Context) string {
	return realClientIP(c)
}

// limiterEntry 单个 IP 的令牌桶及最后活跃时间（供 TTL 淘汰）
type limiterEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

const (
	// limiterEntryTTL 条目空闲超过该时长后被淘汰，防止 limiters map 随唯一 IP 无界增长
	limiterEntryTTL = 10 * time.Minute
	// limiterSweepPeriod 懒清扫的最小间隔（在访问时顺带清理，不另起 goroutine）
	limiterSweepPeriod = time.Minute
)

// ipRateLimiter 按 IP 维护令牌桶；条目带 TTL，访问时顺带懒清扫过期项。
type ipRateLimiter struct {
	mu        sync.Mutex
	entries   map[string]*limiterEntry
	lastSweep time.Time
	newBucket func() *rate.Limiter
}

func newIPRateLimiter(newBucket func() *rate.Limiter) *ipRateLimiter {
	return &ipRateLimiter{entries: make(map[string]*limiterEntry), newBucket: newBucket}
}

func (l *ipRateLimiter) get(ip string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	if now.Sub(l.lastSweep) >= limiterSweepPeriod {
		for key, e := range l.entries {
			if now.Sub(e.lastSeen) >= limiterEntryTTL {
				delete(l.entries, key)
			}
		}
		l.lastSweep = now
	}

	entry, exists := l.entries[ip]
	if !exists {
		entry = &limiterEntry{limiter: l.newBucket()}
		l.entries[ip] = entry
	}
	entry.lastSeen = now
	return entry.limiter
}

// 限流参数由装配方（main）通过 ConfigureRateLimit 注入；
// 桶在首个 IP 到来时才创建，创建时读取当前配置——与原"懒读全局"的时机一致。
var (
	rateLimitCfgMu sync.RWMutex
	perIPRPS       = 100
	loginPerMin    = 10
)

// ConfigureRateLimit 设置限流参数；<=0 的项保持默认值（对齐 config.LoadConfig 的归一化）。
// 只影响之后新建的桶，已存在的桶保持原速率（与原实现行为相同）。
func ConfigureRateLimit(perIP, login int) {
	rateLimitCfgMu.Lock()
	defer rateLimitCfgMu.Unlock()
	if perIP > 0 {
		perIPRPS = perIP
	}
	if login > 0 {
		loginPerMin = login
	}
}

func currentPerIPRPS() int {
	rateLimitCfgMu.RLock()
	defer rateLimitCfgMu.RUnlock()
	return perIPRPS
}

func currentLoginPerMin() int {
	rateLimitCfgMu.RLock()
	defer rateLimitCfgMu.RUnlock()
	return loginPerMin
}

var perIPLimiter = newIPRateLimiter(func() *rate.Limiter {
	rps := currentPerIPRPS()
	return rate.NewLimiter(rate.Limit(rps), rps)
})

func RateLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		if strings.HasPrefix(path, "/admin") || strings.HasPrefix(path, "/uploads") || path == "/health" || path == "/" {
			c.Next()
			return
		}

		ip := realClientIP(c)
		if ip == "::1" || ip == "127.0.0.1" || ip == "localhost" {
			c.Next()
			return
		}

		limiter := perIPLimiter.get(ip)
		if !limiter.Allow() {
			utils.Fail(c, utils.CodeTooManyReqs, "请求过于频繁，请稍后再试")
			c.Abort()
			return
		}
		c.Next()
	}
}

// loginLimiter 对登录/注册接口实施更严格的限流（LoginPerMin 次/分钟）
var perIPLoginLimiter = newIPRateLimiter(func() *rate.Limiter {
	perMin := currentLoginPerMin()
	// 每分钟 perMin 次 = 每秒 perMin/60 次，burst=perMin
	return rate.NewLimiter(rate.Limit(perMin)/60, perMin)
})

// LoginRateLimit 登录/注册接口专用限流中间件
func LoginRateLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := realClientIP(c)
		limiter := perIPLoginLimiter.get(ip)
		if !limiter.Allow() {
			utils.Fail(c, utils.CodeTooManyReqs, "登录尝试过于频繁，请稍后再试")
			c.Abort()
			return
		}
		c.Next()
	}
}
