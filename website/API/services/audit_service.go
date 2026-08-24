package services

import (
	"encoding/json"
	"time"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

type AuditAction string

const (
	AuditActionCreate        AuditAction = "create"
	AuditActionUpdate        AuditAction = "update"
	AuditActionDelete        AuditAction = "delete"
	AuditActionApprove       AuditAction = "approve"
	AuditActionReject        AuditAction = "reject"
	AuditActionTakeDown      AuditAction = "take_down"
	AuditActionRestore       AuditAction = "restore"
	AuditActionResetPassword AuditAction = "reset_password"
	AuditActionResetTest     AuditAction = "reset_test"
	AuditActionGrantSub      AuditAction = "grant_subscription"
	AuditActionRevokeSub     AuditAction = "revoke_subscription"
	AuditActionUpdateConfig  AuditAction = "update_config"
	AuditActionUploadSSL     AuditAction = "upload_ssl"
	AuditActionLogin         AuditAction = "login"
	AuditActionLogout        AuditAction = "logout"
	AuditActionSendEmail     AuditAction = "send_email"
	AuditActionOther         AuditAction = "other"
)

type AuditTargetType string

const (
	AuditTargetUser         AuditTargetType = "user"
	AuditTargetAgent        AuditTargetType = "network_agent"
	AuditTargetGroup        AuditTargetType = "network_group"
	AuditTargetSubscription AuditTargetType = "subscription"
	AuditTargetConfig       AuditTargetType = "system_config"
	AuditTargetAPIKey       AuditTargetType = "api_key"
	AuditTargetPlan         AuditTargetType = "subscription_plan"
	AuditTargetModelPrice   AuditTargetType = "model_price"
	AuditTargetVersion      AuditTargetType = "app_version"
	AuditTargetActivity     AuditTargetType = "activity"
	AuditTargetIfdian       AuditTargetType = "ifdian"
	AuditTargetDevice       AuditTargetType = "device"
	AuditTargetSystem       AuditTargetType = "system"
)

type AuditService struct{}

func NewAuditService() *AuditService {
	return &AuditService{}
}

func (s *AuditService) Log(
	c *gin.Context,
	action AuditAction,
	targetType AuditTargetType,
	targetID string,
	oldValue interface{},
	newValue interface{},
) {
	adminID := c.GetUint("user_id")
	adminName := c.GetString("username")
	if adminName == "" {
		adminName = c.GetString("role")
	}
	ip := c.ClientIP()
	ua := c.GetHeader("User-Agent")

	oldJSON := ""
	if oldValue != nil {
		if b, err := json.Marshal(oldValue); err == nil {
			oldJSON = string(b)
		}
	}
	newJSON := ""
	if newValue != nil {
		if b, err := json.Marshal(newValue); err == nil {
			newJSON = string(b)
		}
	}

	log := &models.AuditLog{
		AdminID:    adminID,
		AdminName:  adminName,
		Action:     string(action),
		TargetType: string(targetType),
		TargetID:   targetID,
		OldValue:   oldJSON,
		NewValue:   newJSON,
		IPAddress:  ip,
		UserAgent:  ua,
	}

	database.Get().Register("AuditLog").Insert(log)
}

func (s *AuditService) List(
	page int,
	pageSize int,
	adminID *uint,
	action *string,
	targetType *string,
	targetID *string,
) ([]models.AuditLog, int, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 200 {
		pageSize = 50
	}

	tbl := database.Get().Register("AuditLog")

	var all []models.AuditLog
	filters := []database.Filter{}
	if adminID != nil {
		filters = append(filters, database.FilterEq("AdminID", float64(*adminID)))
	}
	if action != nil {
		filters = append(filters, database.FilterEq("Action", *action))
	}
	if targetType != nil {
		filters = append(filters, database.FilterEq("TargetType", *targetType))
	}
	if targetID != nil {
		filters = append(filters, database.FilterEq("TargetID", *targetID))
	}

	var filter database.Filter
	if len(filters) > 0 {
		filter = database.FilterAll(filters...)
	}

	total := tbl.Count(filter)
	offset := (page - 1) * pageSize
	// FindAll 签名为 (dest, where, order, offset, limit)，别传反：
	// 传反后第 1 页 limit=0 会返回整表剩余数据。
	tbl.FindAll(&all, filter, "ID desc", offset, pageSize)

	return all, int(total), nil
}

func (s *AuditService) ListAdminActions(adminID uint, page, pageSize int) ([]models.AuditLog, int, error) {
	return s.List(page, pageSize, &adminID, nil, nil, nil)
}

func (s *AuditService) ListForTarget(targetType AuditTargetType, targetID string, page, pageSize int) ([]models.AuditLog, int, error) {
	tt := string(targetType)
	return s.List(page, pageSize, nil, nil, &tt, &targetID)
}

func (s *AuditService) Count() int {
	return int(database.Get().Register("AuditLog").Count(nil))
}

// CleanOld 删除 days 天前的审计日志（按 payload 内 CreatedAt，RFC3339 字典序可比）
func (s *AuditService) CleanOld(days int) (int, error) {
	cutoff := time.Now().UTC().AddDate(0, 0, -days).Format(time.RFC3339Nano)
	n, err := database.Get().Register("AuditLog").DeleteWhereRaw(
		"json_extract(CAST(payload AS TEXT),'$.CreatedAt') < ?", cutoff)
	return int(n), err
}
