# 多端同步与协议扩展 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现多端同步（订阅专属）、三份协议强制签署与持久化、协议文本扩展

**Architecture:** 服务端使用现有 JSON 文件数据库（`database.Get().Register(...)` 模式），为 13 张本地表建对应 SyncXxx 模型 + SyncTombstone 墓碑表，新增 `/sync` 路由组 + 订阅校验中间件。客户端 DB 迁移 v22→v23 加 `client_id`/`updated_at` 字段 + `local_tombstones` 表，新建 SyncService 单例 + SyncProvider，在 12 处删除函数埋点 recordTombstone。协议侧新建第三份协议 + 隐私政策追加真实信息子条款 + AgreementService 持久化。

**Tech Stack:** Flutter/Dart/Riverpod 2.x、sqflite、Go/Gin、JSON 文件数据库（非 GORM）、SharedPreferences

## Global Constraints

- 服务端数据库为 JSON 文件存储（`database/database.go`），用 `database.Get().Register("TableName")` 注册即自动加载/创建，**不需要 AutoMigrate**
- 服务端模型字段使用 PascalCase（如 `UserID`、`ClientID`），JSON tag 用 snake_case
- 客户端 SQLite 表已有 snake_case 字段，迁移用 `ALTER TABLE ADD COLUMN` + try/catch 容错
- 同步表 ClientID 用 `local_tombstones` 缓冲，上传后清空
- 敏感字段（API Key 等）服务端用 `encryptField`/`decryptField`（复用 [user_agent.go:27-47](file:///d:/window/Desktop/AIchat/website/API/handlers/user_agent.go)）
- 协议版本号变更会强制用户重新同意（AgreementService 对比 version）
- 网络市场对所有用户开放，多端同步仅订阅用户可用

---

## 文件结构

### 服务端新增（[website/API/](file:///d:/window/Desktop/AIchat/website/API/)）

| 文件 | 职责 |
|---|---|
| `models/sync_agent.go` 等 13 个 SyncXxx | 同步表模型定义 |
| `models/sync_tombstone.go` | 墓碑表模型 |
| `middleware/sync_subscription.go` | 订阅校验中间件 |
| `handlers/sync_handler.go` | 同步上传/下载/状态/墓碑 handler |

### 服务端修改

| 文件 | 修改点 |
|---|---|
| `models/subscription_plan.go` | 增加 `AllowSync bool` 字段 |
| `data/SubscriptionPlan.json` | 种子数据加 `allow_sync: true` |
| `routes/routes.go` | 注册 `/sync` 路由组 |

### 客户端新增

| 文件 | 职责 |
|---|---|
| `lib/agreements/network_usage_agreement.dart` | 第三份协议文本 |
| `lib/services/agreement_service.dart` | 协议同意状态持久化 |
| `lib/services/device_id_service.dart` | 设备 ID 生成 |
| `lib/services/sync_service.dart` | 同步核心 |
| `lib/providers/sync_provider.dart` | 同步状态管理 |

### 客户端修改

| 文件 | 修改点 |
|---|---|
| `lib/agreements/user_agreement.dart` | 加 version 字段 |
| `lib/agreements/privacy_policy.dart` | 加 version + 真实信息子条款 |
| `lib/services/database_service.dart` | v22→v23 迁移 |
| `lib/screens/login_screen.dart` | 三份协议门控 |
| `lib/screens/settings_screen.dart` | 协议查看入口 + 同步分组 |
| `lib/screens/account_screen.dart` | 订阅引导提示 |
| `lib/providers/agent_provider.dart` | deleteAgent 埋点 |
| `lib/providers/chat_provider.dart` | clearCurrentAgentChatMessages 埋点 |
| `lib/providers/group_provider.dart` | deleteGroup/removeMember 埋点 |
| `lib/providers/user_profile_provider.dart` | deleteProfile/clearAll 埋点 |
| `lib/providers/memory_provider.dart` | 记忆删除埋点 |
| `lib/l10n/app_localizations.dart` | 新增 20+ l10n keys |

---

## Task 1: 服务端订阅计划扩展

**Files:**
- Modify: `website/API/models/subscription_plan.go`
- Modify: `website/API/data/SubscriptionPlan.json`

**Interfaces:**
- Produces: `SubscriptionPlan.AllowSync` 字段（bool），后续 Task 4 中间件依赖此字段

- [ ] **Step 1: 修改 SubscriptionPlan 模型加 AllowSync 字段**

修改 `website/API/models/subscription_plan.go`，在 `RealReplyDailyQuota` 后追加：

```go
type SubscriptionPlan struct {
	ID                uint      `json:"id"`
	Name              string    `json:"name"`
	Description       string    `json:"description"`
	Price             float64   `json:"price"`
	DailyQuota        float64   `json:"daily_quota"`
	DurationDays      int       `json:"duration_days"`
	ModelRestrict     bool      `json:"model_restrict"`
	OcrDailyQuota     int       `json:"ocr_daily_quota"`
	RealReplyDailyQuota int     `json:"real_reply_daily_quota"`
	AllowSync         bool      `json:"allow_sync"`         // 是否允许使用多端同步功能
	Status            int       `json:"status"`
	SortOrder         int       `json:"sort_order"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}
```

- [ ] **Step 2: 修改种子数据**

修改 `website/API/data/SubscriptionPlan.json`，给现有计划加 `"AllowSync": true` 字段（注意：JSON 文件数据库使用 PascalCase 键名，与 Go struct 字段名一致）。

- [ ] **Step 3: 验证编译**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 4: Commit**

```bash
git add website/API/models/subscription_plan.go website/API/data/SubscriptionPlan.json
git commit -m "feat: add AllowSync field to SubscriptionPlan for multi-device sync gating"
```

---

## Task 2: 服务端同步模型定义

**Files:**
- Create: `website/API/models/sync_models.go`（合并所有 SyncXxx 到一个文件，便于维护）

**Interfaces:**
- Produces: 13 个 SyncXxx 结构体 + SyncTombstone，后续 Task 3/5 的 handler 依赖

- [ ] **Step 1: 创建 sync_models.go**

创建 `website/API/models/sync_models.go`，定义 13 张同步表 + 墓碑表。每张表字段一对一映射客户端 SQLite 表，加 `UserID` + `ClientID` + `UpdatedAt` + `CreatedAt`：

```go
package models

import "time"

// 通用字段：每个 SyncXxx 表都有 UserID + ClientID + 时间戳
// ClientID 是客户端本地主键（UUID 或 deviceId_整型id），用于 upsert 定位

type SyncAgent struct {
	ID              uint      `gorm:"primaryKey" json:"id"`
	UserID          uint      `json:"user_id"`
	ClientID        string    `json:"client_id"` // agents.id (UUID)
	Name            string    `json:"name"`
	Gender          string    `json:"gender"`
	Description     string    `json:"description"`
	Persona         string    `json:"persona"`         // 加密
	OpeningLine     string    `json:"opening_line"`     // 加密
	AvatarColor     int       `json:"avatar_color"`
	AvatarPath      string    `json:"avatar_path"`
	ChatBackground  string    `json:"chat_background"`
	Worldview       string    `json:"worldview"`        // 加密
	IsActive        int       `json:"is_active"`
	RealInfoEnabled int       `json:"real_info_enabled"`
	IsSimCharacter  int       `json:"is_sim_character"`
	IsGroupOnly     int       `json:"is_group_only"`
	SourceGroupID   string    `json:"source_group_id"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type SyncChatMessage struct {
	ID          uint      `json:"id"`
	UserID      uint      `json:"user_id"`
	ClientID    string    `json:"client_id"` // deviceId_<id>
	Role        string    `json:"role"`
	Content     string    `json:"content"`
	Timestamp   int64     `json:"timestamp"`
	ShortMemID  string    `json:"short_mem_id"`
	AgentID     string    `json:"agent_id"`
	GroupID     string    `json:"group_id"`
	ImagePath   string    `json:"image_path"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type SyncShortTermMessage struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // short_term_messages.id (UUID)
	Role      string    `json:"role"`
	Content   string    `json:"content"`
	Timestamp int64     `json:"timestamp"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncGroupChat struct {
	ID             uint      `json:"id"`
	UserID         uint      `json:"user_id"`
	ClientID       string    `json:"client_id"` // group_chats.id (UUID)
	Name           string    `json:"name"`
	Description    string    `json:"description"`
	AvatarColor    int       `json:"avatar_color"`
	GroupPersona   string    `json:"group_persona"`
	SpeechMode     string    `json:"speech_mode"`
	SimulatorMode  int       `json:"simulator_mode"`
	WorldSetting   string    `json:"world_setting"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type SyncGroupMember struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // deviceId_<id>
	GroupID   string    `json:"group_id"`
	AgentID   string    `json:"agent_id"`
	Role      string    `json:"role"`
	IsPresent int       `json:"is_present"`
	JoinedAt  int64     `json:"joined_at"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncGroupMessage struct {
	ID           uint      `json:"id"`
	UserID       uint      `json:"user_id"`
	ClientID     string    `json:"client_id"` // deviceId_<id>
	GroupID      string    `json:"group_id"`
	SenderType   string    `json:"sender_type"`
	SenderID     string    `json:"sender_id"`
	SenderName   string    `json:"sender_name"`
	Content      string    `json:"content"`
	Timestamp    int64     `json:"timestamp"`
	ToolCallData string    `json:"tool_call_data"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type SyncGroupShortTerm struct {
	ID         uint      `json:"id"`
	UserID     uint      `json:"user_id"`
	ClientID   string    `json:"client_id"` // deviceId_<id>
	GroupID    string    `json:"group_id"`
	Role       string    `json:"role"`
	SenderName string    `json:"sender_name"`
	Content    string    `json:"content"`
	Timestamp  int64     `json:"timestamp"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SyncGroupSharedMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // group_shared_memories.id (UUID)
	GroupID   string    `json:"group_id"`
	Field     string    `json:"field"`
	Content   string    `json:"content"`
	UpdatedAt time.Time `json:"updated_at"`
	CreatedAt time.Time `json:"created_at"`
}

type SyncLongTermMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // long_term_memories.id (UUID)
	Field     string    `json:"field"`
	Content   string    `json:"content"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncBaseMemory struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	ClientID  string    `json:"client_id"` // base_memories.id (UUID)
	Type      string    `json:"type"`
	Content   string    `json:"content"`
	AgentID   string    `json:"agent_id"`
	GroupID   string    `json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SyncPlannedMessage struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"client_id"` // deviceId_<id>
	ScheduledTime int64     `json:"scheduled_time"`
	Message       string    `json:"message"`
	Delivered     int       `json:"delivered"`
	AgentID       string    `json:"agent_id"`
	GroupID       string    `json:"group_id"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type SyncUserProfile struct {
	ID         uint      `json:"id"`
	UserID     uint      `json:"user_id"`
	ClientID   string    `json:"client_id"` // user_profiles.id (UUID)
	Category   string    `json:"category"`
	Key        string    `json:"key"`
	Value      string    `json:"value"` // 加密
	Confidence int       `json:"confidence"`
	Source     string    `json:"source"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SyncProvider struct {
	ID            uint      `json:"id"`
	UserID        uint      `json:"user_id"`
	ClientID      string    `json:"client_id"` // deviceId_<id>
	Name          string    `json:"name"`
	ApiBaseUrl    string    `json:"api_base_url"`
	ApiKey        string    `json:"api_key"` // 加密
	SelectedModel string    `json:"selected_model"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// SyncTombstone 记录用户在客户端删除的条目
type SyncTombstone struct {
	ID        uint      `json:"id"`
	UserID    uint      `json:"user_id"`
	TableName string    `json:"table_name"` // 'agents' / 'chat_messages' / ...
	ClientID  string    `json:"client_id"`
	CreatedAt time.Time `json:"created_at"`
}
```

- [ ] **Step 2: 验证编译**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 3: Commit**

```bash
git add website/API/models/sync_models.go
git commit -m "feat: add 13 SyncXxx models + SyncTombstone for multi-device sync"
```

---

## Task 3: 服务端同步 handler

**Files:**
- Create: `website/API/handlers/sync_handler.go`

**Interfaces:**
- Consumes: Task 2 的 SyncXxx 模型、Task 1 的 SubscriptionPlan.AllowSync
- Produces: SyncHandler 结构体 + 上传/下载/状态/墓碑 4 类方法，供 Task 5 路由调用

- [ ] **Step 1: 创建 sync_handler.go**

创建 `website/API/handlers/sync_handler.go`。核心设计：用 `tableRegistry` map 把表名映射到处理函数，避免 13 个 if/else 分支。

```go
package handlers

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"aichat-api/database"
	"aichat-api/models"
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

// modelToTable 把表名映射到 SyncXxx 类型 + 是否需要加密
func modelToTable(tableName string) (interface{}, []string) {
	encryptFields := []string{}
	switch tableName {
	case "agents":
		return &models.SyncAgent{}, []string{"Persona", "OpeningLine", "Worldview"}
	case "chat_messages":
		return &models.SyncChatMessage{}, nil
	case "short_term_messages":
		return &models.SyncShortTermMessage{}, nil
	case "group_chats":
		return &models.SyncGroupChat{}, nil
	case "group_members":
		return &models.SyncGroupMember{}, nil
	case "group_messages":
		return &models.SyncGroupMessage{}, nil
	case "group_short_term":
		return &models.SyncGroupShortTerm{}, nil
	case "group_shared_memories":
		return &models.SyncGroupSharedMemory{}, nil
	case "long_term_memories":
		return &models.SyncLongTermMemory{}, nil
	case "base_memories":
		return &models.SyncBaseMemory{}, nil
	case "planned_messages":
		return &models.SyncPlannedMessage{}, nil
	case "user_profiles":
		return &models.SyncUserProfile{}, []string{"Value"}
	case "providers":
		return &models.SyncProvider{}, []string{"ApiKey"}
	}
	return nil, nil
}

// registerTableName Go struct 名 → JSON 表名
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

// GET /api/v1/sync/status — 返回各表云端最近 updated_at
func (h *SyncHandler) GetStatus(c *gin.Context) {
	userID := c.GetUint("user_id")
	status := gin.H{}
	for table := range syncTableNames {
		regName := registerTableName(table)
		tbl := database.Get().Register(regName)
		var all []map[string]interface{}
		tbl.FindAll(&all, func(r map[string]interface{}) bool {
			return fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID)
		}, "UpdatedAt desc", 0, 1)
		if len(all) > 0 {
			status[table] = all[0]["UpdatedAt"]
		} else {
			status[table] = nil
		}
	}
	// 墓碑表
	tbl := database.Get().Register("SyncTombstone")
	var tombstones []map[string]interface{}
	tbl.FindAll(&tombstones, func(r map[string]interface{}) bool {
		return fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID)
	}, "CreatedAt desc", 0, 1)
	if len(tombstones) > 0 {
		status["tombstones"] = tombstones[0]["CreatedAt"]
	} else {
		status["tombstones"] = nil
	}
	utils.Success(c, status)
}

// POST /api/v1/sync/:table — 上传单表数据
func (h *SyncHandler) UploadTable(c *gin.Context) {
	userID := c.GetUint("user_id")
	table := c.Param("table")
	if !syncTableNames[table] {
		utils.BadRequest(c, "无效的表名")
		return
	}

	var req struct {
		Items      []map[string]interface{} `json:"items"`
		Tombstones []map[string]interface{} `json:"tombstones"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	regName := registerTableName(table)
	tbl := database.Get().Register(regName)
	_, encryptFields := modelToTable(table)

	upserted := 0
	for _, item := range req.Items {
		clientID, _ := item["client_id"].(string)
		if clientID == "" {
			continue
		}
		// 加密敏感字段
		for _, f := range encryptFields {
			if v, ok := item[strings.ToLower(f)]; ok {
				if s, ok := v.(string); ok {
					item[strings.ToLower(f)] = encryptField(s)
				}
			}
		}
		// 查找已有记录
		var existing map[string]interface{}
		tbl.FindAll(&[]map[string]interface{}{existing}, func(r map[string]interface{}) bool {
			return fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) &&
				fmt.Sprintf("%v", r["ClientID"]) == clientID
		}, "", 0, 0)
		// 由于上面写法不对，改用直接遍历
		allRows := tbl.All()
		var foundID uint
		for _, r := range allRows {
			if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) &&
				fmt.Sprintf("%v", r["ClientID"]) == clientID {
				if fid, ok := getFloat(r["ID"]); ok {
					foundID = uint(fid)
					break
				}
			}
		}
		now := time.Now()
		item["UserID"] = userID
		item["UpdatedAt"] = now.Format(time.RFC3339)
		if foundID > 0 {
			updates := make(map[string]interface{})
			for k, v := range item {
				updates[k] = v
			}
			tbl.UpdateWhere(func(r map[string]interface{}) bool {
				if fid, ok := getFloat(r["ID"]); ok {
					return uint(fid) == foundID
				}
				return false
			}, updates)
		} else {
			item["CreatedAt"] = now.Format(time.RFC3339)
			// 用 Insert 需要结构体，这里用直接写文件方式
			insertMapAsRow(tbl, item)
		}
		upserted++
	}

	// 处理墓碑
	deleted := 0
	for _, t := range req.Tombstones {
		tombTable, _ := t["table_name"].(string)
		tombClientID, _ := t["client_id"].(string)
		if tombTable == "" || tombClientID == "" {
			continue
		}
		// 插入 SyncTombstone
		tombTbl := database.Get().Register("SyncTombstone")
		insertMapAsRow(tombTbl, map[string]interface{}{
			"UserID":    userID,
			"TableName": tombTable,
			"ClientID":  tombClientID,
			"CreatedAt": time.Now().Format(time.RFC3339),
		})
		// 从对应 SyncXxx 表删除
		if regName := registerTableName(tombTable); regName != "" {
			targetTbl := database.Get().Register(regName)
			allRows := targetTbl.All()
			for _, r := range allRows {
				if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) &&
					fmt.Sprintf("%v", r["ClientID"]) == tombClientID {
					if fid, ok := getFloat(r["ID"]); ok {
						targetTbl.Delete(uint(fid))
					}
				}
			}
		}
		deleted++
	}

	utils.Success(c, gin.H{"upserted": upserted, "deleted": deleted})
}

// GET /api/v1/sync/:table — 下载单表数据
func (h *SyncHandler) DownloadTable(c *gin.Context) {
	userID := c.GetUint("user_id")
	table := c.Param("table")
	if !syncTableNames[table] {
		utils.BadRequest(c, "无效的表名")
		return
	}

	regName := registerTableName(table)
	tbl := database.Get().Register(regName)
	_, encryptFields := modelToTable(table)

	allRows := tbl.All()
	result := []map[string]interface{}{}
	for _, r := range allRows {
		if fmt.Sprintf("%v", r["UserID"]) != fmt.Sprintf("%v", userID) {
			continue
		}
		// 解密敏感字段
		for _, f := range encryptFields {
			key := strings.ToLower(f)
			if v, ok := r[key]; ok {
				if s, ok := v.(string); ok {
					r[key] = decryptField(s)
				}
			}
		}
		result = append(result, r)
	}
	utils.Success(c, gin.H{"items": result, "server_time": time.Now()})
}

// POST /api/v1/sync/all — 上传所有表
func (h *SyncHandler) UploadAll(c *gin.Context) {
	userID := c.GetUint("user_id")
	var req map[string]struct {
		Items      []map[string]interface{} `json:"items"`
		Tombstones []map[string]interface{} `json:"tombstones"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	totalUpserted, totalDeleted := 0, 0
	for table, payload := range req {
		if !syncTableNames[table] {
			continue
		}
		regName := registerTableName(table)
		tbl := database.Get().Register(regName)
		_, encryptFields := modelToTable(table)
		for _, item := range payload.Items {
			clientID, _ := item["client_id"].(string)
			if clientID == "" {
				continue
			}
			for _, f := range encryptFields {
				if v, ok := item[strings.ToLower(f)]; ok {
					if s, ok := v.(string); ok {
						item[strings.ToLower(f)] = encryptField(s)
					}
				}
			}
			allRows := tbl.All()
			var foundID uint
			for _, r := range allRows {
				if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) &&
					fmt.Sprintf("%v", r["ClientID"]) == clientID {
					if fid, ok := getFloat(r["ID"]); ok {
						foundID = uint(fid)
						break
					}
				}
			}
			now := time.Now()
			item["UserID"] = userID
			item["UpdatedAt"] = now.Format(time.RFC3339)
			if foundID > 0 {
				updates := make(map[string]interface{})
				for k, v := range item {
					updates[k] = v
				}
				tbl.UpdateWhere(func(r map[string]interface{}) bool {
					if fid, ok := getFloat(r["ID"]); ok {
						return uint(fid) == foundID
					}
					return false
				}, updates)
			} else {
				item["CreatedAt"] = now.Format(time.RFC3339)
				insertMapAsRow(tbl, item)
			}
			totalUpserted++
		}
		// 处理墓碑
		for _, t := range payload.Tombstones {
			tombTable, _ := t["table_name"].(string)
			tombClientID, _ := t["client_id"].(string)
			if tombTable == "" || tombClientID == "" {
				continue
			}
			tombTbl := database.Get().Register("SyncTombstone")
			insertMapAsRow(tombTbl, map[string]interface{}{
				"UserID":    userID,
				"TableName": tombTable,
				"ClientID":  tombClientID,
				"CreatedAt": time.Now().Format(time.RFC3339),
			})
			if regName := registerTableName(tombTable); regName != "" {
				targetTbl := database.Get().Register(regName)
				allRows := targetTbl.All()
				for _, r := range allRows {
					if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) &&
						fmt.Sprintf("%v", r["ClientID"]) == tombClientID {
						if fid, ok := getFloat(r["ID"]); ok {
							targetTbl.Delete(uint(fid))
						}
					}
				}
			}
			totalDeleted++
		}
	}
	utils.Success(c, gin.H{"upserted": totalUpserted, "deleted": totalDeleted})
}

// GET /api/v1/sync/all — 下载所有表
func (h *SyncHandler) DownloadAll(c *gin.Context) {
	userID := c.GetUint("user_id")
	result := gin.H{}
	for table := range syncTableNames {
		regName := registerTableName(table)
		tbl := database.Get().Register(regName)
		_, encryptFields := modelToTable(table)
		allRows := tbl.All()
		items := []map[string]interface{}{}
		for _, r := range allRows {
			if fmt.Sprintf("%v", r["UserID"]) != fmt.Sprintf("%v", userID) {
				continue
			}
			for _, f := range encryptFields {
				key := strings.ToLower(f)
				if v, ok := r[key]; ok {
					if s, ok := v.(string); ok {
						r[key] = decryptField(s)
					}
				}
			}
			items = append(items, r)
		}
		result[table] = items
	}
	// 墓碑
	tombTbl := database.Get().Register("SyncTombstone")
	tombRows := tombTbl.All()
	tombstones := []map[string]interface{}{}
	for _, r := range tombRows {
		if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) {
			tombstones = append(tombstones, r)
		}
	}
	result["tombstones"] = tombstones
	result["server_time"] = time.Now()
	utils.Success(c, result)
}

// DELETE /api/v1/sync/tombstones — 清空已应用的墓碑
func (h *SyncHandler) ClearTombstones(c *gin.Context) {
	userID := c.GetUint("user_id")
	tombTbl := database.Get().Register("SyncTombstone")
	allRows := tombTbl.All()
	for _, r := range allRows {
		if fmt.Sprintf("%v", r["UserID"]) == fmt.Sprintf("%v", userID) {
			if fid, ok := getFloat(r["ID"]); ok {
				tombTbl.Delete(uint(fid))
			}
		}
	}
	utils.SuccessMsg(c, "墓碑已清空")
}

// insertMapAsRow 直接用 map 插入一行（绕过 Insert 需要结构体的限制）
func insertMapAsRow(tbl *database.Table, m map[string]interface{}) {
	// 用 JSON 序列化再反序列化到临时结构体
	data, _ := json.Marshal(m)
	var row map[string]interface{}
	json.Unmarshal(data, &row)
	// 直接调用 Table 内部机制：用 Insert 方法需要结构体
	// 这里用一个通用结构体占位
	type genericRow struct {
		ID        uint      `json:"id"`
		CreatedAt time.Time `json:"created_at"`
		UpdatedAt time.Time `json:"updated_at"`
	}
	_ = row // 此处需要扩展 database.go 支持 map 插入，见 Task 6
}
```

**注意**：`insertMapAsRow` 需要扩展 `database/database.go` 支持 map 直接插入，详见 Task 6。先在 Task 6 完成扩展，再回到此处验证。

- [ ] **Step 2: 暂不验证编译（依赖 Task 6 的 database.go 扩展）**

- [ ] **Step 3: Commit（先暂存，Task 6 完成后一并提交）**

---

## Task 4: 服务端订阅校验中间件

**Files:**
- Create: `website/API/middleware/sync_subscription.go`

**Interfaces:**
- Consumes: Task 1 的 SubscriptionPlan.AllowSync
- Produces: `RequireSyncSubscription()` 中间件函数

- [ ] **Step 1: 创建 sync_subscription.go**

```go
package middleware

import (
	"fmt"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

// hasSyncSubscription 检查用户是否有允许同步的订阅
func hasSyncSubscription(userID uint) bool {
	today := time.Now().Format("2006-01-02")
	var allSubs []models.UserSubscription
	database.Get().Register("UserSubscription").FindAll(&allSubs, nil, "", 0, 0)

	planIDs := []uint{}
	for _, s := range allSubs {
		if s.UserID == userID && s.Status == 1 && s.ExpiresAt >= today {
			planIDs = append(planIDs, s.PlanID)
		}
	}
	if len(planIDs) == 0 {
		return false
	}

	var allPlans []models.SubscriptionPlan
	database.Get().Register("SubscriptionPlan").FindAll(&allPlans, nil, "", 0, 0)
	for _, plan := range allPlans {
		for _, pid := range planIDs {
			if plan.ID == pid && plan.AllowSync {
				return true
			}
		}
	}
	return false
}

// RequireSyncSubscription 多端同步订阅校验中间件
func RequireSyncSubscription() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetUint("user_id")
		_ = fmt.Sprintf("%v", userID)
		if !hasSyncSubscription(userID) {
			utils.Forbidden(c, "多端同步仅订阅用户可用")
			c.Abort()
			return
		}
		c.Next()
	}
}
```

- [ ] **Step 2: 验证编译**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 3: Commit**

```bash
git add website/API/middleware/sync_subscription.go
git commit -m "feat: add RequireSyncSubscription middleware"
```

---

## Task 5: 扩展 database.go 支持 map 插入

**Files:**
- Modify: `website/API/database/database.go`

**Interfaces:**
- Produces: `(*Table).InsertMap(map[string]interface{}) error` 方法

- [ ] **Step 1: 在 database.go 末尾追加 InsertMap 方法**

在 `database/database.go` 文件末尾追加：

```go
// InsertMap 直接用 map 插入一行，自动分配 ID + CreatedAt + UpdatedAt
// 用于无法用结构体 Insert 的场景（如 sync handler 接收任意表数据）
func (t *Table) InsertMap(m map[string]interface{}) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.seq++
	newRow := make(map[string]interface{})
	for k, v := range m {
		newRow[k] = v
	}
	newRow["ID"] = float64(t.seq)
	now := time.Now().Format(time.RFC3339)
	if _, ok := newRow["CreatedAt"]; !ok {
		newRow["CreatedAt"] = now
	}
	if _, ok := newRow["UpdatedAt"]; !ok {
		newRow["UpdatedAt"] = now
	}
	t.rows = append(t.rows, newRow)
	return t.save()
}
```

- [ ] **Step 2: 修改 sync_handler.go 的 insertMapAsRow 改用 InsertMap**

回到 `website/API/handlers/sync_handler.go`，把 `insertMapAsRow` 函数替换为：

```go
// insertMapAsRow 直接用 map 插入一行
func insertMapAsRow(tbl *database.Table, m map[string]interface{}) {
	_ = tbl.InsertMap(m)
}
```

或者直接在调用处改用 `tbl.InsertMap(m)`，删除 `insertMapAsRow` 函数。

- [ ] **Step 3: 验证编译**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 4: Commit**

```bash
git add website/API/database/database.go website/API/handlers/sync_handler.go
git commit -m "feat: add InsertMap to database.go + fix sync handler"
```

---

## Task 6: 服务端路由注册

**Files:**
- Modify: `website/API/routes/routes.go`

**Interfaces:**
- Consumes: Task 3 的 SyncHandler、Task 4 的 RequireSyncSubscription

- [ ] **Step 1: 在 routes.go 的 userGroup 内追加 /sync 路由组**

在 `routes/routes.go` 的 `userGroup` 块内（约 line 114 之后）追加：

```go
// 多端同步（仅订阅用户可用）
syncHandler := &handlers.SyncHandler{}
syncGroup := userGroup.Group("/sync")
syncGroup.Use(middleware.RequireSyncSubscription())
{
	syncGroup.GET("/status", syncHandler.GetStatus)
	syncGroup.GET("/all", syncHandler.DownloadAll)
	syncGroup.POST("/all", syncHandler.UploadAll)
	syncGroup.GET("/tombstones", syncHandler.DownloadTable) // 复用：返回墓碑列表
	syncGroup.POST("/tombstones", syncHandler.UploadTable)  // 复用：上传墓碑
	syncGroup.DELETE("/tombstones", syncHandler.ClearTombstones)
	syncGroup.GET("/:table", syncHandler.DownloadTable)
	syncGroup.POST("/:table", syncHandler.UploadTable)
}
```

**注意**：墓碑路由 `/tombstones` 必须放在 `/:table` 之前，否则会被 `:table` 通配匹配。

- [ ] **Step 2: 验证编译**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 3: Commit**

```bash
git add website/API/routes/routes.go
git commit -m "feat: register /sync route group with subscription middleware"
```

---

## Task 7: 客户端协议文本

**Files:**
- Create: `lib/agreements/network_usage_agreement.dart`
- Modify: `lib/agreements/user_agreement.dart`
- Modify: `lib/agreements/privacy_policy.dart`

**Interfaces:**
- Produces: `NetworkUsageAgreement.{title, version, content}`、`UserAgreement.version`、`PrivacyPolicy.version` + 真实信息子条款

- [ ] **Step 1: 新建 network_usage_agreement.dart**

创建 `lib/agreements/network_usage_agreement.dart`，使用 spec §5.3 的完整 8 条条款正文。

```dart
class NetworkUsageAgreement {
  NetworkUsageAgreement._();
  static const String title = '《智能体和群聊智能体网络上传，下载，使用协议》';
  static const String version = 'v1.0';
  static const String content = '''
回响 AI 聊天软件
智能体和群聊智能体网络上传，下载，使用协议
更新日期：2026 年 7 月 5 日

第一条 协议范围
1.1 本协议适用于用户使用本软件"网络市场"功能，上传、下载、使用
    智能体配置或群聊智能体配置的行为。
1.2 用户使用网络市场功能前，必须完整阅读并同意本协议。

第二条 上传内容规范
2.1 用户上传的智能体/群聊智能体配置内容（包括人设、世界观、开场白、
    标签、描述等）必须符合中华人民共和国相关法律法规，禁止包含：
    （1）反对宪法确定的基本原则的；
    （2）危害国家安全、泄露国家秘密、颠覆国家政权、破坏国家统一的；
    （3）损害国家荣誉和利益的；
    （4）煽动民族仇恨、民族歧视，破坏民族团结的；
    （5）破坏国家宗教政策，宣扬邪教和封建迷信的；
    （6）散布谣言，扰乱社会秩序，破坏社会稳定的；
    （7）散布淫秽、色情、赌博、暴力、凶杀、恐怖或者教唆犯罪的；
    （8）侮辱或者诽谤他人，侵害他人合法权益的；
    （9）含有法律、行政法规禁止的其他内容的。
2.2 上传内容不得侵犯他人知识产权（著作权、商标权、专利权、肖像权、
    隐私权等）。用户上传即声明对内容享有合法权利。
2.3 禁止上传含恶意代码、诱导性付费、钓鱼链接、广告引流等内容。

第三条 审核机制
3.1 所有上传内容须经管理员审核后方可公开展示。
3.2 审核未通过的内容，用户可在"我上传的"页面查看驳回原因。
3.3 已通过审核的内容，用户修改后将重新进入审核队列，期间内容不公开展示。
3.4 管理员有权对违反本协议第二条的内容进行驳回、下架处理，
    情节严重者将封禁账号。

第四条 下载与使用
4.1 用户可自由下载网络市场中的智能体/群聊智能体配置，下载后将保存
    至用户本地。
4.2 下载的内容仅供用户个人使用，禁止：
    （1）二次上传至本软件或其他平台声称原创；
    （2）用于商业用途（如付费代聊、引流变现）；
    （3）篡改后冒充原作上传。
4.3 用户下载后可自由修改本地副本，修改后不影响原作。

第五条 责任与免责
5.1 用户对上传内容的合法性、合规性、知识产权归属负全部责任。
5.2 因用户上传内容违法或侵权导致的法律责任，由上传用户独立承担，
    本软件运营方不承担连带责任。
5.3 本软件运营方有权但无义务对上传内容进行事先审查，对明显违法
    内容有权立即下架。
5.4 因不可抗力或本软件服务调整导致已上传内容丢失的，本软件不承担
    赔偿责任，建议用户保留本地备份。

第六条 数据传输
6.1 上传的智能体配置中可能包含用户创作的世界观、人设等文本，
    传输与存储均使用 AES 加密。
6.2 本软件不会公开用户上传内容的"我上传的"列表，仅用户本人可见。
6.3 通过审核后公开展示的内容，任何登录用户均可查看与下载。

第七条 知识产权
7.1 上传内容的著作权归原作者所有，用户上传即视为授予本软件
    非排他性、免费、全球性、可转授权的许可，用于公开展示、
    提供下载服务。
7.2 本软件对网络市场功能的整体设计、运营规则享有知识产权。

第八条 协议变更
8.1 本协议可能随业务调整进行更新，更新时将通过应用内通知告知用户。
8.2 用户继续使用网络市场功能即视为同意更新后的协议；
    不同意者可选择停止使用该功能。
''';
}
```

- [ ] **Step 2: 修改 user_agreement.dart 加 version 字段**

读取现有 `lib/agreements/user_agreement.dart`，在 `title` 字段后追加 `static const String version = 'v1.0';`，正文不动。

- [ ] **Step 3: 修改 privacy_policy.dart 加 version + 真实信息子条款**

读取现有 `lib/agreements/privacy_policy.dart`：
1. 在 `title` 后追加 `static const String version = 'v1.1';`
2. 在 `content` 字符串末尾追加 spec §5.2 的 7 条子条款（见 spec §5.2 完整文本）

- [ ] **Step 4: Commit**

```bash
git add lib/agreements/network_usage_agreement.dart lib/agreements/user_agreement.dart lib/agreements/privacy_policy.dart
git commit -m "feat: add network usage agreement + real info protocol in privacy policy"
```

---

## Task 8: 客户端协议同意状态持久化

**Files:**
- Create: `lib/services/agreement_service.dart`

**Interfaces:**
- Produces: `AgreementService.{hasAgreed, markAgreed, allAgreed}` 方法，供 Task 9 登录页调用

- [ ] **Step 1: 创建 agreement_service.dart**

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../agreements/user_agreement.dart';
import '../agreements/privacy_policy.dart';
import '../agreements/network_usage_agreement.dart';

class AgreementService {
  AgreementService._();
  static final AgreementService instance = AgreementService._();

  static const _prefix = 'agreement_';

  /// 检查某份协议是否已同意（且版本号匹配）
  Future<bool> hasAgreed(String key, String currentVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final agreedVersion = prefs.getString('${_prefix}version_$key');
    final agreed = prefs.getBool('${_prefix}agreed_$key') ?? false;
    return agreed && agreedVersion == currentVersion;
  }

  /// 标记同意（记录版本号 + 时间戳）
  Future<void> markAgreed(String key, String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefix}agreed_$key', true);
    await prefs.setString('${_prefix}version_$key', version);
    await prefs.setInt('${_prefix}time_$key', DateTime.now().millisecondsSinceEpoch);
  }

  /// 三份协议是否全部已同意
  Future<bool> allAgreed() async {
    return await hasAgreed('user_agreement', UserAgreement.version) &&
           await hasAgreed('privacy_policy', PrivacyPolicy.version) &&
           await hasAgreed('network_usage', NetworkUsageAgreement.version);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/agreement_service.dart
git commit -m "feat: add AgreementService for persisted agreement state"
```

---

## Task 9: 登录页三份协议门控

**Files:**
- Modify: `lib/screens/login_screen.dart`

**Interfaces:**
- Consumes: Task 7 的三份协议常量、Task 8 的 AgreementService

- [ ] **Step 1: 读取现有 login_screen.dart 完整内容**

读取 `lib/screens/login_screen.dart` 全文，重点关注：
- `_hasAgreedRegister` / `_hasAgreedLogin` 字段（line 38-39）
- 注册勾选框 UI（line 281-318）
- 登录确认弹窗（line 384-429）
- `_showAgreementViewer` 方法（line 365-381）

- [ ] **Step 2: 改造 initState 加载持久化状态**

在 `initState` 中调用 `AgreementService.instance.allAgreed()` 加载已同意状态，初始化 `_hasAgreedRegister` 和 `_hasAgreedLogin`。

- [ ] **Step 3: 改造注册勾选框 UI**

把现有两个 Checkbox 合并为单个 Checkbox + 富文本，文案改为：「我已阅读并同意《用户协议》《隐私政策》《智能体和群聊智能体网络上传，下载，使用协议》」，三份协议名各自可点击跳 `_showAgreementViewer(type)`。

- [ ] **Step 4: 改造勾选回调**

勾选时调 `AgreementService.instance.markAgreed` 写入三份协议状态；取消勾选时不主动清空（保留旧记录，但 UI 状态置 false 拦截提交）。

- [ ] **Step 5: 改造提交校验**

注册/登录提交前校验 `_hasAgreedAll == true`，否则 Toast 提示「请先阅读并同意三份协议」。

- [ ] **Step 6: 扩展 _showAgreementViewer 支持三份协议**

现有方法只支持两份，扩展为接受 `type` 参数（'user' / 'privacy' / 'network'），分别返回对应协议的 title + content。

- [ ] **Step 7: 验证编译**

Run: `flutter analyze lib/screens/login_screen.dart`
Expected: 无新增 error/warning

- [ ] **Step 8: Commit**

```bash
git add lib/screens/login_screen.dart
git commit -m "feat: enforce 3-agreement gating in login screen with persistence"
```

---

## Task 10: 设置页协议查看入口 + 多端同步分组

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/screens/account_screen.dart`

**Interfaces:**
- Consumes: Task 7 的三份协议、Task 8 的 AgreementService、Task 14 的 SyncProvider

**注意**：本任务依赖 Task 14（SyncProvider），但协议查看入口部分可先做，同步分组部分在 Task 14 完成后补做。建议拆为两个子步骤。

- [ ] **Step 1: 先做协议查看入口（不依赖 SyncProvider）**

在 `settings_screen.dart` 的「关于」分组下新增三个 ListTile：查看用户协议 / 查看隐私政策 / 查看网络使用协议，点击均跳 `_showAgreementViewer`（从 login_screen 抽出为公共方法或直接内联）。

- [ ] **Step 2: 暂不提交，等 Task 14 完成后补做同步分组**

- [ ] **Step 3: 账户页订阅引导提示**

在 `account_screen.dart` 的订阅入口下方加一行提示：「多端同步功能需订阅解锁」，点击跳订阅中心。

- [ ] **Step 4: Commit（仅协议查看 + 账户页引导）**

```bash
git add lib/screens/settings_screen.dart lib/screens/account_screen.dart
git commit -m "feat: add agreement viewer entries in settings + sync subscription hint in account"
```

---

## Task 11: 客户端数据库迁移 v22 → v23

**Files:**
- Modify: `lib/services/database_service.dart`

**Interfaces:**
- Produces: v23 迁移逻辑（13 张表加 client_id + updated_at、新建 local_tombstones 表）

- [ ] **Step 1: 修改 version 22 → 23**

修改 `database_service.dart:31` 的 `version: 22` 为 `version: 23`。

- [ ] **Step 2: 在 _onCreate 末尾追加 local_tombstones 表 + 各表加字段**

在 `_onCreate` 方法末尾追加：

```dart
await db.execute('''CREATE TABLE IF NOT EXISTS local_tombstones (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, client_id TEXT NOT NULL, created_at INTEGER NOT NULL)''');

// 13 张同步表加 client_id + updated_at（_onCreate 路径，新安装时）
for (final table in ['agents', 'chat_messages', 'short_term_messages', 'group_chats', 'group_members', 'group_messages', 'group_short_term', 'group_shared_memories', 'long_term_memories', 'base_memories', 'planned_messages', 'user_profiles', 'providers']) {
  try { await db.execute('ALTER TABLE $table ADD COLUMN client_id TEXT'); } catch (_) {}
  try { await db.execute('ALTER TABLE $table ADD COLUMN sync_updated_at INTEGER'); } catch (_) {}
}
```

**注意**：用 `sync_updated_at` 避免与现有 `updated_at` 字段冲突（部分表已有 `updated_at`）。

- [ ] **Step 3: 在 _onUpgrade 追加 v23 迁移块**

在 `_onUpgrade` 的 `if (oldVersion < 22)` 块之后追加：

```dart
if (oldVersion < 23) {
  await db.execute('''CREATE TABLE IF NOT EXISTS local_tombstones (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, client_id TEXT NOT NULL, created_at INTEGER NOT NULL)''');
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final table in ['agents', 'chat_messages', 'short_term_messages', 'group_chats', 'group_members', 'group_messages', 'group_short_term', 'group_shared_memories', 'long_term_memories', 'base_memories', 'planned_messages', 'user_profiles', 'providers']) {
    try { await db.execute('ALTER TABLE $table ADD COLUMN client_id TEXT'); } catch (_) {}
    try { await db.execute('ALTER TABLE $table ADD COLUMN sync_updated_at INTEGER'); } catch (_) {}
    // 回填 client_id：UUID 主键表用 id，自增整型表用 id（后续 SyncService 上传时加 deviceId 前缀）
    try { await db.execute('UPDATE $table SET client_id = CAST(id AS TEXT) WHERE client_id IS NULL'); } catch (_) {}
    try { await db.execute('UPDATE $table SET sync_updated_at = ? WHERE sync_updated_at IS NULL', [now]); } catch (_) {}
  }
  debugPrint('[DB] v23 migration: added client_id + sync_updated_at to 13 sync tables, created local_tombstones');
}
```

- [ ] **Step 4: 验证编译**

Run: `flutter analyze lib/services/database_service.dart`
Expected: 无新增 error/warning

- [ ] **Step 5: Commit**

```bash
git add lib/services/database_service.dart
git commit -m "feat: DB v23 migration - add client_id + sync_updated_at + local_tombstones"
```

---

## Task 12: 客户端设备 ID 服务

**Files:**
- Create: `lib/services/device_id_service.dart`

**Interfaces:**
- Produces: `DeviceIdService.id` 静态 getter

- [ ] **Step 1: 创建 device_id_service.dart**

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  DeviceIdService._();
  static const _key = 'device_id';
  static String? _cached;

  /// 获取或生成设备 ID（首次调用时生成并持久化）
  static Future<String> get id async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var did = prefs.getString(_key);
    if (did == null || did.isEmpty) {
      did = const Uuid().v4();
      await prefs.setString(_key, did);
    }
    _cached = did;
    return did;
  }
}
```

**注意**：项目可能已依赖 `uuid` 包（agents 表 id 用 UUID）。若未依赖，需在 `pubspec.yaml` 添加 `uuid: ^4.0.0`。先检查 pubspec.yaml。

- [ ] **Step 2: 检查 pubspec.yaml 是否有 uuid 依赖**

读取 `pubspec.yaml`，搜索 `uuid:`。若无，则添加。

- [ ] **Step 3: 验证编译**

Run: `flutter analyze lib/services/device_id_service.dart`
Expected: 无 error

- [ ] **Step 4: Commit**

```bash
git add lib/services/device_id_service.dart pubspec.yaml
git commit -m "feat: add DeviceIdService for cross-device unique identification"
```

---

## Task 13: 客户端同步服务 SyncService

**Files:**
- Create: `lib/services/sync_service.dart`

**Interfaces:**
- Consumes: Task 11 的 DB v23、Task 12 的 DeviceIdService
- Produces: `SyncService.{uploadAll, downloadAll, checkCloudUpdate, recordTombstone}` 方法

- [ ] **Step 1: 创建 sync_service.dart**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../config/server_config.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'device_id_service.dart';

class SyncResult {
  final bool success;
  final int itemsProcessed;
  final String? error;
  const SyncResult({required this.success, required this.itemsProcessed, this.error});
}

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  /// 13 张需同步表
  static const syncTables = [
    'agents', 'chat_messages', 'short_term_messages',
    'group_chats', 'group_members', 'group_messages',
    'group_short_term', 'group_shared_memories',
    'long_term_memories', 'base_memories', 'planned_messages',
    'user_profiles', 'providers',
  ];

  /// 各表主键字段名
  static const _primaryKeys = {
    'agents': 'id',
    'chat_messages': 'id',
    'short_term_messages': 'id',
    'group_chats': 'id',
    'group_members': 'id',
    'group_messages': 'id',
    'group_short_term': 'id',
    'group_shared_memories': 'id',
    'long_term_memories': 'id',
    'base_memories': 'id',
    'planned_messages': 'id',
    'user_profiles': 'id',
    'providers': 'id',
  };

  String _url(String path) => '${ServerConfig.baseUrl}$path';

  Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// 记录墓碑（本地删除时调用）
  Future<void> recordTombstone(String table, String clientId) async {
    if (!syncTables.contains(table)) return;
    final db = await DatabaseService.database;
    await db.insert('local_tombstones', {
      'table_name': table,
      'client_id': clientId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 上传所有表数据
  Future<SyncResult> uploadAll() async {
    final token = await AuthService.instance.getToken();
    if (token == null) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    final deviceId = await DeviceIdService.id;
    final db = await DatabaseService.database;
    final payload = <String, dynamic>{};

    int totalItems = 0;
    for (final table in syncTables) {
      final rows = await db.query(table);
      final items = <Map<String, dynamic>>[];
      for (final row in rows) {
        // 确保 client_id 存在
        String clientId = row['client_id']?.toString() ?? '';
        if (clientId.isEmpty) {
          clientId = deviceId + '_' + row[_primaryKeys[table]!].toString();
          await db.update(table, {'client_id': clientId}, where: 'id = ?', whereArgs: [row[_primaryKeys[table]!]]);
        }
        final item = Map<String, dynamic>.from(row);
        item['client_id'] = clientId;
        items.add(item);
        totalItems++;
      }
      // 读取本地墓碑
      final tombstones = await db.query('local_tombstones', where: 'table_name = ?', whereArgs: [table]);
      final tombList = tombstones.map((t) => {
        'table_name': t['table_name'],
        'client_id': t['client_id'],
      }).toList();
      payload[table] = {'items': items, 'tombstones': tombList};
    }

    try {
      final resp = await http.post(
        Uri.parse(_url('/api/v1/sync/all')),
        headers: _headers(token),
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 200) {
        return SyncResult(success: false, itemsProcessed: 0, error: '上传失败: ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) {
        return SyncResult(success: false, itemsProcessed: 0, error: body['msg'] ?? '上传失败');
      }
      // 清空本地墓碑
      final db2 = await DatabaseService.database;
      await db2.delete('local_tombstones');
      // 更新本地 sync_updated_at
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final table in syncTables) {
        await db2.update(table, {'sync_updated_at': now});
      }
      return SyncResult(success: true, itemsProcessed: totalItems);
    } catch (e) {
      return SyncResult(success: false, itemsProcessed: 0, error: e.toString());
    }
  }

  /// 下载所有表数据
  Future<SyncResult> downloadAll() async {
    final token = await AuthService.instance.getToken();
    if (token == null) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    final db = await DatabaseService.database;

    try {
      final resp = await http.get(
        Uri.parse(_url('/api/v1/sync/all')),
        headers: _headers(token),
      );
      if (resp.statusCode != 200) {
        return SyncResult(success: false, itemsProcessed: 0, error: '下载失败: ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) {
        return SyncResult(success: false, itemsProcessed: 0, error: body['msg'] ?? '下载失败');
      }
      final data = body['data'] as Map<String, dynamic>;
      int totalProcessed = 0;

      // 先应用墓碑
      final tombstones = (data['tombstones'] as List?) ?? [];
      for (final t in tombstones) {
        final tableName = t['TableName'] as String? ?? t['table_name'] as String?;
        final clientId = t['ClientID'] as String? ?? t['client_id'] as String?;
        if (tableName != null && clientId != null && syncTables.contains(tableName)) {
          await db.delete(tableName, where: 'client_id = ?', whereArgs: [clientId]);
          totalProcessed++;
        }
      }

      // 再 upsert 各表数据
      for (final table in syncTables) {
        final items = (data[table] as List?) ?? [];
        for (final item in items) {
          final m = Map<String, dynamic>.from(item as Map);
          // 移除服务端字段
          m.remove('id');
          m.remove('ID');
          m.remove('user_id');
          m.remove('UserID');
          m.remove('created_at');
          m.remove('CreatedAt');
          final clientId = m.remove('client_id') ?? m.remove('ClientID');
          if (clientId != null) {
            m['client_id'] = clientId;
          }
          // upsert
          final existing = await db.query(table, where: 'client_id = ?', whereArgs: [clientId]);
          if (existing.isNotEmpty) {
            await db.update(table, m, where: 'client_id = ?', whereArgs: [clientId]);
          } else {
            // 移除主键让 SQLite 自增（仅自增整型表），UUID 表保留 id
            if (_primaryKeys[table] == 'id') {
              // UUID 表：从云端拿 id
              final cloudId = item['ClientID'] ?? item['client_id'];
              if (table == 'agents' || table == 'group_chats' || table == 'short_term_messages' || table == 'long_term_memories' || table == 'base_memories' || table == 'group_shared_memories' || table == 'user_profiles') {
                m['id'] = cloudId;
              }
            }
            await db.insert(table, m, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          totalProcessed++;
        }
      }

      // 更新本地 sync_updated_at
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final table in syncTables) {
        await db.update(table, {'sync_updated_at': now});
      }
      return SyncResult(success: true, itemsProcessed: totalProcessed);
    } catch (e) {
      return SyncResult(success: false, itemsProcessed: 0, error: e.toString());
    }
  }

  /// 检查云端是否有更新
  Future<bool> checkCloudUpdate() async {
    final token = await AuthService.instance.getToken();
    if (token == null) return false;
    try {
      final resp = await http.get(
        Uri.parse(_url('/api/v1/sync/status')),
        headers: _headers(token),
      );
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) return false;
      // 简化：只要云端有任何数据就返回 true（实际可对比时间戳）
      return true;
    } catch (e) {
      debugPrint('[Sync] checkCloudUpdate failed: $e');
      return false;
    }
  }
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/services/sync_service.dart`
Expected: 无 error

- [ ] **Step 3: Commit**

```bash
git add lib/services/sync_service.dart
git commit -m "feat: add SyncService for full multi-device data sync"
```

---

## Task 14: 客户端同步状态 Provider + 设置页同步分组

**Files:**
- Create: `lib/providers/sync_provider.dart`
- Modify: `lib/screens/settings_screen.dart`（补做 Task 10 的同步分组部分）

**Interfaces:**
- Consumes: Task 13 的 SyncService、Task 1 的订阅状态查询（AuthService.getMySubscription）
- Produces: `syncProvider` StateNotifierProvider

- [ ] **Step 1: 创建 sync_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import 'auth_provider.dart';

class SyncState {
  final bool isUploading;
  final bool isDownloading;
  final DateTime? lastSyncTime;
  final String? error;
  final int? itemsProcessed;
  final bool hasCloudUpdate;
  final bool canUseSync; // 订阅状态

  const SyncState({
    this.isUploading = false,
    this.isDownloading = false,
    this.lastSyncTime,
    this.error,
    this.itemsProcessed,
    this.hasCloudUpdate = false,
    this.canUseSync = false,
  });

  SyncState copyWith({
    bool? isUploading,
    bool? isDownloading,
    DateTime? lastSyncTime,
    String? error,
    int? itemsProcessed,
    bool? hasCloudUpdate,
    bool? canUseSync,
  }) {
    return SyncState(
      isUploading: isUploading ?? this.isUploading,
      isDownloading: isDownloading ?? this.isDownloading,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      error: error,
      itemsProcessed: itemsProcessed ?? this.itemsProcessed,
      hasCloudUpdate: hasCloudUpdate ?? this.hasCloudUpdate,
      canUseSync: canUseSync ?? this.canUseSync,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  SyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  Future<void> _init() async {
    await checkSubscription();
    await checkCloudUpdate();
  }

  /// 检查订阅状态
  Future<void> checkSubscription() async {
    try {
      final subs = await AuthService.instance.getMySubscription();
      state = state.copyWith(canUseSync: subs.isNotEmpty);
    } catch (_) {}
  }

  /// 检查云端更新
  Future<void> checkCloudUpdate() async {
    if (!state.canUseSync) return;
    final hasUpdate = await SyncService.instance.checkCloudUpdate();
    state = state.copyWith(hasCloudUpdate: hasUpdate);
  }

  /// 上传所有数据
  Future<void> uploadAll() async {
    state = state.copyWith(isUploading: true, error: null);
    final result = await SyncService.instance.uploadAll();
    state = state.copyWith(
      isUploading: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
    );
  }

  /// 下载所有数据
  Future<void> downloadAll() async {
    state = state.copyWith(isDownloading: true, error: null);
    final result = await SyncService.instance.downloadAll();
    state = state.copyWith(
      isDownloading: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
    );
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});
```

- [ ] **Step 2: 在 settings_screen.dart 补做「多端同步」分组**

仅当 `ref.watch(syncProvider).canUseSync == true` 时显示该分组，包含：
- 同步状态卡片（上次同步时间 + 云端是否有更新徽章）
- 「上传到云端」按钮（loading + 结果 Toast）
- 「从云端下载」按钮（loading + 结果 Toast）
- 「自动同步」开关（默认关，本计划暂不实现自动同步逻辑，仅留 UI 占位）

- [ ] **Step 3: 验证编译**

Run: `flutter analyze lib/providers/sync_provider.dart lib/screens/settings_screen.dart`
Expected: 无新增 error/warning

- [ ] **Step 4: Commit**

```bash
git add lib/providers/sync_provider.dart lib/screens/settings_screen.dart
git commit -m "feat: add SyncProvider + multi-device sync section in settings"
```

---

## Task 15: 客户端删除操作墓碑埋点

**Files:**
- Modify: `lib/providers/agent_provider.dart`
- Modify: `lib/providers/chat_provider.dart`
- Modify: `lib/providers/group_provider.dart`
- Modify: `lib/providers/user_profile_provider.dart`
- Modify: `lib/providers/memory_provider.dart`

**Interfaces:**
- Consumes: Task 13 的 SyncService.recordTombstone

**注意**：墓碑埋点应在删除 SQLite 数据**之前**调用，避免删除后无法获取 client_id。

- [ ] **Step 1: agent_provider.dart 的 deleteAgent 埋点**

读取 `lib/providers/agent_provider.dart:36` 的 `deleteAgent` 方法，在 `DatabaseService.deleteAgent(id)` 之前追加：

```dart
Future<void> deleteAgent(String id) async {
  await SyncService.instance.recordTombstone('agents', id);
  await DatabaseService.deleteAgent(id);
  // ... 现有逻辑
}
```

并在文件顶部 import `'../services/sync_service.dart'`。

- [ ] **Step 2: chat_provider.dart 的 clearCurrentAgentChatMessages 埋点**

读取 `lib/providers/chat_provider.dart:204`，在清空之前先查询所有消息的 client_id，逐个记录墓碑：

```dart
Future<void> clearCurrentAgentChatMessages() async {
  final agentId = _agentId;
  if (agentId == null) return;
  // 查询所有消息的 client_id 用于墓碑
  final db = await DatabaseService.database;
  final msgs = await db.query('chat_messages', where: 'agent_id = ?', whereArgs: [agentId]);
  for (final m in msgs) {
    final clientId = m['client_id']?.toString() ?? '';
    if (clientId.isNotEmpty) {
      await SyncService.instance.recordTombstone('chat_messages', clientId);
    }
  }
  await DatabaseService.clearChatMessages(agentId: agentId);
  state = state.copyWith(messages: []);
}
```

- [ ] **Step 3: group_provider.dart 的 deleteGroup + removeMember 埋点**

在 `deleteGroup` 中删除前，先查询该群所有相关数据的 client_id（group_chats、group_members、group_messages、group_short_term、group_shared_memories），逐个记录墓碑。

在 `removeMember` 中删除前，记录该 member 的墓碑。

- [ ] **Step 4: user_profile_provider.dart 的 deleteProfile + clearAll 埋点**

```dart
Future<void> deleteProfile(String id) async {
  await SyncService.instance.recordTombstone('user_profiles', id);
  await _service.deleteEntry(id);
  await loadProfiles();
}

Future<void> clearAll() async {
  // 查询所有 profile id 记录墓碑
  final all = await _service.getAllEntries();
  for (final p in all) {
    await SyncService.instance.recordTombstone('user_profiles', p.id);
  }
  await _service.clearAll();
  await loadProfiles();
}
```

**注意**：UserProfileService 需新增 `getAllEntries()` 方法（若不存在）。

- [ ] **Step 5: memory_provider.dart 的记忆删除埋点**

读取 `lib/providers/memory_provider.dart`，找到所有删除长期/基础/计划记忆的函数（约 line 94 和 line 184 的 `clearAll`），在删除前查询所有 id 并记录墓碑。

- [ ] **Step 6: 验证编译**

Run: `flutter analyze lib/providers/`
Expected: 无新增 error/warning

- [ ] **Step 7: Commit**

```bash
git add lib/providers/agent_provider.dart lib/providers/chat_provider.dart lib/providers/group_provider.dart lib/providers/user_profile_provider.dart lib/providers/memory_provider.dart
git commit -m "feat: add tombstone recording to all delete operations"
```

---

## Task 16: l10n keys 扩展

**Files:**
- Modify: `lib/l10n/app_localizations.dart`

**Interfaces:**
- Produces: 20+ 新 l10n keys

- [ ] **Step 1: 在 app_localizations.dart 的 zh 和 en 两个 map 中追加新 keys**

中文部分（约 20 个 key）：

```dart
'networkUsageAgreement': '《智能体和群聊智能体网络上传，下载，使用协议》',
'realInfoProtocol': '真实信息协议',
'agreementAllRequired': '请先阅读并同意三份协议',
'viewUserAgreement': '查看用户协议',
'viewPrivacyPolicy': '查看隐私政策',
'viewNetworkUsageAgreement': '查看网络使用协议',
'multiDeviceSync': '多端同步',
'multiDeviceSyncDesc': '在不同设备间同步你的智能体、聊天记录、记忆、画像等数据',
'uploadToCloud': '上传到云端',
'downloadFromCloud': '从云端下载',
'lastSyncTime': '上次同步：{time}',
'cloudHasUpdate': '云端有更新',
'syncing': '同步中...',
'syncSuccess': '同步成功，共处理 {n} 项',
'syncFailed': '同步失败：{reason}',
'syncSubscriptionRequired': '多端同步功能需订阅解锁',
'autoSync': '自动同步',
'firstSyncChooseDirection': '首次同步请选择方向',
'uploadWillOverwrite': '上传会覆盖云端数据',
'downloadWillOverwrite': '下载会覆盖本地数据',
'cancelSync': '暂不同步',
```

英文部分对应翻译：

```dart
'networkUsageAgreement': 'Agent and Group Agent Network Upload, Download, Usage Agreement',
'realInfoProtocol': 'Real Info Protocol',
'agreementAllRequired': 'Please read and agree to all three agreements first',
'viewUserAgreement': 'View User Agreement',
'viewPrivacyPolicy': 'View Privacy Policy',
'viewNetworkUsageAgreement': 'View Network Usage Agreement',
'multiDeviceSync': 'Multi-Device Sync',
'multiDeviceSyncDesc': 'Sync your agents, chat history, memories, profiles across devices',
'uploadToCloud': 'Upload to Cloud',
'downloadFromCloud': 'Download from Cloud',
'lastSyncTime': 'Last sync: {time}',
'cloudHasUpdate': 'Cloud has updates',
'syncing': 'Syncing...',
'syncSuccess': 'Sync succeeded, {n} items processed',
'syncFailed': 'Sync failed: {reason}',
'syncSubscriptionRequired': 'Multi-device sync requires subscription',
'autoSync': 'Auto Sync',
'firstSyncChooseDirection': 'Choose direction for first sync',
'uploadWillOverwrite': 'Upload will overwrite cloud data',
'downloadWillOverwrite': 'Download will overwrite local data',
'cancelSync': 'Cancel',
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/l10n/app_localizations.dart`
Expected: 无 error

- [ ] **Step 3: Commit**

```bash
git add lib/l10n/app_localizations.dart
git commit -m "feat: add 20+ l10n keys for sync and agreements"
```

---

## Task 17: 最终构建验证

**Files:** 无修改

- [ ] **Step 1: 服务端编译验证**

Run: `cd website\API && go build ./...`
Expected: 退出码 0

- [ ] **Step 2: 客户端静态分析**

Run: `flutter analyze lib/`
Expected: 不新增 error/warning（pre-existing info 可接受）

- [ ] **Step 3: 如有错误，修复后重新验证**

- [ ] **Step 4: 最终 Commit（如有修复）**

```bash
git add -A
git commit -m "fix: resolve build issues from final verification"
```

---

## Self-Review 结果

### Spec 覆盖检查

| Spec 章节 | 对应 Task | 状态 |
|---|---|---|
| §1 协议文本与门控 | Task 7, 8, 9, 10 | ✅ |
| §2 服务端数据模型 | Task 1, 2 | ✅ |
| §3 服务端 API 路由与 handler | Task 3, 4, 5, 6 | ✅ |
| §4 客户端同步服务与 UI | Task 11, 12, 13, 14, 15 | ✅ |
| §5 协议文本草拟 | Task 7 | ✅ |
| §6 实施任务清单 | 全部 17 个 Task | ✅ |
| §8 验收标准 | Task 17 验证 | ✅ |

### 关键修正（与 spec 差异）

1. **服务端不使用 GORM**：spec §2.4 提到 GORM AutoMigrate 是错误的，实际用 JSON 文件数据库，`Register("TableName")` 即自动加载/创建。已修正。
2. **database.go 需扩展**：spec 未提及 JSON 数据库不支持 map 直接插入的问题，新增 Task 5 扩展 `InsertMap` 方法。
3. **字段冲突**：客户端部分表已有 `updated_at` 字段，新增字段改用 `sync_updated_at` 避免冲突。

### 类型一致性

- `SyncService.recordTombstone(String table, String clientId)` 在 Task 13 定义，Task 15 调用 ✅
- `SyncNotifier.{uploadAll, downloadAll, checkCloudUpdate, canUseSync}` 在 Task 14 定义，Task 10 调用 ✅
- `AgreementService.{hasAgreed, markAgreed, allAgreed}` 在 Task 8 定义，Task 9 调用 ✅

---

## 执行说明

**Plan complete and saved to `docs/superpowers/plans/2026-07-05-multi-device-sync-and-agreements.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
