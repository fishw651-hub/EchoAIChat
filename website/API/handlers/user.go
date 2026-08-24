package handlers

import (
	"fmt"

	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type UserHandler struct{}

func (h *UserHandler) RefreshDailyAllowance(c *gin.Context) {
	user, refreshed, err := services.RefreshDailyAllowance(c.GetUint("user_id"))
	if err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	freeLeft, subLeft, balance := services.GetUserBalanceTiers(&user)
	utils.Success(c, gin.H{
		"daily_quota_left":        freeLeft,
		"subscription_quota_left": subLeft,
		"balance":                 balance,
		"total_balance":           freeLeft + subLeft + balance,
		"refreshed":               refreshed,
	})
}

func (h *UserHandler) GetBalance(c *gin.Context) {
	userID := c.GetUint("user_id")

	user, err := services.FindUserByID(userID)
	if err != nil || user == nil {
		utils.BadRequest(c, "用户不存在")
		return
	}

	freeLeft, subLeft, balance := services.GetUserBalanceTiers(user)

	utils.Success(c, gin.H{
		"balance":                 balance,
		"daily_quota_left":        freeLeft,
		"daily_quota_used":        user.DailyQuotaUsed + user.SubscriptionQuotaUsed,
		"subscription_quota_left": subLeft,
		"total_balance":           freeLeft + subLeft + balance,
	})
}

func (h *UserHandler) GetSubscriptions(c *gin.Context) {
	userID := c.GetUint("user_id")
	utils.Success(c, services.ActiveSubscriptionsForUser(userID))
}

func (h *UserHandler) GetUsageHistory(c *gin.Context) {
	userID := c.GetUint("user_id")
	pageStr := c.DefaultQuery("page", "1")
	pageSizeStr := c.DefaultQuery("page_size", "20")

	var page, pageSize int
	fmt.Sscanf(pageStr, "%d", &page)
	fmt.Sscanf(pageSizeStr, "%d", &pageSize)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	filtered := services.ListUsageRecordsByUser(userID)

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
