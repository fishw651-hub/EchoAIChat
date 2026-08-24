package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// ChatUpstreamStreamConfigKey 控制聊天端点上游调用模式的系统配置键：
// false（默认）= 非流式请求；true = SSE 流式读取上游后聚合为完整响应
const ChatUpstreamStreamConfigKey = "chat_upstream_stream"

// GetChatUpstreamStreamEnabled 读取上游流式调用开关；未配置时默认关闭
func GetChatUpstreamStreamEnabled() bool {
	db := database.Get()
	if db == nil {
		return false
	}
	var sc models.SystemConfig
	if db.Register("SystemConfig").FindOne(database.FilterEq("Key", ChatUpstreamStreamConfigKey), &sc) {
		return sc.Value == "true"
	}
	return false
}
