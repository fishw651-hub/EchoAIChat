package handlers

import (
	"aichat-api/config"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	authService *services.AuthService
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
		utils.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	if req.Email != "" && !utils.IsValidEmail(req.Email) {
		utils.BadRequest(c, "邮箱格式不正确")
		return
	}

	user, err := h.authService.Register(req.Username, req.Email, req.Password)
	if err != nil {
		utils.BadRequest(c, err.Error())
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
		utils.BadRequest(c, "参数错误")
		return
	}

	user, token, err := h.authService.Login(req.Username, req.Password, c.ClientIP())
	if err != nil {
		utils.BadRequest(c, err.Error())
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
		utils.BadRequest(c, "缺少 device_id")
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
		utils.BadRequest(c, "参数错误")
		return
	}

	// 解析旧 token（必须仍处于有效期内）
	claims, err := utils.ParseToken(req.RefreshToken)
	if err != nil {
		utils.Unauthorized(c, "refresh_token 无效或已过期")
		return
	}

	// 验证用户仍然存在且未被禁用
	user, err := services.GetUserByID(claims.UserID)
	if err != nil || user.Status != 1 {
		utils.Unauthorized(c, "用户不存在或已被禁用")
		return
	}

	// 令牌版本必须匹配：改密/重置密码后旧 token 不允许续期
	if claims.TokenVersion != user.TokenVersion {
		utils.Unauthorized(c, "登录状态已变更，请重新登录")
		return
	}

	// 签发新 token
	newToken, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		utils.Internal(c, "生成 token 失败")
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
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint("user_id")
	if err := h.authService.ChangePassword(userID, req.OldPassword, req.NewPassword); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	utils.SuccessMsg(c, "密码修改成功")
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := c.GetUint("user_id")
	user, err := services.GetUserByID(userID)
	if err != nil {
		utils.BadRequest(c, err.Error())
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
		utils.BadRequest(c, "参数错误")
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
		utils.BadRequest(c, "没有需要更新的字段")
		return
	}

	services.UpdateUserByID(userID, updates)
	utils.SuccessMsg(c, "信息更新成功")
}

func (h *AuthHandler) UploadAvatar(c *gin.Context) {
	file, err := c.FormFile("avatar")
	if err != nil {
		utils.BadRequest(c, "请选择头像文件")
		return
	}

	if msg := utils.ValidateAvatar(file); msg != "" {
		utils.BadRequest(c, msg)
		return
	}

	src, err := file.Open()
	if err != nil {
		utils.Internal(c, "读取文件失败")
		return
	}
	defer src.Close()

	avatarURL, err := services.SaveAvatar(src, file.Filename)
	if err != nil {
		utils.Internal(c, "上传失败: "+err.Error())
		return
	}

	userID := c.GetUint("user_id")
	services.UpdateUserByID(userID, map[string]interface{}{
		"AvatarURL": avatarURL,
	})

	utils.Success(c, gin.H{"avatar_url": avatarURL})
}
