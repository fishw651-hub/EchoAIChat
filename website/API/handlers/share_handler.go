package handlers

import (
	"encoding/json"
	"errors"
	"time"

	"aichat-api/middleware"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type ShareHandler struct{}

// CreateShare 生成智能体分享码（6 位数字，20 分钟有效）
// POST /api/v1/user/share/agent
// body 直接为智能体快照 JSON 对象
func (h *ShareHandler) CreateShare(c *gin.Context) {
	userID := c.GetUint("user_id")
	var snapshot json.RawMessage
	if err := c.ShouldBindJSON(&snapshot); err != nil || len(snapshot) == 0 {
		utils.BadRequest(c, "智能体快照不能为空")
		return
	}

	code, expiresAt, err := services.CreateShareCode(userID, snapshot)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrShareSnapshotEmpty):
			utils.BadRequest(c, err.Error())
		case errors.Is(err, services.ErrShareSnapshotTooLarge):
			utils.BadRequest(c, err.Error())
		default:
			utils.Internal(c, "生成分享码失败")
		}
		return
	}
	utils.Success(c, gin.H{
		"code":       code,
		"expires_at": expiresAt.Format(time.RFC3339),
	})
}

// RedeemShare 凭分享码兑换智能体快照（有效期内可多人重复兑换）
// POST /api/v1/user/share/redeem
func (h *ShareHandler) RedeemShare(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req struct {
		Code string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 防爆破限流：仅计兑换失败，成功不计。per-user 之外叠加 per-IP，
	// 防止批量注册小号线性放大爆破尝试（6 位数字码共 90 万个）
	if err := services.CheckRedeemRateLimit(userID); err != nil {
		utils.Fail(c, utils.CodeTooManyReqs, err.Error())
		return
	}
	clientIP := middleware.RealClientIP(c)
	if err := services.CheckRedeemIPRateLimit(clientIP); err != nil {
		utils.Fail(c, utils.CodeTooManyReqs, err.Error())
		return
	}

	snapshot, err := services.RedeemShareCode(req.Code)
	if err != nil {
		services.RecordRedeemFailure(userID)
		services.RecordRedeemIPFailure(clientIP)
		switch {
		case errors.Is(err, services.ErrShareCodeExpired):
			utils.Fail(c, utils.CodeBadRequest, err.Error())
		case errors.Is(err, services.ErrShareCodeNotFound):
			utils.NotFound(c, err.Error())
		default:
			utils.Internal(c, "兑换失败")
		}
		return
	}
	utils.Success(c, gin.H{"agent": json.RawMessage(snapshot)})
}
