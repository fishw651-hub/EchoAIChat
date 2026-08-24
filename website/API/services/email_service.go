package services

import (
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

const (
	SMTPAuthNone  = "none"
	SMTPAuthPlain = "plain"

	SMTPTLSNone     = "none"
	SMTPTLSStartTLS = "starttls"
	SMTPTLSSSL      = "ssl"
)

type SMTPConfig struct {
	Host               string
	Port               int
	Username           string
	Password           string
	From               string
	TLSMode            string
	AuthMode           string
	InsecureSkipVerify bool
}

func GetSMTPConfig() *SMTPConfig {
	getVal := func(key string) string {
		var sc models.SystemConfig
		if !database.Get().Register("SystemConfig").FindOne(database.FilterEq("Key", key), &sc) {
			return ""
		}
		return sc.Value
	}

	if cfg := smtpConfigFromStore(getVal); cfg != nil {
		return cfg
	}
	return localSMTPConfigFromEnv(os.Getenv)
}

func smtpConfigFromStore(getVal func(string) string) *SMTPConfig {
	host := strings.TrimSpace(getVal("smtp_host"))
	if host == "" {
		return nil
	}

	port := 587
	fmt.Sscanf(getVal("smtp_port"), "%d", &port)

	password := getVal("smtp_password")
	if password != "" {
		if dec, err := DecryptWithConfiguredKeys(password); err == nil {
			password = dec
		}
	}

	tlsMode := normalizeTLSMode(getVal("smtp_tls_mode"), getVal("smtp_use_tls"), port)
	authMode := normalizeAuthMode(getVal("smtp_auth_mode"), getVal("smtp_username"), password)

	return &SMTPConfig{
		Host:               host,
		Port:               port,
		Username:           strings.TrimSpace(getVal("smtp_username")),
		Password:           password,
		From:               strings.TrimSpace(getVal("smtp_from")),
		TLSMode:            tlsMode,
		AuthMode:           authMode,
		InsecureSkipVerify: isTruthy(getVal("smtp_insecure_skip_verify")),
	}
}

func localSMTPConfigFromEnv(getEnv func(string) string) *SMTPConfig {
	host := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_HOST"))
	portStr := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_PORT"))
	username := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_USERNAME"))
	password := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_PASSWORD"))
	from := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_FROM"))
	tlsModeEnv := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_TLS_MODE"))
	authModeEnv := strings.TrimSpace(getEnv("AICHAT_LOCAL_SMTP_AUTH_MODE"))

	enabled := isTruthy(getEnv("AICHAT_LOCAL_SMTP_ENABLED")) ||
		host != "" || portStr != "" || username != "" || password != "" || from != "" ||
		tlsModeEnv != "" || authModeEnv != ""
	if !enabled {
		return nil
	}

	if host == "" {
		host = "127.0.0.1"
	}

	port := 587
	if portStr != "" {
		fmt.Sscanf(portStr, "%d", &port)
	}

	legacyTLS := "1"
	if strings.EqualFold(tlsModeEnv, SMTPTLSNone) {
		legacyTLS = "0"
	}

	return &SMTPConfig{
		Host:               host,
		Port:               port,
		Username:           username,
		Password:           password,
		From:               from,
		TLSMode:            normalizeTLSMode(tlsModeEnv, legacyTLS, port),
		AuthMode:           normalizeAuthMode(authModeEnv, username, password),
		InsecureSkipVerify: isTruthy(getEnv("AICHAT_LOCAL_SMTP_INSECURE_SKIP_VERIFY")),
	}
}

func SendEmail(to, subject, body string) error {
	cfg := GetSMTPConfig()
	if cfg == nil {
		return fmt.Errorf("SMTP 未配置，请先在后台设置")
	}

	from := cfg.From
	if from == "" {
		from = cfg.Username
	}
	if from == "" {
		return fmt.Errorf("SMTP 发件人不能为空")
	}

	headers := map[string]string{
		"From":         fmt.Sprintf("AIchat <%s>", from),
		"To":           to,
		"Subject":      subject,
		"MIME-Version": "1.0",
		"Content-Type": "text/html; charset=UTF-8",
		"Date":         time.Now().Format(time.RFC1123Z),
	}

	var msg strings.Builder
	for k, v := range headers {
		msg.WriteString(fmt.Sprintf("%s: %s\r\n", k, v))
	}
	msg.WriteString("\r\n")
	msg.WriteString(body)

	return sendSMTP(cfg, from, []string{to}, []byte(msg.String()))
}

func sendSMTP(cfg *SMTPConfig, from string, to []string, msg []byte) error {
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)
	auth, err := buildSMTPAuth(cfg)
	if err != nil {
		return err
	}

	switch cfg.TLSMode {
	case SMTPTLSSSL:
		return sendWithImplicitTLS(cfg, addr, auth, from, to, msg)
	case SMTPTLSStartTLS:
		return sendWithStartTLS(cfg, addr, auth, from, to, msg)
	case SMTPTLSNone:
		return sendPlainSMTP(addr, auth, from, to, msg)
	default:
		return fmt.Errorf("不支持的 SMTP TLS 模式: %s", cfg.TLSMode)
	}
}

func buildSMTPAuth(cfg *SMTPConfig) (smtp.Auth, error) {
	switch cfg.AuthMode {
	case "", SMTPAuthNone:
		return nil, nil
	case SMTPAuthPlain:
		if cfg.Username == "" || cfg.Password == "" {
			return nil, fmt.Errorf("SMTP 认证已启用，但用户名或密码为空")
		}
		return smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host), nil
	default:
		return nil, fmt.Errorf("不支持的 SMTP 认证模式: %s", cfg.AuthMode)
	}
}

func sendWithImplicitTLS(cfg *SMTPConfig, addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	// 带超时的拨号：tls.Dial 无超时，SMTP 服务器挂死会让发信 goroutine 挂住数分钟
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 10 * time.Second}, "tcp", addr, &tls.Config{
		ServerName:         cfg.Host,
		InsecureSkipVerify: cfg.InsecureSkipVerify,
	})
	if err != nil {
		return fmt.Errorf("TLS 连接失败: %v", err)
	}
	defer conn.Close()
	// 整个会话级读写期限（握手后的每条 SMTP 指令都受约束）
	_ = conn.SetDeadline(time.Now().Add(60 * time.Second))

	client, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		return fmt.Errorf("创建 SMTP 客户端失败: %v", err)
	}
	defer client.Close()

	return writeSMTPMessage(client, auth, from, to, msg)
}

// dialSMTPWithTimeout 带拨号超时 + 会话级 deadline 建立 SMTP 客户端
// （smtp.Dial 底层 net.Dial 无任何超时）
func dialSMTPWithTimeout(addr string) (*smtp.Client, error) {
	conn, err := (&net.Dialer{Timeout: 10 * time.Second}).Dial("tcp", addr)
	if err != nil {
		return nil, err
	}
	_ = conn.SetDeadline(time.Now().Add(60 * time.Second))
	host, _, _ := net.SplitHostPort(addr)
	return smtp.NewClient(conn, host)
}

func sendWithStartTLS(cfg *SMTPConfig, addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	client, err := dialSMTPWithTimeout(addr)
	if err != nil {
		return fmt.Errorf("连接 SMTP 服务器失败: %v", err)
	}
	defer client.Close()

	ok, _ := client.Extension("STARTTLS")
	if !ok {
		return fmt.Errorf("SMTP 服务器不支持 STARTTLS")
	}

	if err := client.StartTLS(&tls.Config{
		ServerName:         cfg.Host,
		InsecureSkipVerify: cfg.InsecureSkipVerify,
	}); err != nil {
		return fmt.Errorf("STARTTLS 升级失败: %v", err)
	}

	return writeSMTPMessage(client, auth, from, to, msg)
}

func sendPlainSMTP(addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	client, err := dialSMTPWithTimeout(addr)
	if err != nil {
		return fmt.Errorf("连接 SMTP 服务器失败: %v", err)
	}
	defer client.Close()

	return writeSMTPMessage(client, auth, from, to, msg)
}

func writeSMTPMessage(client *smtp.Client, auth smtp.Auth, from string, to []string, msg []byte) error {
	if auth != nil {
		if err := client.Auth(auth); err != nil {
			return fmt.Errorf("SMTP 认证失败: %v", err)
		}
	}
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("设置发件人失败: %v", err)
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return fmt.Errorf("设置收件人失败: %v", err)
		}
	}

	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("打开 DATA 失败: %v", err)
	}
	if _, err = w.Write(msg); err != nil {
		_ = w.Close()
		return fmt.Errorf("写入邮件内容失败: %v", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("关闭 DATA 失败: %v", err)
	}
	if err = client.Quit(); err != nil {
		return fmt.Errorf("提交邮件失败: %v", err)
	}

	log.Printf("[邮件] 成功发送到 %v", to)
	return nil
}

func normalizeTLSMode(mode, legacyUseTLS string, port int) string {
	mode = strings.ToLower(strings.TrimSpace(mode))
	switch mode {
	case SMTPTLSNone, SMTPTLSStartTLS, SMTPTLSSSL:
		return mode
	}

	if legacyUseTLS == "0" {
		return SMTPTLSNone
	}
	if port == 465 {
		return SMTPTLSSSL
	}
	return SMTPTLSStartTLS
}

func normalizeAuthMode(mode, username, password string) string {
	mode = strings.ToLower(strings.TrimSpace(mode))
	switch mode {
	case SMTPAuthNone, SMTPAuthPlain:
		return mode
	}

	if strings.TrimSpace(username) != "" || strings.TrimSpace(password) != "" {
		return SMTPAuthPlain
	}
	return SMTPAuthNone
}

func isTruthy(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

const (
	codeTTL = 10 * time.Minute

	emailAppNameKey             = "email_app_name"
	emailCodeRegisterSubjectKey = "email_code_register_subject"
	emailCodeRegisterBodyKey    = "email_code_register_body"
	emailCodeResetSubjectKey    = "email_code_reset_subject"
	emailCodeResetBodyKey       = "email_code_reset_body"

	defaultEmailAppName = "AIchat"
)

type emailCode struct {
	code      string
	expiresAt time.Time
	purpose   string
}

var (
	codeStore   = map[string]*emailCode{}
	codeStoreMu sync.RWMutex
)

func GenerateAndSendCode(email, purpose string) error {
	code, err := generateVerificationCode()
	if err != nil {
		return fmt.Errorf("生成验证码失败: %w", err)
	}

	// 频率限制检查与验证码写入在同一把 Lock 内完成，避免 TOCTOU 并发发送多个验证码
	codeStoreMu.Lock()
	if existing, ok := codeStore[email]; ok {
		if time.Since(existing.expiresAt.Add(-codeTTL)) < 60*time.Second {
			codeStoreMu.Unlock()
			return fmt.Errorf("发送过于频繁，请稍后再试")
		}
	}
	codeStore[email] = &emailCode{
		code:      code,
		expiresAt: time.Now().Add(codeTTL),
		purpose:   purpose,
	}
	codeStoreMu.Unlock()

	subject, body := renderVerificationEmail(purpose, code, systemConfigValue)
	return SendEmail(email, subject, body)
}

func generateVerificationCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%012d", n.Int64()), nil
}

func systemConfigValue(key string) string {
	var sc models.SystemConfig
	if !database.Get().Register("SystemConfig").FindOne(database.FilterEq("Key", key), &sc) {
		return ""
	}
	return sc.Value
}

func renderVerificationEmail(purpose, code string, getVal func(string) string) (string, string) {
	appName := strings.TrimSpace(getVal(emailAppNameKey))
	if appName == "" {
		appName = defaultEmailAppName
	}

	subjectKey := emailCodeRegisterSubjectKey
	bodyKey := emailCodeRegisterBodyKey
	subjectTemplate := "{{app_name}} verification code"
	bodyTemplate := defaultVerificationBodyTemplate("Your registration verification code is:")
	if purpose == "reset" {
		subjectKey = emailCodeResetSubjectKey
		bodyKey = emailCodeResetBodyKey
		subjectTemplate = "{{app_name}} password reset code"
		bodyTemplate = defaultVerificationBodyTemplate("Your password reset verification code is:")
	}

	if customSubject := strings.TrimSpace(getVal(subjectKey)); customSubject != "" {
		subjectTemplate = customSubject
	}
	if customBody := strings.TrimSpace(getVal(bodyKey)); customBody != "" {
		bodyTemplate = customBody
	}

	vars := map[string]string{
		"app_name":    appName,
		"code":        code,
		"purpose":     purpose,
		"ttl_minutes": strconv.Itoa(int(codeTTL / time.Minute)),
	}

	return replaceEmailTemplateVars(subjectTemplate, vars), replaceEmailTemplateVars(bodyTemplate, vars)
}

func replaceEmailTemplateVars(tpl string, vars map[string]string) string {
	out := tpl
	for key, val := range vars {
		out = strings.ReplaceAll(out, "{{"+key+"}}", val)
	}
	return out
}

func defaultVerificationBodyTemplate(description string) string {
	return `<html><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f5f7;padding:40px 0;margin:0">
<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 20px rgba(0,0,0,.08)">
<div style="background:#4A6CF7;padding:24px 32px;color:#fff">
<h1 style="margin:0;font-size:20px;font-weight:600">{{app_name}}</h1>
<p style="margin:4px 0 0;font-size:13px;opacity:.9">Account security</p>
</div>
<div style="padding:32px">
<p style="margin:0 0 16px;color:#333;font-size:14px;line-height:1.6">` + description + `</p>
<div style="background:#f5f5f7;border-radius:8px;padding:20px;text-align:center;margin:0 0 16px">
<span style="font-size:32px;font-weight:700;letter-spacing:6px;color:#4A6CF7">{{code}}</span>
</div>
<p style="margin:0 0 8px;color:#666;font-size:13px;line-height:1.6">This code expires in {{ttl_minutes}} minutes.</p>
<p style="margin:0;color:#999;font-size:12px;line-height:1.6">If this was not you, ignore this email.</p>
</div>
</div>
</body></html>`
}

// VerifyCode 单次写锁内完成"读取-比对-删除"：拆成 RLock+Lock 两段会让
// 两个并发请求同时通过同一验证码（TOCTOU 双花）。
func VerifyCode(email, code, purpose string) bool {
	codeStoreMu.Lock()
	defer codeStoreMu.Unlock()
	stored, ok := codeStore[email]
	if !ok {
		return false
	}
	if stored.purpose != purpose {
		return false
	}
	if time.Now().After(stored.expiresAt) {
		delete(codeStore, email)
		return false
	}
	if stored.code != code {
		return false
	}

	delete(codeStore, email)
	return true
}

func init() {
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			now := time.Now()
			codeStoreMu.Lock()
			for k, v := range codeStore {
				if now.After(v.expiresAt) {
					delete(codeStore, k)
				}
			}
			codeStoreMu.Unlock()
		}
	}()
}
