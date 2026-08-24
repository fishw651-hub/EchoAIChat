package handlers

import (
	"fmt"
	"log"
	"strings"
	"time"

	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type SyncHandler struct{}

// syncTableName 白名单
var syncTableNames = map[string]bool{
	"agents": true, "chat_messages": true, "short_term_messages": true,
	"group_chats": true, "group_members": true, "group_messages": true,
	"group_short_term": true, "group_shared_memories": true,
	"long_term_memories": true, "base_memories": true, "planned_messages": true,
	"user_profiles": true, "providers": true,
}

// registerTableName 本地表名 → Go struct 注册名（= JSON 文件名）
func registerTableName(tableName string) string {
	switch tableName {
	case "agents":
		return "SyncAgent"
	case "chat_messages":
		return "SyncChatMessage"
	case "short_term_messages":
		return "SyncShortTermMessage"
	case "group_chats":
		return "SyncGroupChat"
	case "group_members":
		return "SyncGroupMember"
	case "group_messages":
		return "SyncGroupMessage"
	case "group_short_term":
		return "SyncGroupShortTerm"
	case "group_shared_memories":
		return "SyncGroupSharedMemory"
	case "long_term_memories":
		return "SyncLongTermMemory"
	case "base_memories":
		return "SyncBaseMemory"
	case "planned_messages":
		return "SyncPlannedMessage"
	case "user_profiles":
		return "SyncUserProfile"
	case "providers":
		return "SyncProvider"
	}
	return ""
}

// encryptFields 各表需要加密的字段（PascalCase，与 Go struct 字段名一致）
var tableEncryptFields = map[string][]string{
	"agents":        {"Persona", "OpeningLine", "Worldview"},
	"user_profiles": {"Value"},
	"providers":     {"ApiKey"},
}

// encryptItem 对 map 中的敏感字段加密（key 可能是 PascalCase 或 snake_case）
func encryptItem(table string, item map[string]interface{}) {
	fields, ok := tableEncryptFields[table]
	if !ok {
		return
	}
	for _, f := range fields {
		// PascalCase
		if v, ok := item[f]; ok {
			if s, ok := v.(string); ok {
				item[f] = encryptField(s)
			}
		}
		// snake_case
		snake := strings.ToLower(f)
		if v, ok := item[snake]; ok {
			if s, ok := v.(string); ok {
				item[snake] = encryptField(s)
			}
		}
	}
}

// decryptItem 对 map 中的敏感字段解密
func decryptItem(table string, item map[string]interface{}) {
	fields, ok := tableEncryptFields[table]
	if !ok {
		return
	}
	for _, f := range fields {
		if v, ok := item[f]; ok {
			if s, ok := v.(string); ok {
				item[f] = decryptField(s)
			}
		}
		snake := strings.ToLower(f)
		if v, ok := item[snake]; ok {
			if s, ok := v.(string); ok {
				item[snake] = decryptField(s)
			}
		}
	}
}

// GET /api/v1/sync/status — 返回各表云端最近 updated_at
func (h *SyncHandler) GetStatus(c *gin.Context) {
	userID := c.GetUint("user_id")
	status := gin.H{}
	for table := range syncTableNames {
		status[table] = services.SyncMaxUpdatedAtByUserID(registerTableName(table), userID)
	}
	status["tombstones"] = services.SyncTombstoneMaxUpdatedAtByUserID(userID)
	utils.Success(c, status)
}

// POST /api/v1/sync/:table — 上传单表数据
func (h *SyncHandler) UploadTable(c *gin.Context) {
	userID := c.GetUint("user_id")
	table := c.Param("table")

	// 特殊处理 tombstones 路由：只处理墓碑，不 upsert 数据
	if table == "tombstones" {
		var req struct {
			Tombstones []map[string]interface{} `json:"tombstones"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			utils.BadRequest(c, utils.T(c, "err.sync.param_error"))
			return
		}
		deleted, err := h.processTombstones(userID, req.Tombstones)
		if err != nil {
			log.Printf("⚠️ 墓碑处理失败(user=%d): %v", userID, err)
			utils.Internal(c, utils.T(c, "err.sync.write_failed"))
			return
		}
		utils.Success(c, gin.H{"upserted": 0, "deleted": deleted})
		return
	}

	if !syncTableNames[table] {
		utils.BadRequest(c, utils.T(c, "err.sync.invalid_table"))
		return
	}

	var req struct {
		Items      []map[string]interface{} `json:"items"`
		Tombstones []map[string]interface{} `json:"tombstones"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.sync.param_error"))
		return
	}

	// 加密敏感字段（原地修改）
	for _, item := range req.Items {
		encryptItem(table, item)
	}

	regName := registerTableName(table)
	// 批量 upsert：全程一次写锁 + 一次落盘（旧实现每条记录都整表落盘）
	upserted, err := services.SyncBatchUpsertByUserIDClientID(regName, userID, req.Items)
	if err != nil {
		// 部分失败必须返回错误让客户端保留本地队列并重试，否则静默丢数据
		log.Printf("⚠️ 同步批量写入失败(user=%d table=%s, 已写入 %d/%d): %v", userID, table, upserted, len(req.Items), err)
		utils.Internal(c, utils.T(c, "err.sync.write_failed"))
		return
	}

	deleted, err := h.processTombstones(userID, req.Tombstones)
	if err != nil {
		log.Printf("⚠️ 墓碑处理失败(user=%d table=%s): %v", userID, table, err)
		utils.Internal(c, utils.T(c, "err.sync.write_failed"))
		return
	}
	utils.Success(c, gin.H{"upserted": upserted, "deleted": deleted})
}

// GET /api/v1/sync/:table — 下载单表数据
func (h *SyncHandler) DownloadTable(c *gin.Context) {
	userID := c.GetUint("user_id")
	table := c.Param("table")

	// 特殊处理 tombstones 路由
	if table == "tombstones" {
		items := services.SyncTombstonesByUserID(userID)
		utils.Success(c, gin.H{"items": items, "server_time": time.Now()})
		return
	}

	if !syncTableNames[table] {
		utils.BadRequest(c, utils.T(c, "err.sync.invalid_table"))
		return
	}

	regName := registerTableName(table)
	items := services.SyncFindAllByUserID(regName, userID)
	for _, item := range items {
		decryptItem(table, item)
	}
	utils.Success(c, gin.H{"items": items, "server_time": time.Now()})
}

// POST /api/v1/sync/all — 上传所有表
func (h *SyncHandler) UploadAll(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req map[string]struct {
		Items      []map[string]interface{} `json:"items"`
		Tombstones []map[string]interface{} `json:"tombstones"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, utils.T(c, "err.sync.param_error"))
		return
	}
	totalUpserted, totalDeleted := 0, 0
	// 合并所有表的墓碑，统一批量处理
	var allTombstones []map[string]interface{}
	for table, payload := range req {
		if !syncTableNames[table] {
			continue
		}
		// 加密敏感字段
		for _, item := range payload.Items {
			encryptItem(table, item)
		}
		regName := registerTableName(table)
		// 批量 upsert：每张表仅一次落盘
		upserted, err := services.SyncBatchUpsertByUserIDClientID(regName, userID, payload.Items)
		if err != nil {
			// 部分失败必须返回错误让客户端保留本地队列并重试，否则静默丢数据
			log.Printf("⚠️ 同步全量批量写入失败(user=%d table=%s, 已写入 %d/%d): %v", userID, table, upserted, len(payload.Items), err)
			utils.Internal(c, utils.T(c, "err.sync.write_failed"))
			return
		}
		totalUpserted += upserted
		allTombstones = append(allTombstones, payload.Tombstones...)
	}
	deleted, err := h.processTombstones(userID, allTombstones)
	if err != nil {
		log.Printf("⚠️ 全量同步墓碑处理失败(user=%d): %v", userID, err)
		utils.Internal(c, utils.T(c, "err.sync.write_failed"))
		return
	}
	totalDeleted = deleted
	utils.Success(c, gin.H{"upserted": totalUpserted, "deleted": totalDeleted})
}

// GET /api/v1/sync/all — 下载所有表
func (h *SyncHandler) DownloadAll(c *gin.Context) {
	userID := c.GetUint("user_id")
	result := gin.H{}
	for table := range syncTableNames {
		regName := registerTableName(table)
		items := services.SyncFindAllByUserID(regName, userID)
		for _, item := range items {
			decryptItem(table, item)
		}
		result[table] = items
	}
	result["tombstones"] = services.SyncTombstonesByUserID(userID)
	result["server_time"] = time.Now()
	utils.Success(c, result)
}

// DELETE /api/v1/sync/tombstones — 清空已应用的墓碑
func (h *SyncHandler) ClearTombstones(c *gin.Context) {
	userID := c.GetUint("user_id")
	// 遍历删除该用户所有墓碑
	for _, t := range services.SyncTombstonesByUserID(userID) {
		if fid, ok := toUint(t["ID"]); ok {
			services.SyncDeleteTombstoneByID(fid)
		}
	}
	utils.SuccessMsg(c, utils.T(c, "ok.sync.tombstones_cleared"))
}

// DELETE /api/v1/sync/cloud — 删除当前账号的云端同步副本，保留本地数据。
func (h *SyncHandler) DeleteCloudCopy(c *gin.Context) {
	userID := c.GetUint("user_id")
	var request struct {
		ScopeMode        string   `json:"scope_mode"`
		SelectedAgentIDs []string `json:"selected_agent_ids"`
	}
	if err := c.ShouldBindJSON(&request); err != nil {
		utils.BadRequest(c, utils.T(c, "err.sync.param_error"))
		return
	}

	var scope services.SyncScope
	switch request.ScopeMode {
	case "all":
		scope = services.NewAllSyncScope()
	case "selected":
		if len(request.SelectedAgentIDs) == 0 {
			utils.BadRequest(c, utils.T(c, "err.sync.selected_ids_required"))
			return
		}
		if len(request.SelectedAgentIDs) > 500 {
			utils.BadRequest(c, utils.T(c, "err.sync.too_many_agents"))
			return
		}
		scope = services.NewSelectedSyncScope(request.SelectedAgentIDs)
	default:
		utils.BadRequest(c, utils.T(c, "err.sync.scope_mode_invalid"))
		return
	}

	deleted := 0
	for table := range syncTableNames {
		rows := services.FilterSyncItems(scope, table,
			services.SyncFindAllByUserID(registerTableName(table), userID))
		clientIDs := make([]string, 0, len(rows))
		for _, row := range rows {
			if clientID := syncClientID(row); clientID != "" {
				clientIDs = append(clientIDs, clientID)
			}
		}
		deleted += services.SyncBatchDeleteByUserIDClientID(registerTableName(table), userID, clientIDs)
	}

	// 删除相关墓碑，避免旧删除记录在后续同步时误删本地数据。
	for _, tombstone := range services.FilterSyncTombstones(scope, services.SyncTombstonesByUserID(userID)) {
		if id, ok := toUint(tombstone["ID"]); ok {
			if services.SyncDeleteTombstoneByID(id) {
				deleted++
			}
		}
	}

	utils.Success(c, gin.H{"deleted": deleted})
}

// processTombstones 处理墓碑：插入 SyncTombstone 记录，并从对应 SyncXxx 表删除。
//
// 批量优化：按目标表分组，每张表仅一次落盘。
// 旧实现每条墓碑都触发 2 次整表落盘（SyncTombstone 一次 + 目标表一次），
// N 条墓碑 = 2N 次整表序列化 + 磁盘 I/O。
func (h *SyncHandler) processTombstones(userID uint, tombstones []map[string]interface{}) (int, error) {
	if len(tombstones) == 0 {
		return 0, nil
	}

	// 收集合法墓碑，按目标表分组
	type tombEntry struct {
		clientID string
	}
	groupedByTable := make(map[string][]tombEntry)
	var tombRows []map[string]interface{}

	for _, t := range tombstones {
		tombTable, _ := t["table_name"].(string)
		tombClientID, _ := t["client_id"].(string)
		if tombTable == "" || tombClientID == "" {
			continue
		}
		if registerTableName(tombTable) == "" {
			continue
		}
		groupedByTable[tombTable] = append(groupedByTable[tombTable], tombEntry{tombClientID})
		tombRows = append(tombRows, map[string]interface{}{
			"UserID":    userID,
			"TableName": tombTable,
			"ClientID":  tombClientID,
		})
	}

	if len(tombRows) == 0 {
		return 0, nil
	}

	// 1) 批量插入墓碑记录，仅一次落盘
	inserted, err := services.SyncInsertTombstones(tombRows)
	if err != nil {
		// 墓碑写不进去就不能继续删目标行：删除会同步不到其他端，必须报错让客户端重试
		return 0, fmt.Errorf("墓碑批量插入失败(已插入 %d/%d): %w", inserted, len(tombRows), err)
	}

	// 2) 按目标表批量删除，每张表仅一次落盘
	deleted := 0
	for tableName, entries := range groupedByTable {
		regName := registerTableName(tableName)
		if regName == "" {
			continue
		}
		clientIDs := make([]string, 0, len(entries))
		for _, e := range entries {
			clientIDs = append(clientIDs, e.clientID)
		}
		deleted += services.SyncBatchDeleteByUserIDClientID(regName, userID, clientIDs)
	}
	return deleted, nil
}

// 兼容性：避免 unused import 警告
var _ = fmt.Sprintf
var _ = models.SyncAgent{}

// toUint 从 interface{} 提取 uint（database 包的 getFloat 是私有的，这里复制一份）
func toUint(v interface{}) (uint, bool) {
	switch val := v.(type) {
	case float64:
		return uint(val), true
	case int:
		return uint(val), true
	case int64:
		return uint(val), true
	case uint:
		return val, true
	}
	return 0, false
}
