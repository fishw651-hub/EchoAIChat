package utils

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// messages 是后端 API 响应文案的多语言表。
// 键命名规范：err.<category>.<description>（错误）/ ok.<category>.<description>（成功）。
// 缺失键或缺失语言时回退顺序：lang → "zh" → key 本身。
var messages = map[string]map[string]string{
	// ─── auth（认证 / 账户） ───────────────────────────
	"err.auth.login_required":        {"zh": "请先登录", "en": "Please log in first"},
	"err.auth.bad_format":            {"zh": "认证格式错误", "en": "Invalid authentication format"},
	"err.auth.token_expired":         {"zh": "登录已过期，请重新登录", "en": "Login has expired, please log in again"},
	"err.auth.account_disabled":     {"zh": "账户不存在或已被禁用", "en": "Account does not exist or has been disabled"},
	"err.auth.status_changed":       {"zh": "登录状态已变更，请重新登录", "en": "Login status has changed, please log in again"},
	"err.auth.refresh_token_invalid": {"zh": "refresh_token 无效或已过期", "en": "refresh_token is invalid or expired"},
	"err.auth.user_not_found":        {"zh": "用户不存在或已被禁用", "en": "User does not exist or has been disabled"},
	"err.auth.user_not_found_short":  {"zh": "用户不存在", "en": "User does not exist"},
	"err.auth.generate_token_failed": {"zh": "生成 token 失败", "en": "Failed to generate token"},
	"err.auth.register_taken":        {"zh": "用户名或邮箱已被注册", "en": "Username or email has already been registered"},
	"err.auth.bcrypt_failed":         {"zh": "密码加密失败", "en": "Password encryption failed"},
	"err.email.password_encrypt_failed": {"zh": "密码加密失败", "en": "Password encryption failed"},
	"err.auth.register_failed":       {"zh": "注册失败", "en": "Registration failed"},
	"err.auth.wrong_credentials":     {"zh": "用户名或密码错误", "en": "Incorrect username or password"},
	"err.auth.account_banned":        {"zh": "账户已被禁用", "en": "Account has been disabled"},
	"err.auth.generate_token_short":  {"zh": "生成token失败", "en": "Failed to generate token"},
	"err.auth.old_password_wrong":    {"zh": "原密码错误", "en": "Old password is incorrect"},
	"ok.auth.password_changed":       {"zh": "密码修改成功", "en": "Password changed successfully"},
	"ok.auth.profile_updated":       {"zh": "信息更新成功", "en": "Profile updated successfully"},
	"err.auth.no_update_fields":      {"zh": "没有需要更新的字段", "en": "No fields to update"},
	"err.auth.avatar_required":       {"zh": "请选择头像文件", "en": "Please select an avatar file"},
	"err.auth.read_file_failed":      {"zh": "读取文件失败", "en": "Failed to read file"},
	"err.auth.upload_failed":         {"zh": "上传失败", "en": "Upload failed"},
	"err.auth.device_id_required":    {"zh": "缺少 device_id", "en": "device_id is required"},
	"err.auth.param_error":           {"zh": "参数错误", "en": "Invalid parameters"},
	"err.auth.param_error_detail":    {"zh": "参数错误: ", "en": "Invalid parameters: "},
	"err.auth.email_invalid":         {"zh": "邮箱格式不正确", "en": "Invalid email format"},
	"err.auth.admin_required":        {"zh": "需要管理员权限", "en": "Administrator privileges required"},
	"err.auth.super_admin_required":  {"zh": "需要超级管理员权限", "en": "Super administrator privileges required"},

	// ─── email（邮箱验证码 / SMTP） ────────────────────
	"err.email.purpose_invalid":      {"zh": "用途参数错误", "en": "Invalid purpose parameter"},
	"err.email.already_registered":   {"zh": "该邮箱已被注册", "en": "This email has already been registered"},
	"err.email.not_registered":       {"zh": "该邮箱未注册", "en": "This email is not registered"},
	"err.email.send_failed":          {"zh": "验证码发送失败，请稍后重试", "en": "Failed to send verification code, please try again later"},
	"ok.email.code_sent":            {"zh": "验证码已发送", "en": "Verification code has been sent"},
	"err.email.code_invalid":        {"zh": "验证码错误或已过期", "en": "Verification code is incorrect or expired"},
	"err.email.tls_unsupported":     {"zh": "TLS 模式不支持", "en": "TLS mode is not supported"},
	"err.email.smtp_auth_unsupported": {"zh": "SMTP 认证模式不支持", "en": "SMTP authentication mode is not supported"},
	"ok.email.smtp_saved":           {"zh": "SMTP 配置保存成功", "en": "SMTP configuration saved successfully"},
	"ok.email.template_saved":       {"zh": "验证码邮件模板已保存", "en": "Email verification template saved"},
	"err.email.recipient_required":  {"zh": "请输入收件邮箱", "en": "Please enter a recipient email"},
	"err.email.recipient_invalid":   {"zh": "收件邮箱格式不正确", "en": "Invalid recipient email format"},
	"err.email.test_send_failed":    {"zh": "测试发送失败，请检查 SMTP 配置", "en": "Test send failed, please check SMTP configuration"},
	"ok.email.test_sent":            {"zh": "测试邮件已发送，请查收", "en": "Test email has been sent, please check your inbox"},
	"err.email.subject_body_empty":  {"zh": "邮件标题和正文不能为空", "en": "Email subject and body cannot be empty"},
	"err.email.no_recipients":       {"zh": "没有可发送的收件人", "en": "No recipients to send to"},
	"ok.email.password_reset":       {"zh": "密码重置成功", "en": "Password has been reset successfully"},

	// ─── chat（聊天 / 计费） ───────────────────────────
	"err.chat.agent_not_owned":        {"zh": "智能体不属于当前账号", "en": "Agent does not belong to this account"},
	"err.chat.proactive_claim_invalid": {"zh": "主动关心 claim 无效", "en": "Invalid proactive care claim"},
	"err.chat.model_not_allowed":     {"zh": "当前订阅不支持模型 {model}", "en": "Current subscription does not support model {model}"},
	"err.chat.reserve_failed":        {"zh": "计费预留失败", "en": "Billing reservation failed"},
	"err.chat.real_reply_reserve_failed": {"zh": "真实回复配额预留失败", "en": "Failed to reserve real-reply quota"},
	"err.chat.upstream_failed":       {"zh": "上游请求失败", "en": "Upstream request failed"},
	"err.chat.upstream_empty":        {"zh": "上游返回空响应", "en": "Upstream returned an empty response"},
	"err.chat.settle_failed":         {"zh": "计费结算失败", "en": "Billing settlement failed"},
	"err.chat.real_reply_commit_failed": {"zh": "真实回复配额提交失败", "en": "Failed to commit real-reply quota"},
	"err.chat.upstream_rate_limited": {"zh": "上游请求过于频繁，请稍后重试", "en": "Upstream is rate limited, please try again later"},
	"err.chat.upstream_unavailable":  {"zh": "上游服务暂时不可用，请稍后重试", "en": "Upstream service is temporarily unavailable, please try again later"},

	// ─── payment（支付） ───────────────────────────────
	"err.payment.provider_not_easypay": {"zh": "当前支付渠道非易支付，请在后台切换", "en": "Current payment provider is not EasyPay, please switch in the admin panel"},
	"err.payment.type_unsupported":     {"zh": "不支持的支付方式", "en": "Unsupported payment method"},
	"err.payment.order_not_found":      {"zh": "订单不存在", "en": "Order does not exist"},
	"err.payment.order_forbidden":      {"zh": "无权查看该订单", "en": "You are not allowed to view this order"},
	"err.payment.topup_offline":        {"zh": "余额充值已下线，请购买订阅", "en": "Balance top-up is offline, please purchase a subscription"},

	// ─── payment result page（支付结果页） ──────────────
	"ok.payment.success":        {"zh": "支付成功", "en": "Payment Successful"},
	"ok.payment.success_guide":  {"zh": "请返回APP，刷新余额即可看到变化", "en": "Please return to the app and refresh to see the balance change"},
	"ok.payment.failed":         {"zh": "支付失败", "en": "Payment Failed"},
	"ok.payment.failed_guide":   {"zh": "请返回APP重新发起支付", "en": "Please return to the app and try again"},
	"ok.payment.page_title":     {"zh": "支付结果", "en": "Payment Result"},
	"ok.payment.order_label":    {"zh": "订单", "en": "Order"},
	"ok.payment.goods_label":    {"zh": "商品", "en": "Product"},
	"ok.payment.amount_label":   {"zh": "金额", "en": "Amount"},
	"ok.payment.close_page":     {"zh": "关闭页面", "en": "Close"},

	// ─── sync（多端同步 / v2 / 设备） ───────────────────
	"err.sync.subscription_required": {"zh": "多端同步仅订阅用户可用", "en": "Multi-device sync is only available to subscribers"},
	"err.sync.invalid_table":          {"zh": "无效的表名", "en": "Invalid table name"},
	"err.sync.write_failed":           {"zh": "同步写入失败，请重试", "en": "Sync write failed, please try again"},
	"ok.sync.tombstones_cleared":      {"zh": "墓碑已清空", "en": "Tombstones cleared"},
	"err.sync.scope_mode_invalid":     {"zh": "scope_mode 必须是 all 或 selected", "en": "scope_mode must be all or selected"},
	"err.sync.selected_ids_required":  {"zh": "selected_agent_ids 不能为空", "en": "selected_agent_ids cannot be empty"},
	"err.sync.too_many_agents":        {"zh": "单次同步智能体数量过多", "en": "Too many agents in a single sync"},
	"err.sync.param_error":            {"zh": "参数错误", "en": "Invalid parameters"},
	"err.sync.generate_preview_failed": {"zh": "生成同步预览失败", "en": "Failed to generate sync preview"},
	"err.sync.data_invalid":           {"zh": "同步数据无效", "en": "Invalid sync data"},
	"err.sync.preview_token_required": {"zh": "preview_token 不能为空", "en": "preview_token is required"},
	"err.sync.run_failed":            {"zh": "执行同步失败", "en": "Failed to execute sync"},
	"err.sync.mode_invalid":           {"zh": "mode 必须是 immediate 或 one_shot", "en": "mode must be immediate or one_shot"},
	"err.sync.device_not_registered":  {"zh": "设备未注册", "en": "Device is not registered"},
	"err.sync.policy_read_failed":     {"zh": "读取同步策略失败", "en": "Failed to read sync policy"},
	"err.sync.policy_changed":         {"zh": "同步策略已变化", "en": "Sync policy has changed"},
	"err.sync.policy_update_failed":   {"zh": "更新同步策略失败", "en": "Failed to update sync policy"},
	"err.sync.setting_read_failed":    {"zh": "读取同步设置失败", "en": "Failed to read sync settings"},
	"err.sync.setting_update_failed":  {"zh": "更新同步设置失败", "en": "Failed to update sync settings"},
	"err.sync.policy_conflict":        {"zh": "同步策略已在其他设备更新", "en": "Sync policy has been updated on another device"},
	"err.sync.policy_invalid":         {"zh": "无效的同步策略", "en": "Invalid sync policy"},

	// ─── device（设备管理） ─────────────────────────────
	"err.device.query_failed":         {"zh": "查询设备失败", "en": "Failed to query devices"},
	"err.device.update_failed":        {"zh": "更新设备失败", "en": "Failed to update device"},
	"err.device.register_failed":      {"zh": "注册设备失败", "en": "Failed to register device"},
	"err.device.role_invalid":         {"zh": "role 必须是 master 或 slave", "en": "role must be master or slave"},
	"err.device.not_found":            {"zh": "设备不存在", "en": "Device does not exist"},
	"err.device.master_demote_required": {"zh": "需要先指定其他设备为主机", "en": "Please designate another device as master first"},
	"err.device.delete_master_first":  {"zh": "请先切换其他设备为主机再删除当前主机", "en": "Please switch another device to master before deleting the current master"},
	"ok.device.deleted":              {"zh": "已删除", "en": "Deleted"},

	// ─── rate limit（限流） ────────────────────────────
	"err.ratelimit.too_many":          {"zh": "请求过于频繁，请稍后再试", "en": "Too many requests, please try again later"},
	"err.ratelimit.login_too_many":    {"zh": "登录尝试过于频繁，请稍后再试", "en": "Too many login attempts, please try again later"},

	// ─── generic / server（通用 / 服务器） ──────────────
	"err.server.internal":             {"zh": "服务器内部错误，请稍后重试", "en": "Internal server error, please try again later"},

	// ─── body / client version（请求体 / 客户端版本） ───
	"err.body.too_large":              {"zh": "请求体超过大小限制", "en": "Request body exceeds the size limit"},
	"err.client.version_too_low":      {"zh": "客户端版本过低，请更新后重试", "en": "Client version is too low, please update and retry"},

	// ─── domain binding（域名绑定） ──────────────────────
	"err.domain.unresolvable":         {"zh": "无法解析请求域名", "en": "Unable to parse request domain"},
	"err.domain.whitelist_empty":      {"zh": "域名绑定已开启但未配置白名单", "en": "Domain binding is enabled but no whitelist is configured"},
	"err.domain.not_whitelisted":      {"zh": "域名 {host} 不在白名单中", "en": "Domain {host} is not in the whitelist"},

	// ─── sync background pressure（后台同步压力） ───────
	"err.sync.background_busy":        {"zh": "服务器正在处理较多同步任务，请稍后重试", "en": "The server is processing many sync tasks, please try again later"},

	// ─── share（智能体分享码） ──────────────────────────
	"err.share.snapshot_empty":        {"zh": "快照不能为空", "en": "Snapshot cannot be empty"},
	"err.share.snapshot_too_large":    {"zh": "快照过大，超过 512KB 限制", "en": "Snapshot too large, exceeds 512KB limit"},
	"err.share.code_not_found":        {"zh": "分享码不存在", "en": "Share code does not exist"},
	"err.share.code_expired":         {"zh": "分享码已过期", "en": "Share code has expired"},
	"err.share.redeem_rate_limited":   {"zh": "兑换失败次数过多，请稍后再试", "en": "Too many failed redemption attempts, please try again later"},
	"err.share.generate_failed":      {"zh": "生成分享码失败", "en": "Failed to generate share code"},
	"err.share.redeem_failed":        {"zh": "兑换失败", "en": "Redemption failed"},
	"err.share.snapshot_required":    {"zh": "智能体快照不能为空", "en": "Agent snapshot cannot be empty"},
}

// supportedLangs 是受支持的语言集合。超出此集合的 lang 回退到 "zh"。
var supportedLangs = map[string]bool{
	"zh": true,
	"en": true,
}

// ResolveLang 从 gin.Context 读取语言偏好（由 I18nLang 中间件写入）。
// 未设置或不可识别时回退到 "zh"。
func ResolveLang(c *gin.Context) string {
	if c == nil {
		return "zh"
	}
	if lang, ok := c.Get("lang"); ok {
		if s, ok := lang.(string); ok && s != "" {
			if supportedLangs[s] {
				return s
			}
		}
	}
	return "zh"
}

// T 按当前请求语言查译文案。查找失败时依次回退到 zh、key 本身。
func T(c *gin.Context, key string) string {
	lang := ResolveLang(c)
	return TLang(lang, key)
}

// TP 按当前请求语言查译并替换 {placeholder} 占位符。
// 例：TP(c, "err.chat.model_not_allowed", map[string]string{"model": "deepseek-chat"})
// 对应模板 "当前订阅不支持模型 {model}"。
func TP(c *gin.Context, key string, params map[string]string) string {
	lang := ResolveLang(c)
	return TPLang(lang, key, params)
}

// TLang 用显式 lang 查译（供无 gin.Context 的 service 层使用）。
func TLang(lang, key string) string {
	lang = normalizeLang(lang)
	if entry, ok := messages[key]; ok {
		if msg, ok := entry[lang]; ok && msg != "" {
			return msg
		}
		if lang != "zh" {
			if msg, ok := entry["zh"]; ok && msg != "" {
				return msg
			}
		}
	}
	return key
}

// TPLang 用显式 lang 查译并替换 {placeholder} 占位符。
func TPLang(lang, key string, params map[string]string) string {
	msg := TLang(lang, key)
	if len(params) == 0 {
		return msg
	}
	for name, value := range params {
		msg = strings.ReplaceAll(msg, "{"+name+"}", value)
	}
	return msg
}

// normalizeLang 将语言标签归一化为受支持的代码。
// 接受 "en"/"en-US"/"zh"/"zh-CN" 等；不识别回退 "zh"。
func normalizeLang(lang string) string {
	if lang == "" {
		return "zh"
	}
	if supportedLangs[lang] {
		return lang
	}
	// 取主语言子标签：zh-CN → zh
	if i := strings.Index(lang, "-"); i > 0 {
		main := strings.ToLower(lang[:i])
		if supportedLangs[main] {
			return main
		}
	}
	return "zh"
}
