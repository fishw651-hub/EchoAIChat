package handlers

import (
	"context"
	"log"
	"strconv"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type NetworkAiReviewHandler struct{}

// aiReviewService 包级单例，测试可替换其 Chat 字段注入假模型
var aiReviewService = &services.AiReviewService{}

// aiReviewUpdates 把审核结论（或错误）映射为记录写回字段
func aiReviewUpdates(verdict services.AiReviewVerdict, reviewErr error) map[string]interface{} {
	now := time.Now().UTC()
	updates := map[string]interface{}{
		"AiReviewedAt": now.Format(time.RFC3339),
	}
	switch {
	case reviewErr != nil:
		updates["AiReviewStatus"] = "error"
		updates["AiReviewReason"] = reviewErr.Error()
	case verdict.Pass:
		updates["AiReviewStatus"] = "pass"
		updates["AiReviewReason"] = verdict.Reason
		updates["Status"] = "approved"
		updates["RejectReason"] = ""
		updates["ReviewedAt"] = now
		updates["ReviewerID"] = uint(0)
	default:
		updates["AiReviewStatus"] = "reject"
		updates["AiReviewReason"] = verdict.Reason
		updates["Status"] = "rejected"
		updates["RejectReason"] = verdict.Reason
		updates["ReviewedAt"] = now
		updates["ReviewerID"] = uint(0)
	}
	return updates
}

func applyAiReviewAgentResult(
	id uint,
	version int,
	verdict services.AiReviewVerdict,
	reviewErr error,
) error {
	return services.UpdatePendingNetworkAgentVersion(id, version, aiReviewUpdates(verdict, reviewErr))
}

func applyAiReviewGroupResult(
	id uint,
	version int,
	verdict services.AiReviewVerdict,
	reviewErr error,
) error {
	return services.UpdatePendingNetworkGroupVersion(id, version, aiReviewUpdates(verdict, reviewErr))
}

// agentReviewPersona 智能体审核内容：人设 + 开场白。
func agentReviewPersona(a models.NetworkAgent) string {
	persona := decryptField(a.Persona)
	openingLine := decryptField(a.OpeningLine)
	if openingLine == "" {
		return persona
	}
	return persona + "\n\n开场白：\n" + openingLine
}

// groupReviewPersona 群聊审核内容：群人设 + 开场白 + 各成员人设拼接（服务端再做长度截断）
func groupReviewPersona(g models.NetworkGroup) string {
	persona := decryptField(g.GroupPersona)
	if openingLine := decryptField(g.OpeningLine); openingLine != "" {
		persona += "\n\n开场白：\n" + openingLine
	}
	members := groupMembers(g)
	if len(members) == 0 {
		return persona
	}
	var sb strings.Builder
	sb.WriteString(persona)
	for _, m := range members {
		sb.WriteString("\n\n成员[" + m.Name + "]：\n" + m.Persona)
	}
	return sb.String()
}

// TriggerAutoAiReviewAgent 智能体上传/编辑后异步 AI 预审（enabled && auto 时）
func TriggerAutoAiReviewAgent(id uint) {
	enabled, auto, _ := services.GetAiReviewConfig()
	if !enabled || !auto {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("AI 预审智能体 %d panic: %v", id, r)
			}
		}()
		agent, findErr := services.FindNetworkAgentByID(id)
		if findErr != nil || agent == nil {
			return
		}
		// 异步预审在请求结束后才执行，不能用请求 ctx（已取消），用 Background
		verdict, err := aiReviewService.ReviewNetworkContent(context.Background(),
			agent.Name, agent.Description, agentReviewPersona(*agent), decryptField(agent.Worldview))
		if updateErr := applyAiReviewAgentResult(id, agent.Version, verdict, err); updateErr != nil {
			log.Printf("AI 预审智能体 %d 写回失败: %v", id, updateErr)
		} else if err == nil {
			if updated, findErr := services.FindNetworkAgentByID(id); findErr == nil && updated != nil && updated.Status != "pending" {
				services.PublishNetworkReviewStatus(
					updated.UploaderID, "agent", updated.ID, updated.Status,
					updated.RejectReason, updated.Version, agent.Status, time.Now(),
				)
			}
		}
	}()
}

// TriggerAutoAiReviewGroup 群聊上传/编辑后异步 AI 预审（enabled && auto 时）
func TriggerAutoAiReviewGroup(id uint) {
	enabled, auto, _ := services.GetAiReviewConfig()
	if !enabled || !auto {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("AI 预审群聊 %d panic: %v", id, r)
			}
		}()
		group, findErr := services.FindNetworkGroupByID(id)
		if findErr != nil || group == nil {
			return
		}
		// 异步预审在请求结束后才执行，不能用请求 ctx（已取消），用 Background
		verdict, err := aiReviewService.ReviewNetworkContent(context.Background(),
			group.Name, group.Description, groupReviewPersona(*group), decryptField(group.WorldSetting))
		if updateErr := applyAiReviewGroupResult(id, group.Version, verdict, err); updateErr != nil {
			log.Printf("AI 预审群聊 %d 写回失败: %v", id, updateErr)
		} else if err == nil {
			if updated, findErr := services.FindNetworkGroupByID(id); findErr == nil && updated != nil && updated.Status != "pending" {
				services.PublishNetworkReviewStatus(
					updated.UploaderID, "group", updated.ID, updated.Status,
					updated.RejectReason, updated.Version, group.Status, time.Now(),
				)
			}
		}
	}()
}

// GET /api/v1/admin/ai-review-config — 读取 AI 审核配置
func (h *NetworkAiReviewHandler) GetConfig(c *gin.Context) {
	enabled, auto, prompt := services.GetAiReviewConfig()
	utils.Success(c, gin.H{
		"enabled": enabled,
		"auto":    auto,
		"prompt":  prompt,
		"model":   services.GetAiReviewModel(),
	})
}

// PUT /api/v1/admin/ai-review-config — 更新 AI 审核配置（enabled 时 prompt 必填；
// model 非空时必须是 ModelPrice 表已存在的 model_id，空 = 自动回退链）
func (h *NetworkAiReviewHandler) UpdateConfig(c *gin.Context) {
	var req struct {
		Enabled bool   `json:"enabled"`
		Auto    bool   `json:"auto"`
		Prompt  string `json:"prompt"`
		Model   string `json:"model"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	if req.Enabled && strings.TrimSpace(req.Prompt) == "" {
		utils.BadRequest(c, "启用 AI 审核时提示词不能为空")
		return
	}
	req.Model = strings.TrimSpace(req.Model)
	if req.Model != "" {
		price, err := services.FindModelPriceByModelID(req.Model)
		if err != nil || price == nil {
			utils.BadRequest(c, "审核模型不存在，请先在模型定价中添加")
			return
		}
	}

	boolStr := func(b bool) string {
		if b {
			return "true"
		}
		return "false"
	}
	_ = services.SaveSystemConfig(services.AiReviewEnabledConfigKey, boolStr(req.Enabled), "AI 内容审核开关")
	_ = services.SaveSystemConfig(services.AiReviewAutoConfigKey, boolStr(req.Auto), "上传时自动 AI 预审")
	_ = services.SaveSystemConfig(services.AiReviewPromptConfigKey, req.Prompt, "AI 内容审核提示词")
	_ = services.SaveSystemConfig(services.AiReviewModelConfigKey, req.Model, "AI 内容审核模型（空=自动）")

	utils.SuccessMsg(c, "AI 审核配置保存成功")
}

// POST /api/v1/admin/network/agents/:id/ai-review — 手动触发智能体 AI 审核（同步执行）
func (h *NetworkAiReviewHandler) ReviewAgent(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	enabled, _, _ := services.GetAiReviewConfig()
	if !enabled {
		utils.BadRequest(c, "AI 内容审核未启用，请先在系统配置中开启")
		return
	}

	agent, findErr := services.FindNetworkAgentByID(uint(id))
	if findErr != nil || agent == nil {
		utils.NotFound(c, "智能体不存在")
		return
	}

	verdict, err := aiReviewService.ReviewNetworkContent(c.Request.Context(),
		agent.Name, agent.Description, agentReviewPersona(*agent), decryptField(agent.Worldview))
	if updateErr := services.UpdateNetworkAgentByID(uint(id), aiReviewUpdates(verdict, err)); updateErr != nil {
		utils.Internal(c, "AI 审核结果保存失败")
		return
	}
	if err != nil {
		utils.Internal(c, "AI 审核失败: "+err.Error())
		return
	}
	if updated, findErr := services.FindNetworkAgentByID(uint(id)); findErr == nil && updated != nil {
		services.PublishNetworkReviewStatus(
			updated.UploaderID, "agent", updated.ID, updated.Status,
			updated.RejectReason, updated.Version, agent.Status, time.Now(),
		)
	}
	utils.Success(c, verdict)
}

// POST /api/v1/admin/network/groups/:id/ai-review — 手动触发群聊 AI 审核（同步执行）
func (h *NetworkAiReviewHandler) ReviewGroup(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	enabled, _, _ := services.GetAiReviewConfig()
	if !enabled {
		utils.BadRequest(c, "AI 内容审核未启用，请先在系统配置中开启")
		return
	}

	group, findErr := services.FindNetworkGroupByID(uint(id))
	if findErr != nil || group == nil {
		utils.NotFound(c, "群聊不存在")
		return
	}

	verdict, err := aiReviewService.ReviewNetworkContent(c.Request.Context(),
		group.Name, group.Description, groupReviewPersona(*group), decryptField(group.WorldSetting))
	if updateErr := services.UpdateNetworkGroupByID(uint(id), aiReviewUpdates(verdict, err)); updateErr != nil {
		utils.Internal(c, "AI 审核结果保存失败")
		return
	}
	if err != nil {
		utils.Internal(c, "AI 审核失败: "+err.Error())
		return
	}
	if updated, findErr := services.FindNetworkGroupByID(uint(id)); findErr == nil && updated != nil {
		services.PublishNetworkReviewStatus(
			updated.UploaderID, "group", updated.ID, updated.Status,
			updated.RejectReason, updated.Version, group.Status, time.Now(),
		)
	}
	utils.Success(c, verdict)
}
