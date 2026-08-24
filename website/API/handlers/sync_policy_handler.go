package handlers

import (
	"errors"
	"net/http"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type SyncPolicyHandler struct {
	Service *services.SyncPolicyService
}

func (h *SyncPolicyHandler) policyService() *services.SyncPolicyService {
	if h.Service != nil {
		return h.Service
	}
	return services.DefaultSyncPolicyService
}

func (h *SyncPolicyHandler) Get(c *gin.Context) {
	policy, err := h.policyService().Get(c.GetUint("user_id"))
	if err != nil {
		utils.Internal(c, "读取同步策略失败")
		return
	}
	utils.Success(c, policy)
}

func (h *SyncPolicyHandler) Update(c *gin.Context) {
	var request models.SyncPolicyUpdate
	if err := c.ShouldBindJSON(&request); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	policy, err := h.policyService().Update(c.GetUint("user_id"), request)
	if errors.Is(err, services.ErrSyncPolicyConflict) {
		c.JSON(http.StatusConflict, utils.Response{
			Code: utils.CodeConflict, Message: err.Error(), Data: nil,
		})
		return
	}
	if errors.Is(err, services.ErrInvalidSyncPolicy) {
		utils.BadRequest(c, err.Error())
		return
	}
	if err != nil {
		utils.Internal(c, "更新同步策略失败")
		return
	}
	utils.Success(c, policy)
}
