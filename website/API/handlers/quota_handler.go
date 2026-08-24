package handlers

import (
	"sort"
	"strconv"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type QuotaHandler struct{}

func (h *QuotaHandler) ClaimProactiveCare(c *gin.Context) {
	var req struct {
		ClientAgentID string `json:"client_agent_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	claim, err := services.ClaimProactiveCare(c.GetUint("user_id"), req.ClientAgentID)
	if err != nil {
		if err == services.ErrProactiveDailyLimit || err == services.ErrProactiveClaimFinalized {
			utils.BadRequest(c, err.Error())
			return
		}
		if err == services.ErrAgentNotOwned {
			utils.Forbidden(c, "智能体不属于当前账号")
			return
		}
		if _, ok := err.(*services.FeatureQuotaExceededError); ok {
			c.JSON(402, gin.H{"code": 402, "message": err.Error()})
			return
		}
		utils.Internal(c, "主动关心配额预留失败")
		return
	}
	utils.Success(c, gin.H{"claim_token": claim.ClaimToken})
}

func (h *QuotaHandler) CommitProactiveCare(c *gin.Context) {
	var req struct {
		ClaimToken string `json:"claim_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if err := services.CommitProactiveCare(req.ClaimToken); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	utils.Success(c, gin.H{"committed": true})
}

func (h *QuotaHandler) ReleaseProactiveCare(c *gin.Context) {
	var req struct {
		ClaimToken string `json:"claim_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if err := services.ReleaseProactiveCare(req.ClaimToken); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	utils.Success(c, gin.H{"released": true})
}

// per-user 分片锁（固定 256 桶、内存有界），防止 Consume/Refund 的检查-扣减区间并发绕过配额上限
// 单实例有效；多实例需分布式锁
var quotaUserLocks = utils.NewStripedLock()

func lockQuotaUser(userID uint) func() {
	return quotaUserLocks.LockUint(userID)
}

// QuotaType 配额类型
type QuotaType string

const (
	QuotaOcr       QuotaType = "ocr"
	QuotaRealReply QuotaType = "real_reply"
)

// subscriptionQuota 单个订阅的配额视图
type subscriptionQuota struct {
	ID        uint   `json:"id"`
	PlanID    uint   `json:"plan_id"`
	PlanName  string `json:"plan_name"`
	ExpiresAt string `json:"expires_at"`
	Ocr       gin.H  `json:"ocr"`
	RealReply gin.H  `json:"real_reply"`
}

// GetUsage 获取当前用户的功能配额使用情况（按订阅独立展示）
func (h *QuotaHandler) GetUsage(c *gin.Context) {
	userID := c.GetUint("user_id")

	user, err := services.FindUserByID(userID)
	if err != nil || user == nil {
		utils.BadRequest(c, "用户不存在")
		return
	}

	// 跨天重置（兼容 User 表旧字段，per-subscription 计数在 loadActiveSubscriptions 内重置）
	h.resetIfNewDay(user)

	subs := h.loadActiveSubscriptions(userID)

	// 构造 per-subscription 视图
	subViews := []subscriptionQuota{}
	aggOcrUsed, aggOcrQuota := 0, 0
	aggRealUsed, aggRealQuota := 0, 0
	aggOcrUnlimited, aggRealUnlimited := false, false

	for _, s := range subs {
		plan := h.loadPlan(s.PlanID)
		ocrQ, ocrUnlim := h.planQuota(plan, QuotaOcr)
		realQ, realUnlim := h.planQuota(plan, QuotaRealReply)

		ocrUsed := s.OcrUsedToday
		realUsed := s.RealReplyUsedToday

		ocrRem := 0
		if ocrUnlim {
			ocrRem = -1
		} else if ocrQ > ocrUsed {
			ocrRem = ocrQ - ocrUsed
		}
		realRem := 0
		if realUnlim {
			realRem = -1
		} else if realQ > realUsed {
			realRem = realQ - realUsed
		}

		subViews = append(subViews, subscriptionQuota{
			ID:        s.ID,
			PlanID:    s.PlanID,
			PlanName:  s.PlanName,
			ExpiresAt: s.ExpiresAt,
			Ocr: gin.H{
				"used":      ocrUsed,
				"quota":     ocrQ,
				"remaining": ocrRem,
				"unlimited": ocrUnlim,
			},
			RealReply: gin.H{
				"used":      realUsed,
				"quota":     realQ,
				"remaining": realRem,
				"unlimited": realUnlim,
			},
		})

		aggOcrUsed += ocrUsed
		aggRealUsed += realUsed
		if ocrUnlim {
			aggOcrUnlimited = true
		} else {
			aggOcrQuota += ocrQ
		}
		if realUnlim {
			aggRealUnlimited = true
		} else {
			aggRealQuota += realQ
		}
	}

	// 无订阅时回退到默认配额（User 表上的 used 仍兼容）
	// 同时计算系统默认值（无论是否有订阅，都返回给客户端用于展示"系统默认"标签）
	defOcr, _ := h.defaultQuota(QuotaOcr)
	defReal, _ := h.defaultQuota(QuotaRealReply)
	if len(subs) == 0 {
		aggOcrQuota = defOcr
		aggRealQuota = defReal
		aggOcrUsed = user.OcrUsedToday
		aggRealUsed = user.RealReplyUsedToday
	}

	aggOcrRem := 0
	if aggOcrUnlimited {
		aggOcrRem = -1
	} else if aggOcrQuota > aggOcrUsed {
		aggOcrRem = aggOcrQuota - aggOcrUsed
	}
	aggRealRem := 0
	if aggRealUnlimited {
		aggRealRem = -1
	} else if aggRealQuota > aggRealUsed {
		aggRealRem = aggRealQuota - aggRealUsed
	}

	utils.Success(c, gin.H{
		"ocr": gin.H{
			"used":      aggOcrUsed,
			"quota":     aggOcrQuota,
			"remaining": aggOcrRem,
			"unlimited": aggOcrUnlimited,
		},
		"real_reply": gin.H{
			"used":      aggRealUsed,
			"quota":     aggRealQuota,
			"remaining": aggRealRem,
			"unlimited": aggRealUnlimited,
		},
		"reset_date":         user.QuotaResetDate,
		"subscriptions":      subViews,
		"default_ocr":        defOcr,
		"default_real_reply": defReal,
	})
}

// Consume 消耗一次配额
// 优先级：若指定 subscription_id 则扣该订阅；否则按"过期最近优先"自动选目标订阅
func (h *QuotaHandler) Consume(c *gin.Context) {
	var req struct {
		Type           string `json:"type" binding:"required"`
		SubscriptionID *uint  `json:"subscription_id"` // 可选
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	qt := QuotaType(req.Type)
	if qt != QuotaOcr && qt != QuotaRealReply {
		utils.BadRequest(c, "未知的配额类型")
		return
	}
	if qt == QuotaRealReply {
		c.JSON(410, gin.H{"code": 410, "message": "真实回复配额已并入聊天事务，请使用聊天接口"})
		return
	}

	userID := c.GetUint("user_id")
	unlock := lockQuotaUser(userID)
	defer unlock()

	var user *models.User
	if u, err := services.FindUserByID(userID); err == nil {
		user = u
	}
	if user == nil {
		utils.BadRequest(c, "用户不存在")
		return
	}
	h.resetIfNewDay(user)

	subs := h.loadActiveSubscriptions(userID)

	// 无订阅：走默认配额，扣 User 表（兼容旧逻辑）
	if len(subs) == 0 {
		defQuota, unlim := h.defaultQuota(qt)
		used := user.OcrUsedToday
		field := "OcrUsedToday"
		if qt == QuotaRealReply {
			used = user.RealReplyUsedToday
			field = "RealReplyUsedToday"
		}
		if !unlim && used >= defQuota {
			utils.BadRequest(c, "今日配额已用完")
			return
		}
		services.IncrementUserField(userID, field, 1)
		used++
		remaining := 0
		if unlim {
			remaining = -1
		} else if defQuota > used {
			remaining = defQuota - used
		}
		key := "ocr"
		if qt == QuotaRealReply {
			key = "real_reply"
		}
		services.PublishQuotaChanged(userID)
		utils.Success(c, gin.H{
			key: gin.H{
				"used":      used,
				"quota":     defQuota,
				"remaining": remaining,
				"unlimited": unlim,
			},
		})
		return
	}

	// 选目标订阅
	target, plan, targetIdx := h.pickTargetSubscription(subs, req.SubscriptionID, qt)
	if target == nil {
		utils.BadRequest(c, "今日配额已用完")
		return
	}

	// 重置该订阅的计数（若跨天）
	h.resetSubscriptionIfNewDay(target)

	quota, unlim := h.planQuota(plan, qt)
	used := target.OcrUsedToday
	field := "OcrUsedToday"
	if qt == QuotaRealReply {
		used = target.RealReplyUsedToday
		field = "RealReplyUsedToday"
	}

	if !unlim && used >= quota {
		// 该订阅已用完，尝试下一个订阅
		remaining := h.tryConsumeNext(subs, targetIdx, qt)
		if remaining == nil {
			utils.BadRequest(c, "今日配额已用完")
			return
		}
		services.PublishQuotaChanged(userID)
		utils.Success(c, gin.H{
			"ocr":        remaining["ocr"],
			"real_reply": remaining["real_reply"],
		})
		return
	}

	// 扣减目标订阅
	services.IncrementUserSubscriptionField(target.ID, field, 1)
	used++

	// 同步更新 User 表上的聚合计数（兼容旧客户端读取）
	aggField := "OcrUsedToday"
	if qt == QuotaRealReply {
		aggField = "RealReplyUsedToday"
	}
	services.IncrementUserField(userID, aggField, 1)

	remaining := 0
	if unlim {
		remaining = -1
	} else if quota > used {
		remaining = quota - used
	}

	key := "ocr"
	if qt == QuotaRealReply {
		key = "real_reply"
	}
	services.PublishQuotaChanged(userID)
	utils.Success(c, gin.H{
		key: gin.H{
			"used":            used,
			"quota":           quota,
			"remaining":       remaining,
			"unlimited":       unlim,
			"subscription_id": target.ID,
		},
	})
}

// pickTargetSubscription 选定目标订阅
// 若指定了 subscriptionID，则使用该订阅；否则按"过期最近优先"选择
func (h *QuotaHandler) pickTargetSubscription(subs []models.UserSubscription, preferredID *uint, qt QuotaType) (*models.UserSubscription, *models.SubscriptionPlan, int) {
	// 复制一份并按 ExpiresAt 升序排序（先用快过期的）
	sortedSubs := make([]models.UserSubscription, len(subs))
	copy(sortedSubs, subs)
	sort.Slice(sortedSubs, func(i, j int) bool {
		return sortedSubs[i].ExpiresAt < sortedSubs[j].ExpiresAt
	})

	if preferredID != nil {
		for i := range sortedSubs {
			if sortedSubs[i].ID == *preferredID {
				plan := h.loadPlan(sortedSubs[i].PlanID)
				return &sortedSubs[i], plan, i
			}
		}
	}

	// 自动选第一个有效订阅（过期最近）
	for i := range sortedSubs {
		plan := h.loadPlan(sortedSubs[i].PlanID)
		// 若该订阅此项 quota=0（不允许），跳过
		q, unlim := h.planQuota(plan, qt)
		if q == 0 && !unlim {
			continue
		}
		return &sortedSubs[i], plan, i
	}
	return nil, nil, -1
}

// tryConsumeNext 当目标订阅已用完时，尝试下一个订阅
func (h *QuotaHandler) tryConsumeNext(subs []models.UserSubscription, skipIdx int, qt QuotaType) gin.H {
	sortedSubs := make([]models.UserSubscription, len(subs))
	copy(sortedSubs, subs)
	sort.Slice(sortedSubs, func(i, j int) bool {
		return sortedSubs[i].ExpiresAt < sortedSubs[j].ExpiresAt
	})

	for i := range sortedSubs {
		if i == skipIdx {
			continue
		}
		h.resetSubscriptionIfNewDay(&sortedSubs[i])
		plan := h.loadPlan(sortedSubs[i].PlanID)
		quota, unlim := h.planQuota(plan, qt)
		if quota == 0 && !unlim {
			continue
		}
		used := sortedSubs[i].OcrUsedToday
		field := "OcrUsedToday"
		if qt == QuotaRealReply {
			used = sortedSubs[i].RealReplyUsedToday
			field = "RealReplyUsedToday"
		}
		if !unlim && used >= quota {
			continue
		}
		services.IncrementUserSubscriptionField(sortedSubs[i].ID, field, 1)
		used++
		remaining := 0
		if unlim {
			remaining = -1
		} else if quota > used {
			remaining = quota - used
		}
		key := "ocr"
		if qt == QuotaRealReply {
			key = "real_reply"
		}
		return gin.H{
			key: gin.H{
				"used":            used,
				"quota":           quota,
				"remaining":       remaining,
				"unlimited":       unlim,
				"subscription_id": sortedSubs[i].ID,
			},
		}
	}
	return nil
}

// loadActiveSubscriptions 加载用户所有有效订阅（status=1 且未过期），并跨天重置 per-subscription 计数
func (h *QuotaHandler) loadActiveSubscriptions(userID uint) []models.UserSubscription {
	result := services.ActiveSubscriptionsForUser(userID)
	for i := range result {
		// 跨天重置
		h.resetSubscriptionIfNewDay(&result[i])
	}
	return result
}

// loadPlan 按 ID 加载订阅计划
func (h *QuotaHandler) loadPlan(planID uint) *models.SubscriptionPlan {
	plan, err := services.FindSubscriptionPlanByID(planID)
	if err != nil || plan == nil {
		return nil
	}
	return plan
}

// planQuota 返回某计划某项配额的上限
func (h *QuotaHandler) planQuota(plan *models.SubscriptionPlan, qt QuotaType) (int, bool) {
	if plan == nil {
		return 0, false
	}
	q := plan.OcrDailyQuota
	if qt == QuotaRealReply {
		q = plan.RealReplyDailyQuota
	}
	if q == -1 {
		return 0, true // 无限
	}
	return q, false
}

// defaultQuota 系统默认配额（无订阅场景）
func (h *QuotaHandler) defaultQuota(qt QuotaType) (int, bool) {
	defaultKey := "default_ocr_daily_quota"
	if qt == QuotaRealReply {
		defaultKey = "default_real_reply_daily_quota"
	}
	defaultQuota := 3
	if qt == QuotaRealReply {
		defaultQuota = 30
	}

	if sc, err := services.FindSystemConfig(defaultKey); err == nil && sc != nil {
		if v, err := strconv.Atoi(sc.Value); err == nil {
			defaultQuota = v
		}
	}
	return defaultQuota, false
}

// resetIfNewDay 若跨天则重置 User 表上的聚合当日使用计数
func (h *QuotaHandler) resetIfNewDay(user *models.User) {
	today := utils.TodayCN()
	if user.QuotaResetDate != today {
		services.UpdateUserByID(user.ID, map[string]interface{}{
			"OcrUsedToday":       0,
			"RealReplyUsedToday": 0,
			"QuotaResetDate":     today,
		})
		user.OcrUsedToday = 0
		user.RealReplyUsedToday = 0
		user.QuotaResetDate = today
	}
}

// resetSubscriptionIfNewDay 若跨天则重置单个订阅的当日使用计数
func (h *QuotaHandler) resetSubscriptionIfNewDay(sub *models.UserSubscription) {
	today := utils.TodayCN()
	if sub.QuotaResetDate != today {
		services.UpdateUserSubscriptionByID(sub.ID, map[string]interface{}{
			"OcrUsedToday":       0,
			"RealReplyUsedToday": 0,
			"QuotaResetDate":     today,
		})
		sub.OcrUsedToday = 0
		sub.RealReplyUsedToday = 0
		sub.QuotaResetDate = today
	}
}
