package main

import (
	"crypto/rand"
	"crypto/tls"
	_ "embed"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/hub"
	"aichat-api/middleware"
	"aichat-api/models"
	"aichat-api/routes"
	"aichat-api/services"

	"golang.org/x/crypto/acme/autocert"
	"golang.org/x/crypto/bcrypt"

	"github.com/gin-gonic/gin"
)

//go:embed maintenance.html
var maintenancePageHTML []byte

func main() {
	configPath := "config.yaml"
	if len(os.Args) > 1 {
		configPath = os.Args[1]
	}

	config.LoadConfig(configPath)

	// 向 services/middleware 注入运行期配置（getter 形态，保留原热读语义）；
	// config.AppConfig 仍是唯一写入点，此处为分发点。
	services.ConfigureRuntime(services.RuntimeConfig{
		EncryptionKey:          func() string { return config.AppConfig.Encryption.Key },
		EncryptionFallbackKeys: func() []string { return config.EncryptionFallbackKeys },
		DeepSeekBaseURL:        func() string { return config.AppConfig.DeepSeek.BaseURL },
		ServerURL:              func() string { return config.AppConfig.Server.ServerURL },
		EasyPay:                func() config.EasyPayConfig { return config.AppConfig.EasyPay },
		Network:                func() config.NetworkConfig { return config.AppConfig.Network },
	})
	middleware.ConfigureRateLimit(config.AppConfig.RateLimit.PerIPRPS, config.AppConfig.RateLimit.LoginPerMin)

	if err := database.Init("./data"); err != nil {
		log.Fatalf("数据库初始化失败: %v", err)
	}
	os.MkdirAll("uploads/avatars", 0755)
	os.MkdirAll("uploads/releases", 0755)
	seedData()
	migratePaymentAPIURL()
	migrateDefaultQuotaConfig()
	migrateMaintenanceConfig()

	middleware.SetMaintenancePageHTML(maintenancePageHTML)

	hub.InitSyncHub()                   // 初始化多端同步 WebSocket Hub
	services.SetEventPublisher(hub.Hub) // 业务事件经窄接口注入，services 不直依赖 hub 单例

	// 后台周期任务：配额日重置 + 过期计费预留清理（5 分钟 tick），
	// 增长型表保留策略（每日）。此前从未被调用，预留泄漏与表膨胀无人兜底。
	services.StartQuotaResetJob()
	services.StartRetentionJob()

	if config.AppConfig.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	if err := r.SetTrustedProxies(nil); err != nil {
		log.Fatalf("配置可信代理失败: %v", err)
	}
	r.MaxMultipartMemory = 32 << 20
	r.Use(middleware.Logger())
	r.Use(gin.Recovery())
	r.Use(middleware.CORS(config.AppConfig.CORS.AllowedOrigins))
	r.Use(middleware.RateLimit())
	r.Use(middleware.BodyLimit(32 << 20))

	routes.SetupRoutes(r)

	addr := fmt.Sprintf(":%d", config.AppConfig.Server.Port)
	listenAddr := addr
	if config.AppConfig.TLS.Enabled {
		listenAddr = fmt.Sprintf(":%d", config.AppConfig.TLS.Port)
		log.Printf("🚀 服务启动于 https://0.0.0.0%s", listenAddr)
		log.Printf("  🔗 管理后台: https://localhost%s/admin", listenAddr)
	} else {
		log.Printf("🚀 服务启动于 http://0.0.0.0%s", addr)
		log.Printf("  🔗 管理后台: http://localhost%s/admin", addr)
	}

	// HTTP 主服务用自定义 listener（4MB buffer + TCP_NODELAY）
	mainLn, err := services.ListenTCPWithBuffer(listenAddr)
	if err != nil {
		log.Fatalf("HTTP listener 创建失败: %v", err)
	}
	mainSrv := &http.Server{
		Addr:              listenAddr,
		Handler:           r,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      330 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}
	if config.AppConfig.TLS.Enabled {
		tlsConfig, acmeManager, err := buildTLSConfig(config.AppConfig.TLS)
		if err != nil {
			log.Fatalf("初始化 TLS 失败: %v", err)
		}
		if acmeManager != nil && addr != listenAddr {
			go serveACMEHTTP(addr, acmeManager)
		}
		mainLn = tls.NewListener(mainLn, tlsConfig)
	}

	if err := mainSrv.Serve(mainLn); err != nil {
		log.Fatalf("服务启动失败: %v", err)
	}
}

func buildTLSConfig(cfg config.TLSConfig) (*tls.Config, *autocert.Manager, error) {
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS12}
	if cfg.AutoACME {
		if err := os.MkdirAll(cfg.CacheDir, 0o700); err != nil {
			return nil, nil, fmt.Errorf("创建 ACME 缓存目录失败: %w", err)
		}
		manager := &autocert.Manager{
			Prompt:     autocert.AcceptTOS,
			Email:      cfg.ACMEEmail,
			HostPolicy: autocert.HostWhitelist(cfg.ACMEDomains...),
			Cache:      autocert.DirCache(cfg.CacheDir),
		}
		tlsConfig = manager.TLSConfig()
		tlsConfig.MinVersion = tls.VersionTLS12
		return tlsConfig, manager, nil
	}
	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		return nil, nil, fmt.Errorf("读取 cert_file/key_file 失败: %w", err)
	}
	tlsConfig.Certificates = []tls.Certificate{cert}
	return tlsConfig, nil, nil
}

func serveACMEHTTP(addr string, manager *autocert.Manager) {
	listener, err := services.ListenTCPWithBuffer(addr)
	if err != nil {
		log.Fatalf("ACME HTTP listener 创建失败: %v", err)
	}
	server := &http.Server{
		Addr:              addr,
		Handler:           manager.HTTPHandler(nil),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Printf("🔐 ACME HTTP-01 挑战监听于 http://0.0.0.0%s", addr)
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatalf("ACME HTTP 服务失败: %v", err)
	}
}

func seedData() {
	db := database.Get()
	users := db.Register("User")

	var existing models.User
	if !users.FindOne(database.FilterEq("Role", "super_admin"), &existing) {
		// 从环境变量读取管理员密码，未设置则生成随机密码（不再使用硬编码弱密码）
		adminPassword := os.Getenv("ADMIN_PASSWORD")
		if adminPassword == "" {
			adminPassword = generateRandomPassword(16)
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(adminPassword), 12)
		if err != nil {
			log.Fatalf("生成管理员密码哈希失败: %v", err)
		}
		users.Insert(&models.User{
			Username:     "admin",
			Email:        "admin@aichat.local",
			PasswordHash: string(hash),
			Nickname:     "超级管理员",
			Role:         "super_admin",
			Status:       1,
			Balance:      9999,
		})
		log.Printf("已创建默认超级管理员: admin / %s", adminPassword)
		log.Println("⚠️  请立即登录管理后台修改密码！后续不会再显示此密码。")
	}

	cfg := db.Register("SystemConfig")
	if cfg.Count(nil) == 0 {
		cfg.Insert(&models.SystemConfig{Key: "default_ocr_daily_quota", Value: "3", Description: "无订阅用户每日聊天记录识别次数"})
		cfg.Insert(&models.SystemConfig{Key: "default_real_reply_daily_quota", Value: "30", Description: "无订阅用户每日真实回复对话轮数"})
		cfg.Insert(&models.SystemConfig{Key: "site_name", Value: "AIchat中继站", Description: "站点名称"})
		cfg.Insert(&models.SystemConfig{Key: "server_url", Value: config.AppConfig.Server.ServerURL, Description: "服务器地址（用于支付回调等）"})

		encKey := config.AppConfig.Encryption.Key
		if len(encKey) < 32 {
			encKey = encKey + "00000000000000000000000000000000"
		}
		keyEnc, _ := services.Encrypt(config.AppConfig.EasyPay.Key, []byte(encKey[:32]))
		cfg.Insert(&models.SystemConfig{Key: "easypay_pid", Value: config.AppConfig.EasyPay.PID, Description: "易支付商户ID"})
		cfg.Insert(&models.SystemConfig{Key: "easypay_key", Value: keyEnc, Description: "易支付商户密钥(已加密)"})
		cfg.Insert(&models.SystemConfig{Key: "easypay_sitename", Value: config.AppConfig.EasyPay.Sitename, Description: "易支付站点名称"})
		cfg.Insert(&models.SystemConfig{Key: "payment_api_url", Value: "https://pay.example.com/submit", Description: "支付接口地址"})
		cfg.Insert(&models.SystemConfig{Key: "payment_query_url", Value: "https://pay.example.com/api", Description: "支付查询接口地址"})
		cfg.Insert(&models.SystemConfig{Key: "payment_provider", Value: "easypay", Description: "支付渠道: easypay / ifdian"})

		log.Println("已初始化默认系统配置（含支付配置）")
	}
}

// generateRandomPassword 生成加密安全的随机密码
func generateRandomPassword(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
	b := make([]byte, length)
	for i := range b {
		// crypto/rand 只在系统熵源故障时才会出错——此时生成的密码不可信，必须 fail-fast
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			log.Fatalf("生成随机密码失败（系统熵源异常）: %v", err)
		}
		b[i] = charset[n.Int64()]
	}
	return string(b)
}

func migratePaymentAPIURL() {
	db := database.Get()
	cfg := db.Register("SystemConfig")

	var sc models.SystemConfig
	if cfg.FindOne(database.FilterEq("Key", "payment_api_url"), &sc) && sc.Value != "" {
		oldVal := sc.Value
		newVal := oldVal
		newVal = strings.Replace(newVal, "old.example.com", "pay.example.com", 1)
		newVal = strings.Replace(newVal, "/mapi.php", "/submit.php", 1)

		u, err := url.Parse(services.EnsureHTTP(newVal))
		if err == nil && (u.Path == "" || u.Path == "/") {
			newVal = strings.TrimRight(services.EnsureHTTP(newVal), "/") + "/submit.php"
		}

		if newVal != oldVal {
			cfg.UpdateWhere(database.FilterEq("Key", "payment_api_url"), map[string]interface{}{"Value": newVal})
			log.Printf("已迁移 payment_api_url: %s → %s", oldVal, newVal)
		}
	}

	var qc models.SystemConfig
	if cfg.FindOne(database.FilterEq("Key", "payment_query_url"), &qc) && qc.Value != "" {
		oldVal := qc.Value
		newVal := strings.Replace(oldVal, "old.example.com", "pay.example.com", 1)

		if newVal != oldVal {
			cfg.UpdateWhere(database.FilterEq("Key", "payment_query_url"), map[string]interface{}{"Value": newVal})
			log.Printf("已迁移 payment_query_url: %s → %s", oldVal, newVal)
		}
	}
}

// migrateDefaultQuotaConfig 为旧部署补齐缺失的功能配额系统默认配置项
func migrateDefaultQuotaConfig() {
	db := database.Get()
	cfg := db.Register("SystemConfig")

	defaults := map[string]struct {
		Value       string
		Description string
	}{
		"default_ocr_daily_quota":        {"3", "无订阅用户每日聊天记录识别次数"},
		"default_real_reply_daily_quota": {"30", "无订阅用户每日真实回复对话轮数"},
	}

	for key, def := range defaults {
		var sc models.SystemConfig
		if !cfg.FindOne(database.FilterEq("Key", key), &sc) {
			cfg.Insert(&models.SystemConfig{Key: key, Value: def.Value, Description: def.Description})
			log.Printf("已补齐系统配置: %s = %s", key, def.Value)
		}
	}
}

// migrateMaintenanceConfig 为旧部署补齐站点维护模式默认配置（默认关闭、旁路 Key 为空）
func migrateMaintenanceConfig() {
	db := database.Get()
	cfg := db.Register("SystemConfig")

	defaults := map[string]struct {
		Value       string
		Description string
	}{
		"maintenance_enabled":    {"false", "站点维护模式开关（开启后落地页与后台入口页显示维护页，API 不受影响）"},
		"maintenance_bypass_key": {"", "维护模式旁路 Key（后台通过 /admin/?maint_key=Key 访问）"},
	}

	for key, def := range defaults {
		var sc models.SystemConfig
		if !cfg.FindOne(database.FilterEq("Key", key), &sc) {
			cfg.Insert(&models.SystemConfig{Key: key, Value: def.Value, Description: def.Description})
			log.Printf("已补齐系统配置: %s = %s", key, def.Value)
		}
	}
}
