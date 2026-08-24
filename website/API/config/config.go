package config

import (
	"crypto/md5"
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/spf13/viper"
)

type Config struct {
	Server     ServerConfig
	Database   DatabaseConfig
	JWT        JWTConfig
	Encryption EncryptionConfig
	EasyPay    EasyPayConfig
	Ifdian     IfdianConfig
	DeepSeek   DeepSeekConfig
	Upload     UploadConfig
	CORS       CORSConfig
	RateLimit  RateLimitConfig
	TLS        TLSConfig     `mapstructure:"tls"`
	Network    NetworkConfig `mapstructure:"network"`
}

type ServerConfig struct {
	Port            int      `mapstructure:"port"`
	Mode            string   `mapstructure:"mode"`
	ServerURL       string   `mapstructure:"server_url"`
	DomainWhitelist []string `mapstructure:"domain_whitelist"`
}

type DatabaseConfig struct {
	Type string `mapstructure:"type"`
	DSN  string `mapstructure:"dsn"`
}

type JWTConfig struct {
	Secret      string `mapstructure:"secret"`
	ExpireHours int    `mapstructure:"expire_hours"`
}

type EncryptionConfig struct {
	Key string `mapstructure:"key"`
}

type EasyPayConfig struct {
	PID      string `mapstructure:"pid"`
	Key      string `mapstructure:"key"`
	Sitename string `mapstructure:"sitename"`
}

type IfdianConfig struct {
	UserID       string `mapstructure:"user_id"`
	Token        string `mapstructure:"token"`
	ClientID     string `mapstructure:"client_id"`
	ClientSecret string `mapstructure:"client_secret"`
}

type DeepSeekConfig struct {
	BaseURL string `mapstructure:"base_url"`
}

type UploadConfig struct {
	MaxSizeMB    int      `mapstructure:"max_size_mb"`
	AllowedTypes []string `mapstructure:"allowed_types"`
}

type CORSConfig struct {
	AllowedOrigins []string `mapstructure:"allowed_origins"`
}

type RateLimitConfig struct {
	GlobalRPS   int `mapstructure:"global_rps"`
	PerIPRPS    int `mapstructure:"per_ip_rps"`
	LoginPerMin int `mapstructure:"login_per_min"`
}

// TLSConfig controls direct HTTPS serving. AutoACME uses Let's Encrypt via
// ACME HTTP-01 or TLS-ALPN-01 and stores certificates only in CacheDir.
type TLSConfig struct {
	Enabled     bool     `mapstructure:"enabled" json:"enabled" yaml:"enabled"`
	Port        int      `mapstructure:"port" json:"port" yaml:"port"`
	CertFile    string   `mapstructure:"cert_file" json:"cert_file" yaml:"cert_file"`
	KeyFile     string   `mapstructure:"key_file" json:"key_file" yaml:"key_file"`
	AutoACME    bool     `mapstructure:"auto_acme" json:"auto_acme" yaml:"auto_acme"`
	ACMEEmail   string   `mapstructure:"acme_email" json:"acme_email" yaml:"acme_email"`
	ACMEDomains []string `mapstructure:"acme_domains" json:"acme_domains" yaml:"acme_domains"`
	CacheDir    string   `mapstructure:"cache_dir" json:"cache_dir" yaml:"cache_dir"`
}

func (c TLSConfig) Validate() error {
	if !c.Enabled {
		return nil
	}
	if c.AutoACME {
		if len(c.ACMEDomains) == 0 {
			return fmt.Errorf("TLS 自动签发至少需要一个 acme_domains")
		}
		if c.CertFile != "" || c.KeyFile != "" {
			return fmt.Errorf("TLS 自动签发不能同时配置 cert_file/key_file")
		}
		return nil
	}
	if strings.TrimSpace(c.CertFile) == "" || strings.TrimSpace(c.KeyFile) == "" {
		return fmt.Errorf("TLS 手工证书必须同时配置 cert_file 和 key_file")
	}
	return nil
}

func NormalizeTLSConfig(c TLSConfig) TLSConfig {
	if c.Port <= 0 {
		c.Port = 443
	}
	if strings.TrimSpace(c.CacheDir) == "" {
		c.CacheDir = "./data/acme"
	}
	c.CertFile = strings.TrimSpace(c.CertFile)
	c.KeyFile = strings.TrimSpace(c.KeyFile)
	c.ACMEEmail = strings.TrimSpace(c.ACMEEmail)
	c.CacheDir = strings.TrimSpace(c.CacheDir)
	domains := make([]string, 0, len(c.ACMEDomains))
	for _, domain := range c.ACMEDomains {
		if domain = strings.ToLower(strings.TrimSpace(domain)); domain != "" {
			domains = append(domains, domain)
		}
	}
	c.ACMEDomains = domains
	return c
}

type NetworkConfig struct {
	BackgroundMinConcurrency int `mapstructure:"background_min_concurrency"`
	BackgroundMaxConcurrency int `mapstructure:"background_max_concurrency"`
	HealthyLatencyMS         int `mapstructure:"healthy_latency_ms"`
	OverloadLatencyMS        int `mapstructure:"overload_latency_ms"`
	UpstreamIdleConns        int `mapstructure:"upstream_idle_conns"`
	UpstreamMaxConnsPerHost  int `mapstructure:"upstream_max_conns_per_host"`
}

func NormalizeNetworkConfig(value NetworkConfig) NetworkConfig {
	value.BackgroundMinConcurrency = min(value.BackgroundMinConcurrency, 1024)
	value.BackgroundMaxConcurrency = min(value.BackgroundMaxConcurrency, 1024)
	value.HealthyLatencyMS = min(value.HealthyLatencyMS, 150000)
	value.OverloadLatencyMS = min(value.OverloadLatencyMS, 300000)
	value.UpstreamIdleConns = min(value.UpstreamIdleConns, 2048)
	value.UpstreamMaxConnsPerHost = min(value.UpstreamMaxConnsPerHost, 2048)
	if value.BackgroundMinConcurrency < 1 {
		value.BackgroundMinConcurrency = 2
	}
	if value.BackgroundMaxConcurrency < value.BackgroundMinConcurrency {
		value.BackgroundMaxConcurrency = max(32, value.BackgroundMinConcurrency)
	}
	if value.HealthyLatencyMS < 100 {
		value.HealthyLatencyMS = 800
	}
	if value.OverloadLatencyMS <= value.HealthyLatencyMS {
		value.OverloadLatencyMS = min(300000, max(3000, value.HealthyLatencyMS*2))
	}
	if value.UpstreamIdleConns < 1 {
		value.UpstreamIdleConns = 32
	}
	if value.UpstreamMaxConnsPerHost < value.UpstreamIdleConns {
		value.UpstreamMaxConnsPerHost = max(64, value.UpstreamIdleConns)
	}
	return value
}

var (
	AppConfig   *Config
	tlsConfigMu sync.RWMutex
)

// EncryptionFallbackKeys 仅用于读取密钥优先级修复前写入的历史密文。
// 新数据始终使用 AppConfig.Encryption.Key。
var EncryptionFallbackKeys []string

// weakJWTSecrets 常见占位/弱 JWT 密钥，命中即拒绝启动
var weakJWTSecrets = []string{
	"change-this-to-a-strong-random-secret",
	"your-secret-key",
	"your-jwt-secret",
	"jwt-secret",
	"secret",
	"changeme",
	"change-me",
}

// ValidateJWTSecret 校验 JWT 签名密钥强度：非空、非占位弱密钥、长度 ≥32 字符。
// 独立成函数便于单元测试；LoadConfig 启动时 fail-fast 调用。
func ValidateJWTSecret(secret string) error {
	s := strings.TrimSpace(secret)
	if s == "" {
		return fmt.Errorf("jwt.secret 为空，请配置至少 32 字符的随机密钥")
	}
	for _, weak := range weakJWTSecrets {
		if strings.EqualFold(s, weak) {
			return fmt.Errorf("jwt.secret 仍是占位/常见弱密钥 %q，必须替换为随机强密钥", weak)
		}
	}
	if len(s) < 32 {
		return fmt.Errorf("jwt.secret 长度不足 32 字符（当前 %d 字符），请使用更长的随机密钥", len(s))
	}
	return nil
}

func LoadConfig(path string) {
	viper.SetConfigFile(path)
	viper.SetConfigType("yaml")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		log.Fatalf("无法读取配置文件: %v", err)
	}

	AppConfig = &Config{}
	if err := viper.Unmarshal(AppConfig); err != nil {
		log.Fatalf("无法解析配置文件: %v", err)
	}
	configuredEncryptionKey := strings.TrimSpace(AppConfig.Encryption.Key)
	EncryptionFallbackKeys = nil

	if AppConfig.RateLimit.PerIPRPS <= 0 {
		AppConfig.RateLimit.PerIPRPS = 100
	}
	if AppConfig.RateLimit.GlobalRPS <= 0 {
		AppConfig.RateLimit.GlobalRPS = 1000
	}
	if AppConfig.RateLimit.LoginPerMin <= 0 {
		AppConfig.RateLimit.LoginPerMin = 10
	}
	AppConfig.Network = NormalizeNetworkConfig(AppConfig.Network)
	AppConfig.TLS = NormalizeTLSConfig(AppConfig.TLS)
	if err := AppConfig.TLS.Validate(); err != nil {
		log.Fatalf("TLS 配置无效，拒绝启动: %v", err)
	}

	// JWT 签名密钥 fail-fast 校验：空/占位/短密钥直接拒绝启动，
	// 避免弱密钥导致任意用户可伪造 JWT。测试不走 LoadConfig，不受影响。
	if err := ValidateJWTSecret(AppConfig.JWT.Secret); err != nil {
		log.Fatalf("JWT 密钥配置不安全，拒绝启动: %v", err)
	}

	// 加密密钥加载优先级：
	// 1. 环境变量 ENCRYPTION_KEY（生产环境推荐，密钥不落盘）
	// 2. 独立密钥文件 .encryption_key（权限 0600，与 config.yaml 分离）
	// 3. config.yaml 中的 encryption.key（向后兼容，但不推荐）
	// 4. 以上都没有 → 自动生成并写入 .encryption_key 文件
	key := loadEncryptionKey(viper.ConfigFileUsed())

	if strings.TrimSpace(key) == "" {
		// 自动生成新密钥
		newKey, err := generateSecureKey(48)
		if err != nil {
			log.Fatalf("生成加密密钥失败: %v", err)
		}
		key = newKey
		AppConfig.Encryption.Key = newKey

		keyFile := encryptionKeyFilePath(viper.ConfigFileUsed())
		if err := os.WriteFile(keyFile, []byte(newKey), 0600); err != nil {
			log.Printf("⚠️ 写入密钥文件 %s 失败: %v", keyFile, err)
			log.Printf("⚠️ 密钥仅本次运行有效，重启后会重新生成，已加密数据将无法解密！")
			// 完整密钥不落日志（集中收集后长期留存等于泄密），只打前 8 位提示
			log.Printf("🔑 本次运行密钥前 8 位: %s...（完整密钥请从运行环境读取，或修复密钥文件写入后重启）", newKey[:8])
		} else {
			log.Println("🔐 已自动生成 48 字符加密密钥")
			log.Printf("✅ 密钥已写入独立文件: %s（权限 0600）", keyFile)
			log.Println("⚠️  config.yaml 可安全提交到 git，但 .encryption_key 必须加入 .gitignore！")
			log.Println("⚠️  生产环境推荐改用环境变量 ENCRYPTION_KEY，密钥不落盘更安全")
			log.Println("⚠️  请妥善备份此密钥！丢失将导致所有已加密数据无法解密。")
		}
		log.Printf("🔑 密钥指纹: %x", md5.Sum([]byte(key[:32])))
	} else if len(key) < 32 {
		log.Printf("⚠️ 安全警告: 加密密钥长度不足 32 字符（当前 %d 字符），用零填充补齐。强烈建议配置 32 字符以上的安全密钥。", len(key))
		key = key + "00000000000000000000000000000000"
		AppConfig.Encryption.Key = key
	} else {
		log.Printf("加密密钥指纹: %x", md5.Sum([]byte(key[:32])))
	}
	// 后续加解密统一从 AppConfig 读取，必须写回按优先级选中的最终密钥。
	AppConfig.Encryption.Key = key
	if configuredEncryptionKey != "" && configuredEncryptionKey != key {
		EncryptionFallbackKeys = append(
			EncryptionFallbackKeys,
			configuredEncryptionKey,
		)
		log.Println("检测到不同的旧配置密钥，已启用历史密文兼容读取")
	}

	log.Println("配置加载成功")
}

// SaveTLSConfig persists non-secret TLS settings to the active YAML file.
// Certificate and private-key contents never pass through this API.
func SaveTLSConfig(value TLSConfig) error {
	value = NormalizeTLSConfig(value)
	if err := value.Validate(); err != nil {
		return err
	}
	tlsConfigMu.Lock()
	defer tlsConfigMu.Unlock()
	viper.Set("tls", value)
	if err := viper.WriteConfig(); err != nil {
		return err
	}
	if AppConfig != nil {
		AppConfig.TLS = value
	}
	return nil
}

// GetTLSConfig returns a copy safe for use by concurrent HTTP handlers.
func GetTLSConfig() TLSConfig {
	tlsConfigMu.RLock()
	defer tlsConfigMu.RUnlock()
	if AppConfig == nil {
		return TLSConfig{}
	}
	value := AppConfig.TLS
	value.ACMEDomains = append([]string(nil), value.ACMEDomains...)
	return value
}

// loadEncryptionKey 按优先级加载加密密钥
func loadEncryptionKey(configPath string) string {
	// 1. 环境变量（最高优先级，生产环境推荐）
	if envKey := strings.TrimSpace(os.Getenv("ENCRYPTION_KEY")); envKey != "" {
		log.Println("🔐 从环境变量 ENCRYPTION_KEY 加载加密密钥")
		return envKey
	}

	// 2. 独立密钥文件 .encryption_key
	keyFile := encryptionKeyFilePath(configPath)
	if data, err := os.ReadFile(keyFile); err == nil {
		if k := strings.TrimSpace(string(data)); k != "" {
			log.Printf("🔐 从密钥文件加载加密密钥: %s", keyFile)
			return k
		}
	}

	// 3. config.yaml 中的 encryption.key（向后兼容）
	if k := strings.TrimSpace(AppConfig.Encryption.Key); k != "" {
		log.Println("⚠️ 从 config.yaml 加载加密密钥（建议迁移到环境变量或独立密钥文件）")
		return k
	}

	return ""
}

// encryptionKeyFilePath 返回密钥文件路径，与 config.yaml 同目录
func encryptionKeyFilePath(configPath string) string {
	dir := filepath.Dir(configPath)
	if dir == "" {
		dir = "."
	}
	return filepath.Join(dir, ".encryption_key")
}

// generateSecureKey 生成加密安全的高强度随机密钥
func generateSecureKey(length int) (string, error) {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		b[i] = charset[n.Int64()]
	}
	return string(b), nil
}
