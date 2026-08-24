package handlers

import (
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"aichat-api/config"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type EmailHandler struct{}

const (
	emailAppNameConfigKey             = "email_app_name"
	emailCodeRegisterSubjectConfigKey = "email_code_register_subject"
	emailCodeRegisterBodyConfigKey    = "email_code_register_body"
	emailCodeResetSubjectConfigKey    = "email_code_reset_subject"
	emailCodeResetBodyConfigKey       = "email_code_reset_body"
)

func isSMTPConfigured(host, username, from, password string) bool {
	return strings.TrimSpace(host) != "" ||
		strings.TrimSpace(username) != "" ||
		strings.TrimSpace(from) != "" ||
		strings.TrimSpace(password) != ""
}

type SendCodeRequest struct {
	Email   string `json:"email" binding:"required"`
	Purpose string `json:"purpose" binding:"required"`
}

func (h *EmailHandler) SendCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.email.param_error"))
		return
	}

	if !utils.IsValidEmail(req.Email) {
		utils.BadRequest(c, utils.T(c, "err.auth.email_invalid"))
		return
	}
	if req.Purpose != "register" && req.Purpose != "reset" {
		utils.BadRequest(c, utils.T(c, "err.email.purpose_invalid"))
		return
	}

	if req.Purpose == "register" {
		if existing, err := services.FindUserByEmail(req.Email); err == nil && existing != nil {
			utils.BadRequest(c, utils.T(c, "err.email.already_registered"))
			return
		}
	}

	if req.Purpose == "reset" {
		existing, err := services.FindUserByEmail(req.Email)
		if err != nil || existing == nil {
			utils.BadRequest(c, utils.T(c, "err.email.not_registered"))
			return
		}
	}

	if err := services.GenerateAndSendCode(req.Email, req.Purpose); err != nil {
		log.Printf("[邮件] 发送验证码失败 email=%s purpose=%s err=%v", utils.MaskEmail(req.Email), req.Purpose, err)
		utils.BadRequest(c, utils.T(c, "err.email.send_failed"))
		return
	}

	log.Printf("[邮件] 验证码发送成功 email=%s purpose=%s", utils.MaskEmail(req.Email), req.Purpose)
	utils.SuccessMsg(c, utils.T(c, "ok.email.code_sent"))
}

type RegisterWithCodeRequest struct {
	Username string `json:"username" binding:"required,min=3,max=64"`
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required,min=6,max=128"`
	Code     string `json:"code" binding:"required,len=12"`
}

func (h *EmailHandler) RegisterWithCode(c *gin.Context) {
	var req RegisterWithCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.TP(c, "err.email.param_error_detail", map[string]string{"detail": err.Error()}))
		return
	}

	if !utils.IsValidEmail(req.Email) {
		utils.BadRequest(c, utils.T(c, "err.auth.email_invalid"))
		return
	}
	if !services.VerifyCode(req.Email, req.Code, "register") {
		utils.BadRequest(c, utils.T(c, "err.email.code_invalid"))
		return
	}

	authService := &services.AuthService{}
	user, err := authService.Register(req.Username, req.Email, req.Password)
	if err != nil {
		utils.BadRequest(c, translateAuthServiceErr(c, err))
		return
	}

	utils.Success(c, gin.H{
		"id":       user.ID,
		"username": user.Username,
		"nickname": user.Nickname,
	})
}

type ResetPasswordRequest struct {
	Email    string `json:"email" binding:"required"`
	Code     string `json:"code" binding:"required,len=12"`
	Password string `json:"password" binding:"required,min=6,max=128"`
}

func (h *EmailHandler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.email.param_error"))
		return
	}

	if !utils.IsValidEmail(req.Email) {
		utils.BadRequest(c, utils.T(c, "err.auth.email_invalid"))
		return
	}
	if !services.VerifyCode(req.Email, req.Code, "reset") {
		utils.BadRequest(c, utils.T(c, "err.email.code_invalid"))
		return
	}

	user, err := services.FindUserByEmail(req.Email)
	if err != nil || user == nil {
		utils.BadRequest(c, utils.T(c, "err.auth.user_not_found_short"))
		return
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.auth.bcrypt_failed"))
		return
	}

	services.UpdateUserByID(user.ID, map[string]interface{}{
		"PasswordHash": string(hashed),
		// 递增令牌版本：重置密码后旧 token 立即失效
		"TokenVersion": user.TokenVersion + 1,
	})

	log.Printf("[用户] 密码重置成功 email=%s id=%d", utils.MaskEmail(req.Email), user.ID)
	utils.SuccessMsg(c, utils.T(c, "ok.email.password_reset"))
}

func (h *EmailHandler) GetSMTPConfig(c *gin.Context) {
	getVal := func(key string) string {
		if sc, err := services.FindSystemConfig(key); err == nil && sc != nil {
			return sc.Value
		}
		return ""
	}

	effectiveCfg := services.GetSMTPConfig()

	pwdDisplay := "未配置"
	if getVal("smtp_password") != "" {
		pwdDisplay = "**** (已加密保存)"
	}

	tlsMode := strings.ToLower(strings.TrimSpace(getVal("smtp_tls_mode")))
	if tlsMode == "" {
		tlsMode = services.SMTPTLSStartTLS
		if getVal("smtp_use_tls") == "0" {
			tlsMode = services.SMTPTLSNone
		} else if strings.TrimSpace(getVal("smtp_port")) == "465" {
			tlsMode = services.SMTPTLSSSL
		}
	}

	authMode := strings.ToLower(strings.TrimSpace(getVal("smtp_auth_mode")))
	if authMode == "" {
		if strings.TrimSpace(getVal("smtp_username")) != "" || getVal("smtp_password") != "" {
			authMode = services.SMTPAuthPlain
		} else {
			authMode = services.SMTPAuthNone
		}
	}

	utils.Success(c, gin.H{
		"host":                 getVal("smtp_host"),
		"port":                 getVal("smtp_port"),
		"username":             getVal("smtp_username"),
		"password":             pwdDisplay,
		"from":                 getVal("smtp_from"),
		"use_tls":              tlsMode != services.SMTPTLSNone,
		"tls_mode":             tlsMode,
		"auth_mode":            authMode,
		"insecure_skip_verify": getVal("smtp_insecure_skip_verify") == "1",
		"configured":           isSMTPConfigured(getVal("smtp_host"), getVal("smtp_username"), getVal("smtp_from"), getVal("smtp_password")) || effectiveCfg != nil,
	})
}

type UpdateSMTPConfigRequest struct {
	Host               string `json:"host"`
	Port               string `json:"port"`
	Username           string `json:"username"`
	Password           string `json:"password"`
	From               string `json:"from"`
	UseTLS             *bool  `json:"use_tls"`
	TLSMode            string `json:"tls_mode"`
	AuthMode           string `json:"auth_mode"`
	InsecureSkipVerify *bool  `json:"insecure_skip_verify"`
}

func (h *EmailHandler) UpdateSMTPConfig(c *gin.Context) {
	var req UpdateSMTPConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.email.param_error"))
		return
	}

	tlsMode := strings.ToLower(strings.TrimSpace(req.TLSMode))
	switch tlsMode {
	case "", services.SMTPTLSNone, services.SMTPTLSStartTLS, services.SMTPTLSSSL:
	default:
		utils.BadRequest(c, utils.T(c, "err.email.tls_unsupported"))
		return
	}
	if tlsMode == "" {
		if req.UseTLS != nil && !*req.UseTLS {
			tlsMode = services.SMTPTLSNone
		} else if strings.TrimSpace(req.Port) == "465" {
			tlsMode = services.SMTPTLSSSL
		} else {
			tlsMode = services.SMTPTLSStartTLS
		}
	}

	authMode := strings.ToLower(strings.TrimSpace(req.AuthMode))
	switch authMode {
	case "", services.SMTPAuthNone, services.SMTPAuthPlain:
	default:
		utils.BadRequest(c, utils.T(c, "err.email.smtp_auth_unsupported"))
		return
	}
	if authMode == "" {
		if strings.TrimSpace(req.Username) != "" || req.Password != "" {
			authMode = services.SMTPAuthPlain
		} else {
			authMode = services.SMTPAuthNone
		}
	}

	saveSMTPConfig := func(key, value, desc string) {
		_ = services.SaveSystemConfig(key, value, desc)
	}
	saveSMTPConfig("smtp_host", req.Host, "SMTP 服务器地址")
	saveSMTPConfig("smtp_port", req.Port, "SMTP 端口")
	saveSMTPConfig("smtp_username", req.Username, "SMTP 用户名")
	saveSMTPConfig("smtp_from", req.From, "发件人邮箱")

	if req.Password != "" {
		encPwd, err := services.Encrypt(req.Password, services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key))
		if err != nil {
			utils.Internal(c, utils.T(c, "err.email.password_encrypt_failed"))
			return
		}
		saveSMTPConfig("smtp_password", encPwd, "SMTP 密码(已加密)")
	}

	useTLSVal := "1"
	if tlsMode == services.SMTPTLSNone {
		useTLSVal = "0"
	}
	saveSMTPConfig("smtp_use_tls", useTLSVal, "是否使用 TLS")
	saveSMTPConfig("smtp_tls_mode", tlsMode, "SMTP TLS 模式")
	saveSMTPConfig("smtp_auth_mode", authMode, "SMTP 认证模式")

	insecureSkipVerifyVal := "0"
	if req.InsecureSkipVerify != nil && *req.InsecureSkipVerify {
		insecureSkipVerifyVal = "1"
	}
	saveSMTPConfig("smtp_insecure_skip_verify", insecureSkipVerifyVal, "是否跳过 SMTP 证书校验")

	log.Printf("[管理后台] SMTP 配置已更新 host=%s tls_mode=%s auth_mode=%s", req.Host, tlsMode, authMode)
	utils.SuccessMsg(c, "SMTP 配置保存成功")
}

func (h *EmailHandler) GetEmailTemplates(c *gin.Context) {
	getVal := func(key string) string {
		if sc, err := services.FindSystemConfig(key); err == nil && sc != nil {
			return sc.Value
		}
		return ""
	}

	utils.Success(c, gin.H{
		"app_name":         getVal(emailAppNameConfigKey),
		"register_subject": getVal(emailCodeRegisterSubjectConfigKey),
		"register_body":    getVal(emailCodeRegisterBodyConfigKey),
		"reset_subject":    getVal(emailCodeResetSubjectConfigKey),
		"reset_body":       getVal(emailCodeResetBodyConfigKey),
	})
}

type UpdateEmailTemplatesRequest struct {
	AppName         string `json:"app_name"`
	RegisterSubject string `json:"register_subject"`
	RegisterBody    string `json:"register_body"`
	ResetSubject    string `json:"reset_subject"`
	ResetBody       string `json:"reset_body"`
}

func (h *EmailHandler) UpdateEmailTemplates(c *gin.Context) {
	var req UpdateEmailTemplatesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	_ = services.SaveSystemConfig(emailAppNameConfigKey, strings.TrimSpace(req.AppName), "邮件显示应用名称")
	_ = services.SaveSystemConfig(emailCodeRegisterSubjectConfigKey, strings.TrimSpace(req.RegisterSubject), "注册验证码邮件标题模板")
	_ = services.SaveSystemConfig(emailCodeRegisterBodyConfigKey, req.RegisterBody, "注册验证码邮件正文模板")
	_ = services.SaveSystemConfig(emailCodeResetSubjectConfigKey, strings.TrimSpace(req.ResetSubject), "重置密码验证码邮件标题模板")
	_ = services.SaveSystemConfig(emailCodeResetBodyConfigKey, req.ResetBody, "重置密码验证码邮件正文模板")

	utils.SuccessMsg(c, "验证码邮件模板已保存")
}

type SendNotificationEmailRequest struct {
	Mode    string      `json:"mode"`
	Email   string      `json:"email"`
	UserIDs interface{} `json:"user_ids"`
	Subject string      `json:"subject"`
	Body    string      `json:"body"`
}

type notificationRecipient struct {
	UserID uint
	Email  string
	Name   string
}

type notificationFailure struct {
	UserID uint   `json:"user_id,omitempty"`
	Email  string `json:"email"`
	Error  string `json:"error"`
}

func (h *EmailHandler) SendNotificationEmail(c *gin.Context) {
	var req SendNotificationEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	mode := strings.TrimSpace(req.Mode)
	if mode == "" {
		mode = "single"
	}
	subject := strings.TrimSpace(req.Subject)
	body := strings.TrimSpace(req.Body)
	if subject == "" || body == "" {
		utils.BadRequest(c, "邮件标题和正文不能为空")
		return
	}

	recipients, failed := h.resolveNotificationRecipients(mode, req)
	if len(recipients) == 0 {
		utils.BadRequest(c, "没有可发送的收件人")
		return
	}

	sentCount := 0
	failedCount := len(failed)
	for _, recipient := range recipients {
		if err := services.SendEmail(recipient.Email, subject, body); err != nil {
			failedCount++
			failed = appendLimitedNotificationFailure(failed, notificationFailure{
				UserID: recipient.UserID,
				Email:  recipient.Email,
				Error:  err.Error(),
			})
			continue
		}
		sentCount++
	}

	utils.Success(c, gin.H{
		"sent_count":   sentCount,
		"failed_count": failedCount,
		"failed":       failed,
	})
}

func (h *EmailHandler) resolveNotificationRecipients(mode string, req SendNotificationEmailRequest) ([]notificationRecipient, []notificationFailure) {
	switch mode {
	case "single":
		email := strings.TrimSpace(req.Email)
		if email == "" || !utils.IsValidEmail(email) {
			return nil, []notificationFailure{{Email: email, Error: "邮箱格式不正确"}}
		}
		return []notificationRecipient{{Email: email}}, nil
	case "users":
		userIDs, err := parseNotifyUserIDs(req.UserIDs)
		if err != nil {
			return nil, []notificationFailure{{Error: err.Error()}}
		}
		return notificationRecipientsByIDs(userIDs)
	case "all":
		return allActiveNotificationRecipients(), nil
	default:
		return nil, []notificationFailure{{Error: "发送范围不支持"}}
	}
}

func parseNotifyUserIDs(raw interface{}) ([]uint, error) {
	values := make([]string, 0)
	switch v := raw.(type) {
	case []string:
		values = v
	case []interface{}:
		for _, item := range v {
			values = append(values, fmt.Sprintf("%v", item))
		}
	case nil:
	default:
		return nil, fmt.Errorf("用户 ID 格式不正确")
	}

	ids := make([]uint, 0, len(values))
	for _, item := range values {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		id, err := strconv.ParseUint(item, 10, 64)
		if err != nil || id == 0 {
			return nil, fmt.Errorf("无效用户 ID: %s", item)
		}
		ids = append(ids, uint(id))
	}
	if len(ids) == 0 {
		return nil, fmt.Errorf("请填写用户 ID")
	}
	return ids, nil
}

func notificationRecipientsByIDs(userIDs []uint) ([]notificationRecipient, []notificationFailure) {
	recipients := make([]notificationRecipient, 0, len(userIDs))
	var failed []notificationFailure
	for _, id := range userIDs {
		user, err := services.FindUserByID(id)
		if err != nil || user == nil {
			failed = appendLimitedNotificationFailure(failed, notificationFailure{UserID: id, Error: "用户不存在"})
			continue
		}
		addNotificationRecipient(&recipients, &failed, *user)
	}
	return recipients, failed
}

func allActiveNotificationRecipients() []notificationRecipient {
	allUsers := services.ListUsers("")
	recipients := make([]notificationRecipient, 0, len(allUsers))
	for _, user := range allUsers {
		if user.Status == 0 {
			continue
		}
		if strings.TrimSpace(user.Email) == "" || !utils.IsValidEmail(user.Email) {
			continue
		}
		recipients = append(recipients, notificationRecipient{
			UserID: user.ID,
			Email:  strings.TrimSpace(user.Email),
			Name:   user.Username,
		})
	}
	return recipients
}

func addNotificationRecipient(recipients *[]notificationRecipient, failed *[]notificationFailure, user models.User) {
	email := strings.TrimSpace(user.Email)
	if email == "" || !utils.IsValidEmail(email) {
		*failed = appendLimitedNotificationFailure(*failed, notificationFailure{UserID: user.ID, Email: email, Error: "用户邮箱无效"})
		return
	}
	*recipients = append(*recipients, notificationRecipient{
		UserID: user.ID,
		Email:  email,
		Name:   user.Username,
	})
}

func appendLimitedNotificationFailure(failed []notificationFailure, item notificationFailure) []notificationFailure {
	if len(failed) >= 20 {
		return failed
	}
	return append(failed, item)
}

func (h *EmailHandler) TestSMTP(c *gin.Context) {
	var req struct {
		To string `json:"to" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "请输入收件邮箱")
		return
	}

	if !utils.IsValidEmail(req.To) {
		utils.BadRequest(c, "收件邮箱格式不正确")
		return
	}

	subject := "[AIchat] SMTP 配置测试"
	body := fmt.Sprintf(`<html><body style="font-family:-apple-system,sans-serif;padding:40px">
<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:12px;padding:32px">
<h2 style="color:#4A6CF7;margin:0 0 16px">SMTP 配置测试成功</h2>
<p style="color:#666;font-size:14px;line-height:1.6">如果您收到此邮件，说明 SMTP 配置已生效。</p>
<p style="color:#999;font-size:12px;margin-top:24px">发送时间: %s</p>
</div>
</body></html>`, time.Now().Format("2006-01-02 15:04:05"))

	if err := services.SendEmail(req.To, subject, body); err != nil {
		log.Printf("[管理后台] SMTP 测试失败 to=%s err=%v", utils.MaskEmail(req.To), err)
		utils.BadRequest(c, "测试发送失败，请检查 SMTP 配置")
		return
	}

	utils.SuccessMsg(c, "测试邮件已发送，请查收")
}
