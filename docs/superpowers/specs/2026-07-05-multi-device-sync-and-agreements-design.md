# 多端同步与协议扩展设计

**作者**：用户确认 + AI 辅助
**日期**：2026-07-05
**状态**：已确认，待实现

---

## 0. 概述

本设计文档涵盖三件事：

1. **协议扩展**：新增独立的《智能体和群聊智能体网络上传，下载，使用协议》；在《隐私政策》中追加《真实信息协议》子条款；三份协议在登录/注册入口强制签署并本地持久化。
2. **网络市场门控**：网络市场的上传/下载功能**对所有用户开放**（免费用户也能上下传）。
3. **多端同步新功能**：服务端新增 `/sync` 路由，客户端全量同步 13 张本地用户数据表到云端。**仅订阅用户可用**。

### 关键约束

| 功能 | 免费用户 | 订阅用户 |
|---|---|---|
| 网络市场上下传 | ✅ | ✅ |
| 多端同步 | ❌ | ✅ |

---

## 1. 协议文本与门控

### 1.1 现状

- 现有 2 份协议：[lib/agreements/user_agreement.dart](file:///d:/window/Desktop/AIchat/lib/agreements/user_agreement.dart) 和 [lib/agreements/privacy_policy.dart](file:///d:/window/Desktop/AIchat/lib/agreements/privacy_policy.dart)
- 同意状态零持久化：登录页两个 Checkbox 是 StatefulWidget 内存变量，每次重进登录页都要重勾
- 服务端 User 表不追踪协议状态
- 设置页无协议查看入口

### 1.2 新增/修改协议文件

#### 新建 [lib/agreements/network_usage_agreement.dart](file:///d:/window/Desktop/AIchat/lib/agreements/network_usage_agreement.dart)

```dart
class NetworkUsageAgreement {
  NetworkUsageAgreement._();
  static const String title = '《智能体和群聊智能体网络上传，下载，使用协议》';
  static const String version = 'v1.0';
  static const String content = '''<完整 8 条条款见 §5.3，此处为常量定义占位说明，实际代码中填入完整正文>''';
}
```

#### 修改 [lib/agreements/privacy_policy.dart](file:///d:/window/Desktop/AIchat/lib/agreements/privacy_policy.dart)

- 版本号升级 `v1.0` → `v1.1`
- `content` 末尾追加《真实信息协议》子条款（7 条），覆盖：
  - 真实信息功能概述（每智能体独立开关、10 轮间隔）
  - 画像数据收集（4 种来源 + 置信度）
  - 画像数据存储与传输（本地为主、同步时 AES 加密）
  - 画像数据使用（增强对话、个性化、多端展示）
  - 用户权利（查看/编辑/删除/清空）
  - 群聊场景（不触发画像 AI）
  - 协议变更机制

#### 修改 [lib/agreements/user_agreement.dart](file:///d:/window/Desktop/AIchat/lib/agreements/user_agreement.dart)

- 仅追加 `static const String version = 'v1.0';`，正文不动

### 1.3 协议同意状态持久化

**新建 [lib/services/agreement_service.dart](file:///d:/window/Desktop/AIchat/lib/services/agreement_service.dart)**：

SharedPreferences 键设计：
- `agreement_agreed_<key>` (bool)：是否同意
- `agreement_version_<key>` (String)：上次同意时的协议版本号
- `agreement_time_<key>` (int)：同意时间戳

核心方法：
- `hasAgreed(key, currentVersion)`：版本号匹配且 agreed=true 才返回 true
- `markAgreed(key, version)`：写入同意状态 + 版本号 + 时间戳
- `allAgreed()`：三份协议是否全部已同意（版本号需匹配）

### 1.4 登录页改造

**修改 [lib/screens/login_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/login_screen.dart)**：

- `initState` 调 `AgreementService` 加载三份协议已同意状态
- 单 Checkbox 表示"同意全部三份"，初始状态由持久化决定
- 文案：「我已阅读并同意《用户协议》《隐私政策》《智能体和群聊智能体网络上传，下载，使用协议》」
- 三份协议名各自可点击，跳 `_showAgreementViewer(type)` 全屏阅读
- 勾选时调 `markAgreed` 写入三份协议状态
- 提交注册/登录前校验三份全部已同意，否则 Toast 拦截

### 1.5 设置页新增协议查看入口

**修改 [lib/screens/settings_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/settings_screen.dart)** 「关于」分组：

- ListTile：查看用户协议 → `_showAgreementViewer('user')`
- ListTile：查看隐私政策 → `_showAgreementViewer('privacy')`
- ListTile：查看网络使用协议 → `_showAgreementViewer('network')`

`_showAgreementViewer` 抽出为公共方法，便于复用。

---

## 2. 服务端数据模型

### 2.1 同步表清单

为 13 张本地用户数据表建对应云端模型，全部位于 [website/API/models/](file:///d:/window/Desktop/AIchat/website/API/models/)：

| 服务端模型 | 对应本地表 | 用途 |
|---|---|---|
| `SyncAgent` | `agents` | 智能体配置 |
| `SyncChatMessage` | `chat_messages` | 聊天消息 |
| `SyncShortTermMessage` | `short_term_messages` | 短期记忆 |
| `SyncGroupChat` | `group_chats` | 群聊 |
| `SyncGroupMember` | `group_members` | 群成员 |
| `SyncGroupMessage` | `group_messages` | 群消息 |
| `SyncGroupShortTerm` | `group_short_term` | 群短期记忆 |
| `SyncGroupSharedMemory` | `group_shared_memories` | 群共享记忆 |
| `SyncLongTermMemory` | `long_term_memories` | 长期记忆 |
| `SyncBaseMemory` | `base_memories` | 基础记忆 |
| `SyncPlannedMessage` | `planned_messages` | 计划消息 |
| `SyncUserProfile` | `user_profiles` | 用户画像 |
| `SyncProvider` | `providers` | API Key 配置 |

**不同步**：`token_usage`/`token_cost`（按设备统计）、`draft_uploads`（仅本地草稿）、`novel_generations`（已生成产物）、`debug_logs`（设备日志）。

### 2.2 通用模型字段模式

```go
type SyncAgent struct {
    ID        uint      `gorm:"primaryKey"`
    UserID    uint      `gorm:"index:idx_user_client"`
    ClientID  string    `gorm:"index:idx_user_client"` // 客户端本地主键
    // ... 该表原有字段一对一映射
    // 敏感字段（如 api_key）用 AES 加密，复用 user_agent.go 的加密逻辑
    UpdatedAt time.Time `gorm:"index"`
    CreatedAt time.Time
}
```

`SyncTombstone`（墓碑表，记录删除）：

```go
type SyncTombstone struct {
    ID        uint      `gorm:"primaryKey"`
    UserID    uint      `gorm:"index:idx_user_table_client"`
    TableName string    `gorm:"index:idx_user_table_client"` // 'agents' / 'chat_messages' / ...
    ClientID  string    `gorm:"index:idx_user_table_client"`
    CreatedAt time.Time
}
```

### 2.3 订阅计划扩展

**修改 [website/API/models/subscription_plan.go](file:///d:/window/Desktop/AIchat/website/API/models/subscription_plan.go)**：

```go
type SubscriptionPlan struct {
    // ... 现有字段
    AllowSync bool `gorm:"default:false"` // 是否允许使用多端同步功能
}
```

**修改 [website/API/data/SubscriptionPlan.json](file:///d:/window/Desktop/AIchat/website/API/data/SubscriptionPlan.json)**：现有计划改为 `allow_sync: true`。

### 2.4 自动建表

GORM `db.AutoMigrate(&SyncAgent{}, ..., &SyncTombstone{})` 自动建表，无需手写 SQL。

---

## 3. 服务端 API 路由与 handler

### 3.1 路由设计

**修改 [website/API/routes/routes.go](file:///d:/window/Desktop/AIchat/website/API/routes/routes.go)**：

```go
syncGroup := apiV1.Group("/sync")
syncGroup.Use(middleware.JWT(), middleware.RequireSyncSubscription())
{
    GET  /sync/status           // 各表云端最近 updated_at
    GET  /sync/all              // 拉取所有表数据（含墓碑）
    POST /sync/all              // 上传所有表数据
    GET  /sync/:table           // 拉取指定表数据
    POST /sync/:table           // 上传指定表数据
    GET  /sync/tombstones       // 拉取墓碑
    POST /sync/tombstones       // 上传墓碑
    DELETE /sync/tombstones     // 清空已应用的墓碑
}
```

`:table` 白名单：13 张表名。非白名单返回 400。

### 3.2 订阅校验中间件

**新建 [website/API/middleware/sync_subscription.go](file:///d:/window/Desktop/AIchat/website/API/middleware/sync_subscription.go)**：

```go
func RequireSyncSubscription() gin.HandlerFunc {
    return func(c *gin.Context) {
        userID := c.GetUint("user_id")
        // 复用 quota_handler.go:resolveQuota 的订阅查询逻辑
        // 查询用户所有 status==1 的 UserSubscription → PlanID 集合
        // 任一 Plan.AllowSync == true 则放行
        if !hasSyncSubscription(userID) {
            c.AbortWithStatusJSON(403, gin.H{
                "code": 403,
                "msg":  "多端同步仅订阅用户可用",
            })
            return
        }
        c.Next()
    }
}
```

### 3.3 handler 设计

**新建 [website/API/handlers/sync_handler.go](file:///d:/window/Desktop/AIchat/website/API/handlers/sync_handler.go)**：

#### 上传（POST `/sync/:table` 与 POST `/sync/all`）

1. 解析请求体 `{ items: [...], tombstones?: [...] }`
2. 对每个 item 按 `(UserID, ClientID)` upsert 到对应 SyncXxx 表
3. 对每个 tombstone 按 `(UserID, TableName, ClientID)` 插入 SyncTombstone，同时从对应 SyncXxx 表删除
4. 返回 `{ code: 0, data: { upserted: N, deleted: M } }`

#### 下载（GET `/sync/:table` 与 GET `/sync/all`）

1. 查询当前用户的所有 SyncXxx 数据（按 UpdatedAt DESC）
2. 查询当前用户的所有未应用 SyncTombstone
3. 返回 `{ code: 0, data: { items: [...], tombstones: [...], server_time: now } }`

#### 状态查询（GET `/sync/status`）

返回各表云端最近 `updated_at`，客户端对比本地 `last_sync_<table>` 判断是否需要拉取。

### 3.4 安全与隔离

- 所有查询强制 `WHERE user_id = ?`，用户只能看自己数据
- 敏感字段 AES 加密，复用 [user_agent.go](file:///d:/window/Desktop/AIchat/website/API/handlers/user_agent.go) 加密逻辑
- 单次请求体限制 50MB
- 限流：每用户每分钟 10 次同步请求

---

## 4. 客户端同步服务与 UI

### 4.1 同步服务核心

**新建 [lib/services/sync_service.dart](file:///d:/window/Desktop/AIchat/lib/services/sync_service.dart)**：

```dart
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();
  
  Future<SyncResult> uploadAll();      // 上传 13 张表 + 本地墓碑
  Future<SyncResult> downloadAll();    // 下载并应用墓碑 + 各表数据
  Future<List<String>> checkCloudUpdate();  // 对比时间戳返回需刷新表
  Future<void> recordTombstone(String table, String clientId);  // 本地删除埋点
}
```

### 4.2 数据库迁移 v22 → v23

**修改 [lib/services/database_service.dart](file:///d:/window/Desktop/AIchat/lib/services/database_service.dart)**：

- 新建本地 `local_tombstones` 表（缓冲待上传的删除记录）
- 13 张需同步表新增 `updated_at` INTEGER 字段（已有数据回填 `now`）
- 13 张需同步表新增 `client_id` TEXT 字段
  - 已有 UUID 主键的表（如 `agents.id`）：`client_id = id`
  - 自增整型主键表（如 `chat_messages.id`）：`client_id = '${deviceId}_${id}'`

### 4.3 设备 ID 服务

**新建 [lib/services/device_id_service.dart](file:///d:/window/Desktop/AIchat/lib/services/device_id_service.dart)**：

- 首次启动生成 UUID v4，存 `SharedPreferences` key `device_id`
- 用于自增主键表的 `client_id` 前缀

### 4.4 同步状态 Provider

**新建 [lib/providers/sync_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/sync_provider.dart)**：

```dart
class SyncState {
  final bool isUploading;
  final bool isDownloading;
  final DateTime? lastSyncTime;
  final String? error;
  final int? itemsUploaded;
  final int? itemsDownloaded;
  final bool hasCloudUpdate;
}

class SyncNotifier extends StateNotifier<SyncState> {
  Future<void> uploadAll();
  Future<void> downloadAll();
  Future<void> checkCloudUpdate();
  Future<bool> canUseSync();  // 检查订阅状态
}
```

### 4.5 UI 入口

#### 设置页新增「多端同步」分组（仅订阅用户可见）

**修改 [lib/screens/settings_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/settings_screen.dart)**：

- 同步状态卡片：上次同步时间 + 云端是否有更新徽章
- 「上传到云端」按钮（loading + 结果 Toast）
- 「从云端下载」按钮（loading + 结果 Toast）
- 「自动同步」开关（默认关）：启动 App 自动 `checkCloudUpdate`，本地变更 5 秒去抖自动 `uploadAll`
- 非订阅用户不显示此分组

#### 账户页订阅引导

**修改 [lib/screens/account_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/account_screen.dart)**：

订阅入口下方显示提示：「多端同步功能需订阅解锁」，点击跳订阅中心。

### 4.6 本地删除操作墓碑埋点

需修改的删除函数（约 12 处），删除前先调 `SyncService.instance.recordTombstone(table, clientId)`：

| 文件 | 函数 | 表 |
|---|---|---|
| [agent_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/agent_provider.dart) | `deleteAgent` | agents |
| [chat_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/chat_provider.dart) | `clearCurrentAgentChatMessages`、单条消息删除 | chat_messages |
| [group_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/group_provider.dart) | `deleteGroup`、`removeMember` | group_chats、group_members |
| [user_profile_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/user_profile_provider.dart) | `deleteProfile`、`clearAll` | user_profiles |
| [memory_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/memory_provider.dart) | 长期/基础/计划记忆删除 | long_term_memories、base_memories、planned_messages |

### 4.7 冲突处理策略

**Last-Write-Wins (LWW)**：
- 上传：按 `UpdatedAt` 比较，本地较新才覆盖云端
- 下载：按 `UpdatedAt` 比较，云端较新才覆盖本地
- 同一字段两设备同时修改：以 `UpdatedAt` 较晚者为准

不做字段级合并（YAGNI，手动同步用户可主动选择方向）。

### 4.8 首次同步引导

第一次启动「多端同步」开关时弹确认对话框：
- 「上传到云端」：本地数据上传，云端已有数据**会被覆盖**
- 「从云端下载」：云端数据下载到本地，本地已有数据**会被覆盖**
- 「取消」：暂不同步

---

## 5. 协议文本草拟

### 5.1 《用户协议》

仅追加 `version = 'v1.0'`，正文保持现状。

### 5.2 《隐私政策》追加《真实信息协议》子条款

版本号 `v1.0` → `v1.1`，正文末尾追加 7 条子条款：

1. 真实信息功能概述（每智能体独立开关、10 轮间隔）
2. 用户画像数据的收集（4 种来源 + 置信度）
3. 用户画像数据的存储与传输（本地为主、同步时 AES 加密）
4. 用户画像数据的使用（增强对话、个性化、多端展示）
5. 用户权利（查看/编辑/删除/清空）
6. 群聊场景（不触发画像 AI）
7. 协议变更机制

### 5.3 《智能体和群聊智能体网络上传，下载，使用协议》

新建，8 条主条款：

1. 协议范围
2. 上传内容规范（9 项法律法规禁止内容 + 知识产权 + 恶意代码禁止）
3. 审核机制（管理员审核、驳回、下架、封禁）
4. 下载与使用（仅供个人使用、禁止二次上传/商业用途/篡改冒充）
5. 责任与免责（上传者负全部责任、运营方不承担连带责任）
6. 数据传输（AES 加密、"我上传的"仅自己可见、公开后任何人可下载）
7. 知识产权（著作权归原作者、上传即授予非排他性许可）
8. 协议变更机制

### 5.4 l10n keys

新增约 20 个 l10n keys（中英双语）：

```
networkUsageAgreement, realInfoProtocol, agreementAllRequired,
viewUserAgreement, viewPrivacyPolicy, viewNetworkUsageAgreement,
multiDeviceSync, multiDeviceSyncDesc, uploadToCloud, downloadFromCloud,
lastSyncTime, cloudHasUpdate, syncing, syncSuccess, syncFailed,
syncSubscriptionRequired, autoSync, firstSyncChooseDirection,
uploadWillOverwrite, downloadWillOverwrite, cancelSync
```

---

## 6. 实施任务清单

### 服务端

1. 新建 13 个 SyncXxx 模型 + SyncTombstone 模型（[website/API/models/](file:///d:/window/Desktop/AIchat/website/API/models/)）
2. 修改 `subscription_plan.go` 增加 `AllowSync` 字段
3. 修改 `SubscriptionPlan.json` 种子数据加 `allow_sync: true`
4. 新建 `middleware/sync_subscription.go` 订阅校验中间件
5. 新建 `handlers/sync_handler.go` 实现上传/下载/状态/墓碑 4 类接口
6. 修改 `routes/routes.go` 注册 `/sync` 路由组
7. 修改 `main.go` 添加 GORM AutoMigrate
8. 服务端 `go build ./...` 验证

### 客户端

9. 新建 [lib/agreements/network_usage_agreement.dart](file:///d:/window/Desktop/AIchat/lib/agreements/network_usage_agreement.dart) 协议文本
10. 修改 [lib/agreements/privacy_policy.dart](file:///d:/window/Desktop/AIchat/lib/agreements/privacy_policy.dart) 追加《真实信息协议》
11. 修改 [lib/agreements/user_agreement.dart](file:///d:/window/Desktop/AIchat/lib/agreements/user_agreement.dart) 追加 version 字段
12. 新建 [lib/services/agreement_service.dart](file:///d:/window/Desktop/AIchat/lib/services/agreement_service.dart) 持久化
13. 修改 [lib/screens/login_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/login_screen.dart) 三份协议门控
14. 修改 [lib/screens/settings_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/settings_screen.dart) 协议查看入口 + 多端同步分组
15. 修改 [lib/screens/account_screen.dart](file:///d:/window/Desktop/AIchat/lib/screens/account_screen.dart) 订阅引导提示
16. 数据库迁移 v22 → v23：local_tombstones 表 + 13 张表加 updated_at/client_id
17. 新建 [lib/services/device_id_service.dart](file:///d:/window/Desktop/AIchat/lib/services/device_id_service.dart)
18. 新建 [lib/services/sync_service.dart](file:///d:/window/Desktop/AIchat/lib/services/sync_service.dart) 同步核心
19. 新建 [lib/providers/sync_provider.dart](file:///d:/window/Desktop/AIchat/lib/providers/sync_provider.dart)
20. 12 处删除函数埋点 recordTombstone
21. 修改 [lib/l10n/app_localizations.dart](file:///d:/window/Desktop/AIchat/lib/l10n/app_localizations.dart) 新增 20 个 l10n keys
22. 客户端 `flutter analyze lib/` 验证

---

## 7. 风险与影响

### 风险

- **数据迁移风险**：v22 → v23 给 13 张表加字段，已有数据回填 `updated_at = now`、`client_id = 主键或 deviceId_主键`。建议迁移前提示用户备份数据库。
- **同步流量风险**：聊天记录和短期记忆数据量较大，全量同步在弱网下可能失败。建议失败重试 3 次后提示用户切换网络。
- **冲突丢失风险**：LWW 策略下两设备同时修改同一字段会丢一版本。手动同步场景下用户可主动选择方向，可接受。
- **协议版本升级风险**：用户已同意旧版协议，新版上线后 `hasAgreed` 会返回 false 强制重新同意。需在版本说明中告知用户。

### 影响范围

- **服务端**：新增 14 个模型文件、1 个中间件、1 个 handler、1 组路由
- **客户端**：新增 4 个文件、修改 12+ 个文件、DB 迁移 v22→v23
- **协议**：3 份协议全部需用户重新同意（版本号升级）
- **订阅体系**：现有订阅计划自动获得 `allow_sync` 能力（种子数据改为 true）

---

## 8. 验收标准

1. 三份协议在登录页强制签署，已同意状态持久化（重进登录页默认勾选）
2. 协议版本升级后强制重新同意
3. 设置页可查看三份协议全文
4. 网络市场对免费用户开放上下传
5. 多端同步仅订阅用户可用，非订阅用户在设置页不见同步分组、账户页可见订阅引导
6. 订阅用户可一键上传/下载 13 张表数据
7. 本地删除操作正确生成墓碑并同步到云端
8. 服务端 `go build ./...` 退出码 0
9. 客户端 `flutter analyze lib/` 不新增 error/warning
