package handlers

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AdminHandler struct{}

var auditSvc = services.NewAuditService()

func (h *AdminHandler) Dashboard(c *gin.Context) {
	days, err := strconv.Atoi(c.DefaultQuery("days", "30"))
	if err != nil || (days != 7 && days != 30 && days != 90) {
		utils.BadRequest(c, "days 仅支持 7、30 或 90")
		return
	}

	// 计数/求和全部下推 SQL（COUNT(*) / SUM(json_extract)），不再全表 FindAll 到内存聚合
	userCount, err := services.CountUsers()
	if err != nil {
		utils.Internal(c, "统计用户数失败")
		return
	}
	agentCount, err := services.CountAgentsTotal()
	if err != nil {
		utils.Internal(c, "统计智能体数失败")
		return
	}
	planCount, err := services.CountSubscriptionPlans()
	if err != nil {
		utils.Internal(c, "统计订阅方案数失败")
		return
	}

	orderPending, err := services.CountPaymentOrdersByStatus("pending")
	if err != nil {
		utils.Internal(c, "统计待处理订单失败")
		return
	}

	totalUsageCost, err := services.SumTotalUsageCost()
	if err != nil {
		utils.Internal(c, "统计用量成本失败")
		return
	}
	todayStr := time.Now().Format("2006-01-02")
	todayUsage, err := services.SumUsageCostOn(todayStr)
	if err != nil {
		utils.Internal(c, "统计今日用量失败")
		return
	}

	todayNewUsers, err := services.CountUsersCreatedOn(todayStr)
	if err != nil {
		utils.Internal(c, "统计今日新增用户失败")
		return
	}

	dailyActive, err := services.GetDailyActiveStats(days, time.Now())
	if err != nil {
		utils.Internal(c, "读取日活统计失败")
		return
	}

	utils.Success(c, gin.H{
		"user_count":             userCount,
		"agent_count":            agentCount,
		"plan_count":             planCount,
		"order_pending":          orderPending,
		"total_usage_cost":       totalUsageCost,
		"today_usage":            todayUsage,
		"today_new_users":        todayNewUsers,
		"active_users_today":     dailyActive.Today,
		"active_users_yesterday": dailyActive.Yesterday,
		"active_change_percent":  dailyActive.ChangePercent,
		"dau_peak":               dailyActive.Peak,
		"dau_average":            dailyActive.Average,
		"dau_trend":              dailyActive.Trend,
	})
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")
	keyword := c.Query("keyword")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	allUsers := services.ListUsers("ID desc")

	today := time.Now().Format("2006-01-02")
	// 订阅配额一次性聚合，避免逐用户全表扫 UserSubscription（N+1）
	subQuotaMap := services.SubscriptionDailyQuotaMap()

	type UserWithTiers struct {
		models.User
		FreeQuotaLeft         float64 `json:"free_quota_left"`
		SubscriptionQuotaLeft float64 `json:"subscription_quota_left"`
		TotalBalance          float64 `json:"total_balance"`
	}

	var filtered []UserWithTiers
	for _, u := range allUsers {
		if keyword != "" {
			if !contains(u.Username, keyword) && !contains(u.Email, keyword) && !contains(u.Nickname, keyword) {
				continue
			}
		}
		isNewDay := u.QuotaResetDate != today
		_, freeLeft, subLeft, balance := services.GetUserBalanceTiersReadonlyWithQuota(&u, isNewDay, subQuotaMap[u.ID])
		filtered = append(filtered, UserWithTiers{
			User:                  u,
			FreeQuotaLeft:         freeLeft,
			SubscriptionQuotaLeft: subLeft,
			TotalBalance:          freeLeft + subLeft + balance,
		})
	}

	total := len(filtered)
	offset := (page - 1) * pageSize
	end := offset + pageSize
	if offset > len(filtered) {
		offset = len(filtered)
	}
	if end > len(filtered) {
		end = len(filtered)
	}

	utils.Success(c, gin.H{
		"total":     total,
		"page":      page,
		"page_size": pageSize,
		"records":   filtered[offset:end],
	})
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	user, err := services.FindUserByID(uint(id))
	if err != nil || user == nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	freeLeft, subLeft, balance := services.GetUserBalanceTiers(user)

	utils.Success(c, gin.H{
		"user":                    user,
		"daily_quota_left":        freeLeft,
		"subscription_quota_left": subLeft,
		"total_balance":           freeLeft + subLeft + balance,
	})
}

func (h *AdminHandler) UpdateUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		Status  *int     `json:"status"`
		Role    string   `json:"role"`
		Balance *float64 `json:"balance"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	callerRole := c.GetString("role")
	if callerRole != "super_admin" && (req.Role != "" || req.Balance != nil) {
		utils.Forbidden(c, "只有超级管理员可以修改角色或余额")
		return
	}
	var target *models.User
	if t, err := services.FindUserByID(uint(id)); err == nil {
		target = t
	}
	if target != nil && target.Role == "super_admin" && callerRole != "super_admin" {
		utils.Forbidden(c, "普通管理员不能修改超级管理员")
		return
	}

	oldTarget := models.User{}
	if target != nil {
		oldTarget = *target
	}

	updates := map[string]interface{}{}
	if req.Status != nil {
		updates["Status"] = *req.Status
	}
	if req.Role != "" {
		updates["Role"] = req.Role
	}
	if req.Balance != nil {
		updates["Balance"] = *req.Balance
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "没有需要更新的字段")
		return
	}

	services.UpdateUserByID(uint(id), updates)

	updated := models.User{}
	if u, err := services.FindUserByID(uint(id)); err == nil && u != nil {
		updated = *u
	}
	auditSvc.Log(c, services.AuditActionUpdate, services.AuditTargetUser, fmt.Sprintf("%d", id), oldTarget, updated)

	utils.SuccessMsg(c, "更新成功")
}

// ResetUserQuotaTest 高危测试功能：重置目标用户的当日额度，并可选设置永久余额。
func (h *AdminHandler) ResetUserQuotaTest(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "用户 ID 无效")
		return
	}

	var req struct {
		Balance *float64 `json:"balance"`
		Confirm bool     `json:"confirm"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if !req.Confirm {
		utils.BadRequest(c, "请确认高危操作")
		return
	}

	user, err := services.FindUserByID(uint(id))
	if err != nil || user == nil {
		utils.BadRequest(c, "用户不存在")
		return
	}

	oldUser := *user

	// 重置今日额度；下次刷新接口会重新发放对应额度。
	updates := map[string]interface{}{
		"DailyCheckInBonus":     0,
		"DailyQuotaUsed":        0,
		"SubscriptionQuotaUsed": 0,
		"DailyAllowanceDate":    "",
	}
	// 可选设置永久余额（测试用途）
	if req.Balance != nil {
		updates["Balance"] = *req.Balance
	}
	services.UpdateUserByID(uint(id), updates)

	updated := models.User{}
	if u, err := services.FindUserByID(uint(id)); err == nil && u != nil {
		updated = *u
	}
	auditSvc.Log(c, services.AuditActionResetTest, services.AuditTargetUser, fmt.Sprintf("%d", id), oldUser, updated)

	utils.Success(c, gin.H{
		"message":     "已重置该用户的今日额度",
		"balance_set": req.Balance != nil,
		"balance":     updates["Balance"],
	})
}

func (h *AdminHandler) GetDomainConfig(c *gin.Context) {
	getVal := func(key string) string {
		if sc, err := services.FindSystemConfig(key); err == nil && sc != nil {
			return sc.Value
		}
		return ""
	}

	enabled := getVal("domain_binding_enabled")
	domainsRaw := getVal("allowed_domains")
	var domainList []string
	if domainsRaw != "" {
		for _, d := range strings.Split(domainsRaw, ",") {
			d = strings.TrimSpace(d)
			if d != "" {
				domainList = append(domainList, d)
			}
		}
	}

	utils.Success(c, gin.H{
		"enabled": enabled == "true",
		"domains": domainList,
	})
}

func (h *AdminHandler) UpdateDomainConfig(c *gin.Context) {
	var req struct {
		Enabled bool     `json:"enabled"`
		Domains []string `json:"domains"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	var oldEnabled, oldDomains string
	if sc, err := services.FindSystemConfig("domain_binding_enabled"); err == nil && sc != nil {
		oldEnabled = sc.Value
	}
	if sc, err := services.FindSystemConfig("allowed_domains"); err == nil && sc != nil {
		oldDomains = sc.Value
	}

	services.SaveSystemConfig("domain_binding_enabled", fmt.Sprintf("%t", req.Enabled), "域名绑定开关")
	services.SaveSystemConfig("allowed_domains", strings.Join(req.Domains, ","), "允许的域名列表（逗号分隔）")

	auditSvc.Log(c, services.AuditActionUpdateConfig, services.AuditTargetConfig, "domain_config",
		gin.H{"enabled": oldEnabled, "domains": oldDomains},
		gin.H{"enabled": fmt.Sprintf("%t", req.Enabled), "domains": strings.Join(req.Domains, ",")},
	)

	utils.SuccessMsg(c, "域名配置保存成功")
}

// GetMaintenanceConfig 读取站点维护模式配置
func (h *AdminHandler) GetMaintenanceConfig(c *gin.Context) {
	enabled, bypassKey := services.GetMaintenanceConfig()
	utils.Success(c, gin.H{
		"enabled":    enabled,
		"bypass_key": bypassKey,
	})
}

// UpdateMaintenanceConfig 更新站点维护模式配置；开启且 Key 留空时自动生成随机 Key 并返回
func (h *AdminHandler) UpdateMaintenanceConfig(c *gin.Context) {
	var req struct {
		Enabled   bool   `json:"enabled"`
		BypassKey string `json:"bypass_key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	req.BypassKey = strings.TrimSpace(req.BypassKey)
	if req.Enabled && req.BypassKey == "" {
		req.BypassKey = services.GenerateMaintenanceBypassKey()
	}

	oldEnabled, oldKey := services.GetMaintenanceConfig()

	services.SaveSystemConfig(services.MaintenanceEnabledConfigKey, fmt.Sprintf("%t", req.Enabled), "站点维护模式开关")
	services.SaveSystemConfig(services.MaintenanceBypassKeyConfigKey, req.BypassKey, "维护模式旁路 Key")

	auditSvc.Log(c, services.AuditActionUpdateConfig, services.AuditTargetConfig, "maintenance_config",
		gin.H{"enabled": oldEnabled, "bypass_key": oldKey},
		gin.H{"enabled": req.Enabled, "bypass_key": req.BypassKey},
	)

	utils.Success(c, gin.H{
		"message":    "维护模式配置保存成功",
		"enabled":    req.Enabled,
		"bypass_key": req.BypassKey,
	})
}

func contains(s, substr string) bool {
	return len(substr) == 0 ||
		len(s) >= len(substr) &&
			(s == substr ||
				len(s) > 0 && len(substr) > 0 && strContains(s, substr))
}

func strContains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func (h *AdminHandler) CreateUser(c *gin.Context) {
	var req struct {
		Username string  `json:"username" binding:"required"`
		Email    string  `json:"email"`
		Password string  `json:"password" binding:"required"`
		Nickname string  `json:"nickname"`
		Role     string  `json:"role"`
		Balance  float64 `json:"balance"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 与 UpdateUser 一致：只有超级管理员可以指定角色或初始余额，
	// 普通管理员提交非空角色/余额直接拒绝，防止垂直越权创建 super_admin。
	callerRole := c.GetString("role")
	if callerRole != "super_admin" && (req.Role != "" || req.Balance != 0) {
		utils.Forbidden(c, "只有超级管理员可以指定角色或余额")
		return
	}

	if existing, err := services.FindUserByUsername(req.Username); err == nil && existing != nil {
		utils.BadRequest(c, "用户名已存在")
		return
	}
	if req.Email != "" {
		if existing, err := services.FindUserByEmail(req.Email); err == nil && existing != nil {
			utils.BadRequest(c, "邮箱已被注册")
			return
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		utils.Internal(c, "密码加密失败")
		return
	}
	nickname := req.Nickname
	if nickname == "" {
		nickname = req.Username
	}
	role := req.Role
	if role == "" {
		role = "user"
	}

	user := models.User{
		Username:       req.Username,
		Email:          req.Email,
		PasswordHash:   string(hash),
		Nickname:       nickname,
		Role:           role,
		Balance:        req.Balance,
		Status:         1,
		QuotaResetDate: time.Now().Format("2006-01-02"),
	}

	if err := services.InsertUser(&user); err != nil {
		utils.Internal(c, "创建失败")
		return
	}

	auditSvc.Log(c, services.AuditActionCreate, services.AuditTargetUser, fmt.Sprintf("%d", user.ID), nil, user)

	utils.Success(c, user)
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	user, err := services.FindUserByID(uint(id))
	if err != nil || user == nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	if user.Role == "super_admin" {
		utils.BadRequest(c, "不能删除超级管理员")
		return
	}

	deleted := *user
	services.DeleteUserByID(uint(id))
	auditSvc.Log(c, services.AuditActionDelete, services.AuditTargetUser, fmt.Sprintf("%d", id), deleted, nil)

	utils.SuccessMsg(c, "删除成功")
}

func (h *AdminHandler) GetUserSubscriptions(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	today := time.Now().Format("2006-01-02")
	userSubs := services.ListUserSubscriptionsByUser(uint(id))
	var subs []gin.H
	for _, s := range userSubs {
		isActive := s.Status == 1 && s.ExpiresAt >= today
		subs = append(subs, gin.H{
			"id":          s.ID,
			"plan_name":   s.PlanName,
			"daily_quota": s.DailyQuota,
			"started_at":  s.StartedAt,
			"expires_at":  s.ExpiresAt,
			"status":      s.Status,
			"active":      isActive,
			"order_no":    s.OrderNo,
		})
	}

	utils.Success(c, subs)
}

func (h *AdminHandler) AssignSubscription(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)

	var req struct {
		PlanID       uint    `json:"plan_id" binding:"required"`
		DailyQuota   float64 `json:"daily_quota"`
		DurationDays int     `json:"duration_days"`
		Renew        bool    `json:"renew"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	user, err := services.FindUserByID(uint(id))
	if err != nil || user == nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	plan, err := services.FindSubscriptionPlanByID(req.PlanID)
	if err != nil || plan == nil {
		utils.NotFound(c, "订阅计划不存在")
		return
	}

	if req.DurationDays <= 0 {
		req.DurationDays = plan.DurationDays
	}
	if req.DailyQuota <= 0 {
		req.DailyQuota = plan.DailyQuota
	}

	now := time.Now()
	today := now.Format("2006-01-02")

	if req.Renew {
		existing, err := services.FindActiveUserSubscription(uint(id), req.PlanID, today)
		if err == nil && existing != nil {
			oldSub := *existing
			expiry, err := time.Parse("2006-01-02", existing.ExpiresAt)
			if err != nil {
				expiry = now
			}
			newExpiry := expiry.AddDate(0, 0, req.DurationDays)
			services.UpdateUserSubscriptionByID(existing.ID, map[string]interface{}{
				"ExpiresAt":  newExpiry.Format("2006-01-02"),
				"DailyQuota": req.DailyQuota,
			})
			existing.ExpiresAt = newExpiry.Format("2006-01-02")
			existing.DailyQuota = req.DailyQuota
			auditSvc.Log(c, services.AuditActionGrantSub, services.AuditTargetSubscription, fmt.Sprintf("%d", existing.ID), oldSub, *existing)
			utils.Success(c, existing)
			return
		}
	}

	sub := models.UserSubscription{
		UserID:     uint(id),
		PlanID:     req.PlanID,
		PlanName:   plan.Name,
		DailyQuota: req.DailyQuota,
		StartedAt:  today,
		ExpiresAt:  now.AddDate(0, 0, req.DurationDays).Format("2006-01-02"),
		Status:     1,
		OrderNo:    "ADMIN" + now.Format("20060102150405"),
	}

	if err := services.InsertUserSubscription(&sub); err != nil {
		utils.Internal(c, "分配失败")
		return
	}

	auditSvc.Log(c, services.AuditActionGrantSub, services.AuditTargetSubscription, fmt.Sprintf("%d", sub.ID), nil, sub)

	utils.Success(c, sub)
}

func (h *AdminHandler) ChangePassword(c *gin.Context) {
	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint("user_id")
	role, _ := c.Get("role")

	user, err := services.FindUserByID(userID)
	if err != nil || user == nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	if role == "super_admin" && req.OldPassword == "" {
		// super_admin 可不验证旧密码直接修改
	} else {
		if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
			utils.BadRequest(c, "原密码错误")
			return
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), 12)
	if err != nil {
		utils.Internal(c, "密码加密失败")
		return
	}

	services.UpdateUserByID(userID, map[string]interface{}{
		"PasswordHash": string(hash),
		// 管理员重置密码同样递增令牌版本，踢出该用户所有已签发 token
		"TokenVersion": user.TokenVersion + 1,
	})

	auditSvc.Log(c, services.AuditActionResetPassword, services.AuditTargetUser, fmt.Sprintf("%d", userID), nil, gin.H{"changed": true})

	utils.SuccessMsg(c, "密码修改成功")
}

// GET /api/v1/admin/audit-logs — 审计日志列表
func (h *AdminHandler) ListAuditLogs(c *gin.Context) {
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "50")
	action := c.Query("action")
	targetType := c.Query("target_type")
	targetID := c.Query("target_id")
	adminIDStr := c.Query("admin_id")

	page, _ := strconv.Atoi(pageStr)
	pageSize, _ := strconv.Atoi(pageSizeStr)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 200 {
		pageSize = 50
	}

	var adminID *uint
	if adminIDStr != "" {
		id, err := strconv.ParseUint(adminIDStr, 10, 64)
		if err == nil {
			uid := uint(id)
			adminID = &uid
		}
	}

	var actionPtr *string
	if action != "" {
		actionPtr = &action
	}
	var targetTypePtr *string
	if targetType != "" {
		targetTypePtr = &targetType
	}
	var targetIDPtr *string
	if targetID != "" {
		targetIDPtr = &targetID
	}

	list, total, err := auditSvc.List(page, pageSize, adminID, actionPtr, targetTypePtr, targetIDPtr)
	if err != nil {
		utils.Internal(c, "查询失败")
		return
	}

	utils.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GET /api/v1/admin/audit-logs/stats — 审计日志统计
func (h *AdminHandler) AuditLogStats(c *gin.Context) {
	total := auditSvc.Count()
	utils.Success(c, gin.H{
		"total": total,
	})
}
