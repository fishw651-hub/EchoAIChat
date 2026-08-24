package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"time"

	"aichat-api/hub"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

type SyncV2Handler struct {
	PolicyService *services.SyncPolicyService
	PreviewStore  *services.SyncPreviewStore
}

type syncV2TablePayload struct {
	Items      []map[string]interface{} `json:"items"`
	Tombstones []map[string]interface{} `json:"tombstones"`
}

type syncV2Request struct {
	PreviewToken  string                        `json:"preview_token"`
	Mode          string                        `json:"mode"`
	PolicyVersion uint64                        `json:"policy_version"`
	AgentIDs      []string                      `json:"agent_ids"`
	Tables        map[string]syncV2TablePayload `json:"tables"`
}

type syncPreviewCounts struct {
	UploadCount         int `json:"upload_count"`
	DownloadCount       int `json:"download_count"`
	OverwriteLocalCount int `json:"overwrite_local_count"`
	OverwriteCloudCount int `json:"overwrite_cloud_count"`
	DeleteCount         int `json:"delete_count"`
	ConflictCount       int `json:"conflict_count"`
}

func (h *SyncV2Handler) policyService() *services.SyncPolicyService {
	if h.PolicyService != nil {
		return h.PolicyService
	}
	return services.DefaultSyncPolicyService
}

func (h *SyncV2Handler) previewStore() *services.SyncPreviewStore {
	if h.PreviewStore != nil {
		return h.PreviewStore
	}
	return services.DefaultSyncPreviewStore
}

func (h *SyncV2Handler) Preview(c *gin.Context) {
	request, deviceID, policy, scope, ok := h.bindAndValidate(c)
	if !ok {
		return
	}
	counts, err := h.previewCounts(c.GetUint("user_id"), scope, request.Tables)
	if err != nil {
		utils.Internal(c, "生成同步预览失败")
		return
	}
	payloadHash, err := syncV2PayloadHash(request)
	if err != nil {
		utils.BadRequest(c, "同步数据无效")
		return
	}
	token, expiresAt, err := h.previewStore().Issue(services.SyncPreviewBinding{
		UserID: c.GetUint("user_id"), DeviceID: deviceID, Mode: request.Mode,
		PolicyVersion: policy.Version, Scope: scope, PayloadHash: payloadHash,
	})
	if err != nil {
		utils.BadRequest(c, err.Error())
		return
	}
	utils.Success(c, gin.H{
		"preview_token": token, "expires_at": expiresAt, "policy_version": policy.Version,
		"upload_count": counts.UploadCount, "download_count": counts.DownloadCount,
		"overwrite_local_count": counts.OverwriteLocalCount,
		"overwrite_cloud_count": counts.OverwriteCloudCount,
		"delete_count":          counts.DeleteCount, "conflict_count": counts.ConflictCount,
	})
}

func (h *SyncV2Handler) Run(c *gin.Context) {
	request, deviceID, policy, scope, ok := h.bindAndValidate(c)
	if !ok {
		return
	}
	if request.PreviewToken == "" {
		utils.BadRequest(c, "preview_token 不能为空")
		return
	}
	payloadHash, err := syncV2PayloadHash(request)
	if err != nil {
		utils.BadRequest(c, "同步数据无效")
		return
	}
	err = h.previewStore().Consume(request.PreviewToken, services.SyncPreviewBinding{
		UserID: c.GetUint("user_id"), DeviceID: deviceID, Mode: request.Mode,
		PolicyVersion: policy.Version, Scope: scope, PayloadHash: payloadHash,
	})
	if err != nil {
		status := http.StatusBadRequest
		if errors.Is(err, services.ErrSyncPreviewChanged) {
			status = http.StatusConflict
		}
		c.JSON(status, utils.Response{Code: utils.CodeConflict, Message: err.Error()})
		return
	}

	changes, err := h.mergeAndPersist(
		c.Request.Context(),
		c.GetUint("user_id"),
		scope,
		request.Tables,
	)
	if err != nil {
		utils.Internal(c, "执行同步失败")
		return
	}
	h.notifyRealtimeChanges(c.GetUint("user_id"), deviceID, policy, changes)
	tables, tombstones := h.downloadScope(c.GetUint("user_id"), scope)
	now := time.Now().UTC()
	_ = services.UpdateDeviceByUserAndDeviceID(c.GetUint("user_id"), deviceID,
		map[string]interface{}{"LastSyncAt": now, "LastActiveAt": now})

	utils.Success(c, gin.H{
		"tables": tables, "tombstones": tombstones, "server_time": now,
		"policy_version": policy.Version,
	})
}

func (h *SyncV2Handler) notifyRealtimeChanges(
	userID uint,
	deviceID string,
	policy models.SyncPolicy,
	changes []syncChangeEvent,
) {
	if hub.Hub == nil || !policy.RealtimeEnabled {
		return
	}
	seen := make(map[string]struct{})
	for _, change := range changes {
		key := change.Table + "\x00" + change.AgentID
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		hub.Hub.NotifyDataChange(
			userID,
			deviceID,
			change.Table,
			change.AgentID,
			policy,
		)
	}
}

func (h *SyncV2Handler) bindAndValidate(c *gin.Context) (syncV2Request, string, models.SyncPolicy, services.SyncScope, bool) {
	var request syncV2Request
	if err := c.ShouldBindJSON(&request); err != nil {
		utils.BadRequest(c, "参数错误")
		return request, "", models.SyncPolicy{}, services.SyncScope{}, false
	}
	if request.Mode != "immediate" && request.Mode != "one_shot" {
		utils.BadRequest(c, "mode 必须是 immediate 或 one_shot")
		return request, "", models.SyncPolicy{}, services.SyncScope{}, false
	}
	deviceID := c.GetHeader("X-Device-ID")
	if deviceID == "" || !registeredSyncDevice(c.GetUint("user_id"), deviceID) {
		utils.Forbidden(c, "设备未注册")
		return request, "", models.SyncPolicy{}, services.SyncScope{}, false
	}
	policy, err := h.policyService().Get(c.GetUint("user_id"))
	if err != nil {
		utils.Internal(c, "读取同步策略失败")
		return request, "", models.SyncPolicy{}, services.SyncScope{}, false
	}
	if request.PolicyVersion != policy.Version {
		c.JSON(http.StatusConflict, utils.Response{Code: utils.CodeConflict, Message: "同步策略已变化"})
		return request, "", models.SyncPolicy{}, services.SyncScope{}, false
	}
	var scope services.SyncScope
	if request.Mode == "one_shot" {
		if len(request.AgentIDs) > 500 {
			utils.BadRequest(c, "单次同步智能体数量过多")
			return request, "", models.SyncPolicy{}, services.SyncScope{}, false
		}
		scope = services.NewSelectedSyncScope(request.AgentIDs)
	} else if policy.ScopeMode == "selected" {
		scope = services.NewSelectedSyncScope(policy.SelectedAgentIDs)
	} else {
		scope = services.NewAllSyncScope()
	}
	return request, deviceID, policy, scope, true
}

func registeredSyncDevice(userID uint, deviceID string) bool {
	device, err := services.FindDevice(userID, deviceID)
	return err == nil && device != nil
}

func syncV2PayloadHash(request syncV2Request) (string, error) {
	request.PreviewToken = ""
	data, err := json.Marshal(request)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}

func (h *SyncV2Handler) previewCounts(userID uint, scope services.SyncScope, payloads map[string]syncV2TablePayload) (syncPreviewCounts, error) {
	counts := syncPreviewCounts{}
	for _, table := range allowedScopeTables(scope) {
		local := services.FilterSyncItems(scope, table, payloads[table].Items)
		cloud := services.FilterSyncItems(scope, table,
			services.SyncFindAllByUserID(registerTableName(table), userID))
		localByID := syncItemsByClientID(local)
		cloudByID := syncItemsByClientID(cloud)
		for clientID, localItem := range localByID {
			cloudItem, exists := cloudByID[clientID]
			if !exists {
				counts.UploadCount++
				continue
			}
			winner, conflict := services.NewerSyncItem(localItem, cloudItem)
			if conflict {
				counts.ConflictCount++
			}
			if syncMapIsItem(winner, localItem) {
				counts.OverwriteCloudCount++
			} else if conflict {
				counts.OverwriteLocalCount++
			}
		}
		for clientID := range cloudByID {
			if _, exists := localByID[clientID]; !exists {
				counts.DownloadCount++
			}
		}
		counts.DeleteCount += len(services.FilterSyncTombstones(scope, payloads[table].Tombstones))
	}
	return counts, nil
}

type syncChangeEvent struct {
	Table   string
	AgentID string
}

func (h *SyncV2Handler) mergeAndPersist(
	ctx context.Context,
	userID uint,
	scope services.SyncScope,
	payloads map[string]syncV2TablePayload,
) ([]syncChangeEvent, error) {
	changes := make([]syncChangeEvent, 0)
	err := services.WithSyncTx(ctx, func(tx *services.SyncTx) error {
		for _, table := range allowedScopeTables(scope) {
			registerName := registerTableName(table)
			cloudRows, err := tx.FindAllByUserID(registerName, userID)
			if err != nil {
				return fmt.Errorf("读取 %s: %w", table, err)
			}
			cloudByID := syncItemsByClientID(services.FilterSyncItems(scope, table, cloudRows))
			for _, localItem := range services.FilterSyncItems(scope, table, payloads[table].Items) {
				clientID := syncClientID(localItem)
				if clientID == "" {
					continue
				}
				if cloudItem, exists := cloudByID[clientID]; exists {
					winner, _ := services.NewerSyncItem(localItem, cloudItem)
					if !syncMapIsItem(winner, localItem) {
						continue
					}
				}
				stored := cloneHandlerMap(localItem)
				encryptItem(table, stored)
				if err := tx.UpsertByUserIDClientID(registerName, userID, stored); err != nil {
					return fmt.Errorf("写入 %s: %w", table, err)
				}
				agentID := syncHandlerString(localItem, "agent_id", "AgentID")
				if table == "agents" {
					agentID = clientID
				}
				changes = append(changes, syncChangeEvent{Table: table, AgentID: agentID})
				cloudByID[clientID] = localItem
			}
			for _, tombstone := range services.FilterSyncTombstones(scope, payloads[table].Tombstones) {
				clientID := syncClientID(tombstone)
				if clientID == "" {
					continue
				}
				if cloudItem, exists := cloudByID[clientID]; exists &&
					!services.SyncTombstoneWins(tombstone, cloudItem) {
					continue
				}
				if _, err := tx.DeleteByUserIDClientID(registerName, userID, clientID); err != nil {
					return fmt.Errorf("删除 %s: %w", table, err)
				}
				if err := tx.Insert("SyncTombstone", &models.SyncTombstone{
					UserID: userID, TableName: table, ClientID: clientID,
					AgentID:   syncHandlerString(tombstone, "agent_id", "AgentID"),
					CreatedAt: syncTombstoneCreatedAt(tombstone),
				}); err != nil {
					return fmt.Errorf("写入墓碑: %w", err)
				}
				agentID := syncHandlerString(tombstone, "agent_id", "AgentID")
				if table == "agents" {
					agentID = clientID
				}
				changes = append(changes, syncChangeEvent{Table: table, AgentID: agentID})
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return changes, nil
}

func syncTombstoneCreatedAt(tombstone map[string]interface{}) time.Time {
	value := tombstone["created_at"]
	if value == nil {
		value = tombstone["CreatedAt"]
	}
	switch timestamp := value.(type) {
	case float64:
		return time.UnixMilli(int64(timestamp)).UTC()
	case int64:
		return time.UnixMilli(timestamp).UTC()
	case string:
		if parsed, err := time.Parse(time.RFC3339Nano, timestamp); err == nil {
			return parsed.UTC()
		}
	}
	return time.Now().UTC()
}

func (h *SyncV2Handler) downloadScope(userID uint, scope services.SyncScope) (gin.H, []map[string]interface{}) {
	result := gin.H{}
	for _, table := range allowedScopeTables(scope) {
		items := services.FilterSyncItems(scope, table,
			services.SyncFindAllByUserID(registerTableName(table), userID))
		for _, item := range items {
			decryptItem(table, item)
		}
		result[table] = items
	}
	tombstones := services.FilterSyncTombstones(scope,
		services.SyncTombstonesByUserID(userID))
	return result, tombstones
}

func allowedScopeTables(scope services.SyncScope) []string {
	tables := make([]string, 0, len(syncTableNames))
	for table := range syncTableNames {
		if scope.AllowsTable(table) {
			tables = append(tables, table)
		}
	}
	sort.Strings(tables)
	return tables
}

func syncItemsByClientID(items []map[string]interface{}) map[string]map[string]interface{} {
	result := make(map[string]map[string]interface{}, len(items))
	for _, item := range items {
		if clientID := syncClientID(item); clientID != "" {
			result[clientID] = item
		}
	}
	return result
}

func syncClientID(item map[string]interface{}) string {
	return syncHandlerString(item, "client_id", "ClientID")
}

func syncHandlerString(item map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if value, ok := item[key].(string); ok {
			return value
		}
	}
	return ""
}

func syncMapIsItem(candidate, item map[string]interface{}) bool {
	candidateData, _ := json.Marshal(candidate)
	itemData, _ := json.Marshal(item)
	return string(candidateData) == string(itemData)
}

func cloneHandlerMap(item map[string]interface{}) map[string]interface{} {
	copy := make(map[string]interface{}, len(item))
	for key, value := range item {
		copy[key] = value
	}
	return copy
}
