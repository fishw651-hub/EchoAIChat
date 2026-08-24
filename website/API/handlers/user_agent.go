package handlers

import (
	"fmt"
	"strconv"
	"time"

	"aichat-api/config"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type UserAgentHandler struct{}

func getEncKey() []byte {
	encKey := config.AppConfig.Encryption.Key
	if len(encKey) < 32 {
		encKey = encKey + "00000000000000000000000000000000"
	}
	return []byte(encKey[:32])
}

func encryptField(val string) string {
	if val == "" {
		return ""
	}
	enc, err := services.Encrypt(val, getEncKey())
	if err != nil {
		return ""
	}
	return enc
}

func decryptField(val string) string {
	if val == "" {
		return ""
	}
	dec, err := services.DecryptWithConfiguredKeys(val)
	if err != nil {
		return ""
	}
	return dec
}

// GET /api/v1/user/agents — 列出当前用户所有智能体
func (h *UserAgentHandler) ListMyAgents(c *gin.Context) {
	userID := c.GetUint("user_id")

	all := services.ListUserAgentsByUser(userID)

	var result []gin.H
	for _, a := range all {
		result = append(result, gin.H{
			"id":                                a.ID,
			"user_id":                           a.UserID,
			"client_id":                         a.ClientID,
			"name":                              a.Name,
			"gender":                            a.Gender,
			"description":                       a.Description,
			"persona":                           decryptField(a.Persona),
			"opening_line":                      decryptField(a.OpeningLine),
			"avatar_color":                      a.AvatarColor,
			"avatar_path":                       a.AvatarPath,
			"chat_background":                   a.ChatBackground,
			"worldview":                         decryptField(a.Worldview),
			"max_response_length":               normalizeAgentResponseLength(a.MaxResponseLength),
			"is_sim_character":                  a.IsSimCharacter,
			"real_info_enabled":                 a.RealInfoEnabled,
			"proactive_care_enabled":            a.ProactiveCareEnabled,
			"proactive_care_daily_limit":        a.ProactiveCareDailyLimit,
			"proactive_care_min_interval_hours": a.ProactiveCareMinIntervalHours,
			"created_at":                        a.CreatedAt,
			"updated_at":                        a.UpdatedAt,
		})
	}

	utils.Success(c, result)
}

// POST /api/v1/user/agents — 创建/更新智能体
func (h *UserAgentHandler) SaveAgent(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req struct {
		ID                            *uint   `json:"id"`
		ClientID                      *string `json:"client_id"`
		Name                          *string `json:"name" binding:"required"`
		Gender                        *string `json:"gender"`
		Description                   *string `json:"description"`
		Persona                       *string `json:"persona"`
		OpeningLine                   *string `json:"opening_line"`
		AvatarColor                   *int    `json:"avatar_color"`
		AvatarPath                    *string `json:"avatar_path"`
		ChatBackground                *string `json:"chat_background"`
		Worldview                     *string `json:"worldview"`
		MaxResponseLength             *int    `json:"max_response_length"`
		IsSimCharacter                *bool   `json:"is_sim_character"`
		RealInfoEnabled               *bool   `json:"real_info_enabled"`
		ProactiveCareEnabled          *bool   `json:"proactive_care_enabled"`
		ProactiveCareDailyLimit       *int    `json:"proactive_care_daily_limit"`
		ProactiveCareMinIntervalHours *int    `json:"proactive_care_min_interval_hours"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	now := time.Now()

	// 更新已有智能体
	if req.ID == nil && req.ClientID != nil && *req.ClientID != "" {
		if existing, _ := services.FindUserAgentByClientID(userID, *req.ClientID); existing != nil {
			req.ID = &existing.ID
		}
	}
	if req.ID != nil && *req.ID > 0 {
		existing, err := services.FindUserAgentByID(*req.ID)
		if err != nil || existing == nil || existing.UserID != userID {
			utils.NotFound(c, "智能体不存在")
			return
		}

		updates := make(map[string]interface{})
		if req.Name != nil {
			updates["Name"] = *req.Name
		}
		if req.Gender != nil {
			updates["Gender"] = *req.Gender
		}
		if req.Description != nil {
			updates["Description"] = *req.Description
		}
		if req.Persona != nil {
			updates["Persona"] = encryptField(*req.Persona)
		}
		if req.OpeningLine != nil {
			updates["OpeningLine"] = encryptField(*req.OpeningLine)
		}
		if req.AvatarColor != nil {
			updates["AvatarColor"] = *req.AvatarColor
		}
		if req.AvatarPath != nil {
			updates["AvatarPath"] = *req.AvatarPath
		}
		if req.ChatBackground != nil {
			updates["ChatBackground"] = *req.ChatBackground
		}
		if req.Worldview != nil {
			updates["Worldview"] = encryptField(*req.Worldview)
		}
		if req.MaxResponseLength != nil {
			updates["MaxResponseLength"] = normalizeAgentResponseLength(*req.MaxResponseLength)
		}
		if req.IsSimCharacter != nil {
			updates["IsSimCharacter"] = *req.IsSimCharacter
		}
		if req.ClientID != nil && *req.ClientID != "" {
			updates["ClientID"] = *req.ClientID
		}
		if req.RealInfoEnabled != nil {
			updates["RealInfoEnabled"] = *req.RealInfoEnabled
		}
		if req.ProactiveCareEnabled != nil {
			updates["ProactiveCareEnabled"] = *req.ProactiveCareEnabled
		}
		if req.ProactiveCareDailyLimit != nil {
			updates["ProactiveCareDailyLimit"] = *req.ProactiveCareDailyLimit
		}
		if req.ProactiveCareMinIntervalHours != nil {
			updates["ProactiveCareMinIntervalHours"] = *req.ProactiveCareMinIntervalHours
		}
		updates["UpdatedAt"] = now

		services.UpdateUserAgentByID(existing.ID, updates)
		utils.Success(c, gin.H{"id": existing.ID})
		return
	}

	// 创建新智能体
	agent := models.UserAgent{
		UserID:    userID,
		Name:      "",
		UpdatedAt: now,
	}
	if req.ClientID != nil {
		agent.ClientID = *req.ClientID
	}
	if req.Name != nil {
		agent.Name = *req.Name
	}
	if req.Gender != nil {
		agent.Gender = *req.Gender
	}
	if req.Description != nil {
		agent.Description = *req.Description
	}
	if req.Persona != nil {
		agent.Persona = encryptField(*req.Persona)
	}
	if req.OpeningLine != nil {
		agent.OpeningLine = encryptField(*req.OpeningLine)
	}
	if req.AvatarColor != nil {
		agent.AvatarColor = *req.AvatarColor
	}
	if req.AvatarPath != nil {
		agent.AvatarPath = *req.AvatarPath
	}
	if req.ChatBackground != nil {
		agent.ChatBackground = *req.ChatBackground
	}
	if req.Worldview != nil {
		agent.Worldview = encryptField(*req.Worldview)
	}
	if req.MaxResponseLength != nil {
		agent.MaxResponseLength = normalizeAgentResponseLength(*req.MaxResponseLength)
	}
	if req.IsSimCharacter != nil {
		agent.IsSimCharacter = *req.IsSimCharacter
	}
	if req.RealInfoEnabled != nil {
		agent.RealInfoEnabled = *req.RealInfoEnabled
	}
	if req.ProactiveCareEnabled != nil {
		agent.ProactiveCareEnabled = *req.ProactiveCareEnabled
	}
	if req.ProactiveCareDailyLimit != nil {
		agent.ProactiveCareDailyLimit = *req.ProactiveCareDailyLimit
	}
	if req.ProactiveCareMinIntervalHours != nil {
		agent.ProactiveCareMinIntervalHours = *req.ProactiveCareMinIntervalHours
	}

	if err := services.InsertUserAgent(&agent); err != nil {
		utils.Internal(c, "保存失败")
		return
	}

	utils.Success(c, gin.H{"id": agent.ID, "created_at": agent.CreatedAt, "updated_at": agent.UpdatedAt})
}

// DELETE /api/v1/user/agents/:id — 删除智能体
func (h *UserAgentHandler) DeleteAgent(c *gin.Context) {
	userID := c.GetUint("user_id")
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	agent, err := services.FindUserAgentByID(uint(id))
	if err != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	if agent.UserID != userID {
		utils.Forbidden(c, fmt.Sprintf("无权删除该智能体"))
		return
	}

	services.DeleteUserAgentByID(uint(id))
	utils.SuccessMsg(c, "删除成功")
}
