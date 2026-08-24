package handlers

import (
	"errors"

	"aichat-api/config"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	authService *services.AuthService
}

// translateAuthServiceErr 将 AuthService 返回的哨兵错误翻译为当前请求语言的文案。
// 已识别的错误用对应 i18n 键；未识别的哨兵错误回退到通用错误文案。
func translateAuthServiceErr(c *gin.Context, err error) string {
	if err == nil {
		return ""
	}
	switch {
	case errors.Is(err, services.ErrAuthUserTaken):
		return utils.T(c, "err.auth.register_taken")
	case errors.Is(err, services.ErrAuthBcryptFailed):
		return utils.T(c, "err.auth.bcrypt_failed")
	case errors.Is(err, services.ErrAuthRegisterFailed):
		return utils.T(c, "err.auth.register_failed")
	case errors.Is(err, services.ErrAuthWrongCredentials):
		return utils.T(c, "err.auth.wrong_credentials")
	case errors.Is(err, services.ErrAuthAccountBanned):
		return utils.T(c, "err.auth.account_banned")
	case errors.Is(err, services.ErrAuthGenerateTokenFailed):
		return utils.T(c, "err.auth.generate_token_short")
	case errors.Is(err, services.ErrAuthUserNotFound):
		return utils.T(c, "err.auth.user_not_found_short")
	case errors.Is(err, services.ErrAuthOldPasswordWrong):
		return utils.T(c, "err.auth.old_password_wrong")
	}
	return err.Error()
}

func NewAuthHandler() *AuthHandler {
	return &AuthHandler{authService: &services.AuthService{}}
}

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=64"`
	Email    string `json:"email"` // 选填：不绑定邮箱的账号无法找回密码
	Password string `json:"password" binding:"required,min=6,max=128"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	DeviceID string `json:"device_id"` // 客户端设备指纹，用于账号切换封禁统计
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.TP(c, "err.auth.param_error_detail", map[string]string{"detail": err.Error()}))
		return
	}

	if req.Email != "" && !utils.IsValidEmail(req.Email) {
		utils.BadRequest(c, utils.T(c, "err.auth.email_invalid"))
		return
	}

	user, err := h.authService.Register(req.Username, req.Email, req.Password)
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

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	user, token, err := h.authService.Login(req.Username, req.Password, c.ClientIP())
	if err != nil {
		utils.BadRequest(c, translateAuthServiceErr(c, err))
		return
	}

	// 记录设备账号切换（防盗用 API）；触发封禁时随响应返回封禁信息
	banned, banUntil, banDays := services.RecordDeviceLogin(req.DeviceID, user.ID)

	// refresh_token 用同一个 JWT 简化处理：客户端在 token 即将过期前调用 /auth/refresh 换新
	utils.Success(c, gin.H{
		"token":         token,
		"refresh_token": token,
		"expires_in":    config.AppConfig.JWT.ExpireHours * 3600,
		"id":            user.ID,
		"username":      user.Username,
		"nickname":      user.Nickname,
		"avatar_url":    user.AvatarURL,
		"role":          user.Role,
		"balance":       0,
		"device_banned": banned,
		"ban_until":     banUntil,
		"ban_days":      banDays,
	})
}

// DeviceStatus 查询设备封禁状态（公开端点，客户端每次启动调用）
func (h *AuthHandler) DeviceStatus(c *gin.Context) {
	deviceID := c.Query("device_id")
	if deviceID == "" {
		utils.BadRequest(c, utils.T(c, "err.auth.device_id_required"))
		return
	}
	banned, banUntil, banDays := services.CheckDeviceBan(deviceID)
	utils.Success(c, gin.H{
		"banned":    banned,
		"ban_until": banUntil,
		"ban_days":  banDays,
	})
}

// / Refresh 接口：接受当前有效的 JWT，签发新的 JWT（滑动过期）
// / 客户端在 token 过期前调用此接口换取新 token，避免频繁登录
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.RefreshToken == "" {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	// 解析旧 token（必须仍处于有效期内）
	claims, err := utils.ParseToken(req.RefreshToken)
	if err != nil {
		utils.Unauthorized(c, utils.T(c, "err.auth.refresh_token_invalid"))
		return
	}

	// 验证用户仍然存在且未被禁用
	user, err := services.GetUserByID(claims.UserID)
	if err != nil || user.Status != 1 {
		utils.Unauthorized(c, utils.T(c, "err.auth.user_not_found"))
		return
	}

	// 令牌版本必须匹配：改密/重置密码后旧 token 不允许续期
	if claims.TokenVersion != user.TokenVersion {
		utils.Unauthorized(c, utils.T(c, "err.auth.status_changed"))
		return
	}

	// 签发新 token
	newToken, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		utils.Internal(c, utils.T(c, "err.auth.generate_token_failed"))
		return
	}

	utils.Success(c, gin.H{
		"token":         newToken,
		"refresh_token": newToken,
		"expires_in":    config.AppConfig.JWT.ExpireHours * 3600,
	})
}

func (h *AuthHandler) ChangePassword(c *gin.Context) {
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	userID := c.GetUint("user_id")
	if err := h.authService.ChangePassword(userID, req.OldPassword, req.NewPassword); err != nil {
		utils.BadRequest(c, translateAuthServiceErr(c, err))
		return
	}

	utils.SuccessMsg(c, utils.T(c, "ok.auth.password_changed"))
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := c.GetUint("user_id")
	user, err := services.GetUserByID(userID)
	if err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.user_not_found_short"))
		return
	}

	dailyLeft := services.GetUserDailyQuota(user)
	if dailyLeft < 0 {
		dailyLeft = 0
	}

	utils.Success(c, gin.H{
		"user": gin.H{
			"id":               user.ID,
			"username":         user.Username,
			"email":            user.Email,
			"nickname":         user.Nickname,
			"avatar_url":       user.AvatarURL,
			"balance":          0,
			"daily_quota_used": user.DailyQuotaUsed + user.SubscriptionQuotaUsed,
			"daily_quota_left": dailyLeft,
			"role":             user.Role,
			"status":           user.Status,
		},
	})
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	var req struct {
		Nickname  string `json:"nickname"`
		AvatarURL string `json:"avatar_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.param_error"))
		return
	}

	userID := c.GetUint("user_id")
	updates := map[string]interface{}{}
	if req.Nickname != "" {
		updates["Nickname"] = req.Nickname
	}
	if req.AvatarURL != "" {
		updates["AvatarURL"] = req.AvatarURL
	}

	if len(updates) == 0 {
		utils.BadRequest(c, utils.T(c, "err.auth.no_update_fields"))
		return
	}

	services.UpdateUserByID(userID, updates)
	utils.SuccessMsg(c, utils.T(c, "ok.auth.profile_updated"))
}

func (h *AuthHandler) UploadAvatar(c *gin.Context) {
	file, err := c.FormFile("avatar")
	if err != nil {
		utils.BadRequest(c, utils.T(c, "err.auth.avatar_required"))
		return
	}

	if msg := utils.ValidateAvatar(file); msg != "" {
		utils.BadRequest(c, msg)
		return
	}

	src, err := file.Open()
	if err != nil {
		utils.Internal(c, utils.T(c, "err.auth.read_file_failed"))
		return
	}
	defer src.Close()

	avatarURL, err := services.SaveAvatar(src, file.Filename)
	if err != nil {
		utils.Internal(c, utils.TP(c, "err.auth.upload_failed", map[string]string{"detail": err.Error()}))
		return
	}

	userID := c.GetUint("user_id")
	services.UpdateUserByID(userID, map[string]interface{}{
		"AvatarURL": avatarURL,
	})

	utils.Success(c, gin.H{"avatar_url": avatarURL})
}
