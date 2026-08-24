# P0/P1/P2 Security and Reliability Hard Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复审计中的 P0、P1、P2 问题，并以 v5.3.6（version_code 67）立即切断旧聊天、退款、同步和主动关心协议。

**Architecture:** Flutter 以服务端用户 ID 派生独立 SQLite 数据库，所有高风险请求携带版本和智能体客户端 ID。Go 服务端持有智能体归属、功能配额、主动关心、模型准入和 WebSocket ticket 的权威状态；同步敏感字段以版本化 AES envelope 落库，更新包以 SHA-256 + Ed25519 验证。

**Tech Stack:** Flutter 3.41 / Dart 3.11、Riverpod 2、sqflite、Go 1.25、Gin 1.12、modernc.org/sqlite、AES-GCM、Ed25519、GitHub Actions。

## Global Constraints

- 新客户端版本必须为 `5.3.6+67`，高风险接口最低版本必须为 67。
- 旧协议立即拒绝，不实现 JWT query、公开退款或无版本头回退。
- 本地数据必须按账号使用独立 SQLite 文件；注销不删除账号数据库。
- 同步传输使用 TLS，服务端敏感字段使用带版本前缀的 AES envelope。
- Flutter 新代码不得使用 `withOpacity`，不得重新启用 Kotlin 增量编译。
- 每个行为修复先运行对应失败测试，再写生产代码。
- 不提交或覆盖工作区中与本计划无关的现有变更。

---

### Task 1: 协议版本与 CI 发布门禁

**Files:**
- Modify: `pubspec.yaml`
- Modify: `vision.json`
- Create: `lib/services/client_protocol.dart`
- Create: `website/API/middleware/client_version.go`
- Create: `website/API/middleware/client_version_test.go`
- Modify: `website/API/routes/routes.go`
- Create: `.github/workflows/quality-gate.yml`

**Interfaces:**
- Produces: `ClientProtocol.versionCode == 67`、`ClientProtocol.headers()`。
- Produces: `middleware.RequireClientVersion(67)`，错误码 `upgrade_required`。

- [ ] **Step 1: 写失败测试**

```go
func TestRequireClientVersionRejectsMissingAndOldVersions(t *testing.T) {
    router := gin.New()
    router.GET("/protected", RequireClientVersion(67), func(c *gin.Context) { c.Status(http.StatusNoContent) })
    for _, version := range []string{"", "66", "invalid"} {
        req := httptest.NewRequest(http.MethodGet, "/protected", nil)
        if version != "" { req.Header.Set("X-Client-Version-Code", version) }
        rec := httptest.NewRecorder()
        router.ServeHTTP(rec, req)
        if rec.Code != http.StatusUpgradeRequired { t.Fatalf("version %q: status=%d", version, rec.Code) }
    }
}
```

- [ ] **Step 2: 运行测试并确认因 `RequireClientVersion` 不存在而失败**

Run: `cd website/API && go test -count=1 ./middleware -run TestRequireClientVersionRejectsMissingAndOldVersions`

- [ ] **Step 3: 实现版本协议和中间件**

```dart
abstract final class ClientProtocol {
  static const versionCode = 67;
  static const platformHeader = 'X-Client-Platform';
  static const versionHeader = 'X-Client-Version-Code';

  static Map<String, String> headers(String platform) => {
    versionHeader: '$versionCode',
    platformHeader: platform,
  };
}
```

```go
func RequireClientVersion(minimum int) gin.HandlerFunc {
    return func(c *gin.Context) {
        value, err := strconv.Atoi(c.GetHeader("X-Client-Version-Code"))
        if err != nil || value < minimum {
            c.AbortWithStatusJSON(http.StatusUpgradeRequired, gin.H{
                "code": "upgrade_required", "message": "请升级到最新版本",
                "data": gin.H{"minimum_version_code": minimum},
            })
            return
        }
        c.Next()
    }
}
```

- [ ] **Step 4: 对聊天、quota、sync、主动关心路由挂载最低版本中间件并升级版本号**

- [ ] **Step 5: 添加不可忽略失败的 CI**

```yaml
name: quality-gate
on: [push, pull_request]
jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
  go:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: website/API } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.25.x' }
      - run: go test -count=1 ./...
      - run: go build ./...
```

- [ ] **Step 6: 验证 Task 1**

Run: `cd website/API && go test -count=1 ./middleware ./routes`

### Task 2: 每账号独立 Flutter 数据库

**Files:**
- Create: `lib/services/account_database_scope.dart`
- Create: `lib/services/account_database_migration.dart`
- Modify: `lib/services/database_service.dart`
- Modify: `lib/services/database_schema.dart`
- Modify: `lib/services/secure_session_store.dart`
- Modify: `lib/providers/auth_provider.dart`
- Modify: `lib/main.dart`
- Create: `test/account_database_scope_test.dart`
- Modify: `test/secure_session_store_test.dart`

**Interfaces:**
- Produces: `AccountDatabaseScope.databaseNameFor(int userId)`。
- Produces: `DatabaseService.switchAccount(int? userId)`、`DatabaseService.currentUserId`。
- SecureSession 新增 `int? userId`。

- [ ] **Step 1: 写数据库名和切换顺序失败测试**

```dart
test('不同账号得到不同且不含账号明文的数据库名', () {
  final a = AccountDatabaseScope.databaseNameFor(12);
  final b = AccountDatabaseScope.databaseNameFor(13);
  expect(a, isNot(b));
  expect(a, startsWith('aichat_u_'));
  expect(a, isNot(contains('12')));
});
```

```dart
test('secure session 保存稳定 userId', () async {
  await store.save(const SecureSession(jwtToken: 'jwt', userId: 42));
  expect((await store.read())!.userId, 42);
});
```

- [ ] **Step 2: 运行测试并确认缺少账号作用域而失败**

Run: `flutter test test/account_database_scope_test.dart test/secure_session_store_test.dart`

- [ ] **Step 3: 实现不可逆数据库名派生**

```dart
abstract final class AccountDatabaseScope {
  static const guestDatabaseName = 'aichat_guest.db';
  static String databaseNameFor(int userId) {
    if (userId <= 0) throw ArgumentError.value(userId, 'userId');
    final digest = sha256.convert(utf8.encode('echo-account-db-v1:$userId'));
    return 'aichat_u_${digest.toString().substring(0, 24)}.db';
  }
}
```

- [ ] **Step 4: 实现串行数据库切换与旧库一次性认领**

```dart
static Future<void> switchAccount(int? userId) => _switchMutex.protect(() async {
  if (_currentUserId == userId && _database != null) return;
  final old = _database;
  _database = null;
  _cleanupDone = false;
  await old?.close();
  await AccountDatabaseMigration.claimLegacyIfNeeded(userId);
  _currentUserId = userId;
  _database = await _initDatabase(databaseName: _databaseNameFor(userId));
});
```

- [ ] **Step 5: 登录先切库再启用 JWT 业务，注销切 guest 库**

登录流程必须执行：解析 `user.id` → `switchAccount(user.id)` → 刷新数据库 Providers → 设置业务状态和启动后台任务。后台检查必须比较 `SecureSession.userId == DatabaseService.currentUserId`。

- [ ] **Step 6: 验证账号切换**

Run: `flutter test test/account_database_scope_test.dart test/secure_session_store_test.dart test/auth_state_test.dart`

### Task 3: 智能体客户端 ID 归属与聊天硬协议

**Files:**
- Modify: `website/API/models/user_agent.go`
- Modify: `website/API/handlers/user_agent.go`
- Modify: `website/API/services/user_agent_store.go`
- Modify: `website/API/handlers/chat.go`
- Create: `website/API/services/agent_ownership.go`
- Create: `website/API/handlers/agent_ownership_test.go`
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/providers/agent_provider.dart`
- Modify: `lib/services/api_service.dart`
- Modify: `test/api_service_client_reuse_test.dart`

**Interfaces:**
- `UserAgent.ClientID string`，按 `user_id + client_id` 唯一。
- `services.RequireOwnedAgent(userID uint, clientID string) (*models.UserAgent, error)`。
- `ChatRequest.ClientAgentID`、`ChatRequest.RequestKind`。

- [ ] **Step 1: 写跨账号和缺字段失败测试**

```go
func TestChatRejectsAgentOwnedByAnotherUser(t *testing.T) {
    // user 1 注册 client-agent-a，user 2 使用相同 client_agent_id 发起聊天。
    // 断言 403，且上游与计费预留均未调用。
}
```

- [ ] **Step 2: 运行并确认当前 ChatRequest 忽略 agent ID，测试失败**

Run: `cd website/API && go test -count=1 ./handlers -run 'TestChatRejectsAgentOwnedByAnotherUser|TestChatRequiresHardProtocolFields'`

- [ ] **Step 3: 扩展 UserAgent 并做幂等 upsert**

```go
type UserAgent struct {
    ID uint `json:"id"`
    UserID uint `json:"user_id"`
    ClientID string `json:"client_id"`
    RealInfoEnabled bool `json:"real_info_enabled"`
    ProactiveCareEnabled bool `json:"proactive_care_enabled"`
    ProactiveCareDailyLimit int `json:"proactive_care_daily_limit"`
    ProactiveCareMinIntervalHours int `json:"proactive_care_min_interval_hours"`
    // existing fields remain
}
```

- [ ] **Step 4: Chat Handler 在预留和上游调用前校验 `client_agent_id` 与 `request_kind`**

```go
type ChatRequest struct {
    ClientAgentID string `json:"client_agent_id" binding:"required"`
    RequestKind string `json:"request_kind" binding:"required,oneof=chat group_chat proactive_care"`
    ProactiveClaimToken string `json:"proactive_claim_token"`
    // existing fields
}
```

- [ ] **Step 5: Flutter 所有聊天请求顶层发送智能体 ID 和请求类型**

`ApiService.chatCompletion` 与 `chatCompletionStream` 新增必填 `clientAgentId`、`requestKind`，禁止从首条 message 的自定义键推断。

- [ ] **Step 6: 验证归属链路**

Run: `cd website/API && go test -count=1 ./handlers ./services`

Run: `flutter test test/api_service_client_reuse_test.dart test/chat_provider_agent_switch_test.dart`

### Task 4: 删除公开退款并将真实回复配额并入聊天事务

**Files:**
- Create: `website/API/models/feature_quota_reservation.go`
- Create: `website/API/services/feature_quota_reservation.go`
- Create: `website/API/services/feature_quota_reservation_test.go`
- Modify: `website/API/handlers/chat.go`
- Modify: `website/API/handlers/quota_handler.go`
- Modify: `website/API/routes/routes.go`
- Modify: `lib/services/quota_service.dart`
- Modify: `lib/providers/chat_provider.dart`
- Modify: `lib/services/proactive_care_service.dart`
- Modify: `test/quota_service_test.dart`

**Interfaces:**
- `ReserveFeatureQuota(userID uint, quotaType string) (*FeatureQuotaReservation, error)`。
- `CommitFeatureQuota(id string) error`、`ReleaseFeatureQuota(id string) error`，仅服务端调用。

- [ ] **Step 1: 写一次性状态转换测试**

```go
func TestFeatureQuotaReservationCanOnlyCommitOrReleaseOnce(t *testing.T) {
    reservation := reserveRealReply(t, userID)
    if err := CommitFeatureQuota(reservation.ID); err != nil { t.Fatal(err) }
    if err := ReleaseFeatureQuota(reservation.ID); !errors.Is(err, ErrReservationFinalized) { t.Fatalf("err=%v", err) }
}
```

- [ ] **Step 2: 写路由测试，断言 `/quota/refund` 为 404**

- [ ] **Step 3: 运行失败测试**

Run: `cd website/API && go test -count=1 ./services ./routes -run 'FeatureQuota|Refund'`

- [ ] **Step 4: 实现服务端私有预留状态机并接入 Chat Handler**

仅 `ownedAgent.RealInfoEnabled && request_kind == chat` 或有效主动关心 claim 时预留真实回复配额；任何失败路径 defer release，成功路径 commit。

- [ ] **Step 5: 删除 Flutter 真实回复预扣和 refund 调用**

OCR 仍在识别成功后调用 `consume(ocr)`；`QuotaService` 不再暴露 refund。

- [ ] **Step 6: 验证计费链路**

Run: `cd website/API && go test -count=1 ./handlers ./services ./routes`

Run: `flutter test test/quota_service_test.dart test/chat_provider_agent_switch_test.dart test/proactive_care_service_test.dart`

### Task 5: 服务端主动关心 claim/commit

**Files:**
- Create: `website/API/models/proactive_care_task.go`
- Create: `website/API/services/proactive_care_service.go`
- Create: `website/API/services/proactive_care_service_test.go`
- Create: `website/API/handlers/proactive_care.go`
- Create: `website/API/handlers/proactive_care_test.go`
- Modify: `website/API/routes/routes.go`
- Create: `lib/services/proactive_care_api.dart`
- Modify: `lib/services/proactive_care_service.dart`
- Modify: `test/proactive_care_service_test.dart`

**Interfaces:**
- `POST /api/v1/proactive-care/claim` 返回 `{claim_token, expires_at}`。
- `POST /api/v1/proactive-care/commit` 和 `/release`。
- `ClaimProactiveCare(userID, agentClientID, localDate string, now time.Time) (*Task, error)`。

- [ ] **Step 1: 写跨设备并发测试**

```go
func TestConcurrentProactiveClaimsOnlyOneSucceeds(t *testing.T) {
    var success atomic.Int32
    var wg sync.WaitGroup
    for range 2 {
        wg.Add(1)
        go func() { defer wg.Done(); if _, err := ClaimProactiveCare(userID, agentID, "2026-08-17", now); err == nil { success.Add(1) } }()
    }
    wg.Wait()
    if success.Load() != 1 { t.Fatalf("success=%d", success.Load()) }
}
```

- [ ] **Step 2: 运行失败测试**

Run: `cd website/API && go test -count=1 -race ./services ./handlers -run ProactiveCare`

- [ ] **Step 3: 实现事务 claim/commit/release、过期回收和 agent 配置二次检查**

- [ ] **Step 4: Flutter 先取得服务端 claim，再以 `request_kind=proactive_care` 调用聊天，最后 commit**

任何异常 release；本地 `ProactiveCareStore` 只负责消息提交幂等，不再作为每日上限权威源。

- [ ] **Step 5: 验证主动关心链路**

Run: `cd website/API && go test -count=1 -race ./services ./handlers -run ProactiveCare`

Run: `flutter test test/proactive_care_service_test.dart test/proactive_care_store_test.dart`

### Task 6: 画像周期、记忆作用域、容量与 Provider 竞态

**Files:**
- Modify: `lib/services/memory_scheduler.dart`
- Modify: `test/memory_scheduler_test.dart`
- Create: `lib/services/memory_scope.dart`
- Modify: `lib/services/memory_service.dart`
- Modify: `lib/services/database_memory_store.dart`
- Modify: `lib/services/database_schema.dart`
- Modify: `lib/providers/group_provider.dart`
- Modify: `lib/providers/memory_provider.dart`
- Create: `test/memory_scope_test.dart`
- Create: `test/memory_provider_race_test.dart`
- Modify: `lib/agreements/privacy_policy.dart`

**Interfaces:**
- `sealed class MemoryScope`，具体为 `PrivateAgentScope`、`GroupAgentScope`、`GroupSharedScope`。
- `MemoryService({required MemoryScope scope})`，不再允许空 ID 创建长期/基础记忆。

- [ ] **Step 1: 将触发测试改为第 10 轮，并先确认现实现失败**

```dart
test('第 1-9 轮 false，第 10 轮 true', () async {
  for (var i = 1; i <= 9; i++) expect(await scheduler.shouldRunMemoryAi('a1'), isFalse);
  expect(await scheduler.shouldRunMemoryAi('a1'), isTrue);
});
```

- [ ] **Step 2: 写空作用域拒绝、群共享在场记录和迟到结果丢弃测试**

- [ ] **Step 3: 运行失败测试**

Run: `flutter test test/memory_scheduler_test.dart test/memory_scope_test.dart test/memory_provider_race_test.dart`

- [ ] **Step 4: 实现 10 轮、类型化 scope、群共享在场记录和 v38 孤儿数据迁移**

长期记忆插入在同一事务中查询 agent 私聊/群成员作用域数量，超过 15 条时删除最旧非永久记录后再插入。

- [ ] **Step 5: Provider 使用 generation 防迟到覆盖**

```dart
final generation = ++_loadGeneration;
final targetAgentId = _memoryService.agentId;
final memories = await _repo.getLongTermMemories(agentId: targetAgentId!);
if (generation != _loadGeneration || _memoryService.agentId != targetAgentId) return;
state = state.copyWith(memories: memories, isLoading: false);
```

- [ ] **Step 6: 修改隐私协议为 TLS 传输与服务端 AES 存储**

- [ ] **Step 7: 验证记忆与画像**

Run: `flutter test test/memory_scheduler_test.dart test/memory_scope_test.dart test/memory_provider_race_test.dart test/memory_service_agent_isolation_test.dart`

### Task 7: 同步 AES envelope 与 WebSocket ticket

**Files:**
- Create: `website/API/services/sensitive_envelope.go`
- Create: `website/API/services/sensitive_envelope_test.go`
- Modify: `website/API/handlers/sync_handler.go`
- Modify: `website/API/handlers/sync_v2_handler.go`
- Create: `website/API/services/sync_sensitive_migration.go`
- Create: `website/API/models/sync_ws_ticket.go`
- Create: `website/API/services/sync_ws_ticket.go`
- Create: `website/API/services/sync_ws_ticket_test.go`
- Modify: `website/API/handlers/sync_ws_handler.go`
- Modify: `website/API/routes/routes.go`
- Modify: `lib/services/sync_websocket_service.dart`
- Modify: `test/sync_websocket_message_test.dart`

**Interfaces:**
- `SealSensitiveField(table, field, plaintext string) (string, error)` 返回 `enc:v1:<base64>`。
- `OpenSensitiveField(value string) (plaintext string, needsMigration bool, err error)`。
- `POST /api/v1/sync/ws-ticket` 返回一次性 ticket；WS 仅接受 `ticket`。

- [ ] **Step 1: 写 envelope 幂等、历史密文兼容和明文迁移测试**

```go
func TestSealSensitiveFieldDoesNotDoubleEncrypt(t *testing.T) {
    sealed, _ := SealSensitiveField("long_term_memories", "Content", "秘密")
    again, _ := SealSensitiveField("long_term_memories", "Content", sealed)
    if again != sealed { t.Fatalf("double encryption") }
}
```

- [ ] **Step 2: 写 WS ticket 过期、重放和设备不匹配测试**

- [ ] **Step 3: 运行失败测试**

Run: `cd website/API && go test -count=1 -race ./services ./handlers -run 'Sensitive|WSTicket'`

- [ ] **Step 4: 扩展敏感字段注册表并在启动迁移历史记录**

覆盖 agents、user_profiles、long/base/short_term、group_shared/group_short_term、providers；解密失败不得静默返回空字符串。

- [ ] **Step 5: 实现数据库原子消费 ticket，删除 JWT query 支持**

- [ ] **Step 6: Flutter 建连前使用 Authorization 获取 ticket**

- [ ] **Step 7: 验证同步安全链路**

Run: `cd website/API && go test -count=1 -race ./services ./handlers ./routes -run 'Sync|Sensitive|WSTicket'`

Run: `flutter test test/sync_websocket_message_test.dart test/sync_payload_builder_test.dart test/sync_response_applier_test.dart`

### Task 8: 更新包完整性、唯一性和强更状态机

**Files:**
- Modify: `website/API/models/app_version.go`
- Modify: `website/API/handlers/update.go`
- Create: `website/API/services/update_integrity.go`
- Create: `website/API/services/update_integrity_test.go`
- Create: `website/API/handlers/update_test.go`
- Modify: `website/API/database/database.go`
- Modify: `lib/services/update_service.dart`
- Modify: `lib/screens/force_update_screen.dart`
- Create: `lib/services/update_installer.dart`
- Create: `test/update_service_test.dart`

**Interfaces:**
- AppVersion 增加 `SHA256`、`Signature`、`SignatureAlgorithm`、`SigningKeyID`。
- `ValidateReleaseSource(ctx, downloadURL, expectedHash string) error`。
- `UpdateInstaller.downloadVerifyAndOpen(UpdateInfo) Future<void>`。

- [ ] **Step 1: 写 SSRF 重定向、重复版本和原子计数失败测试**

- [ ] **Step 2: 写客户端完整响应校验与哈希不匹配测试**

- [ ] **Step 3: 运行失败测试**

Run: `cd website/API && go test -count=1 -race ./services ./handlers -run Update`

Run: `flutter test test/update_service_test.dart`

- [ ] **Step 4: 实现发布前 URL 每跳校验、SHA-256 与 Ed25519 签名验证**

仅允许 HTTPS；每次 DNS 解析结果都拒绝 loopback/private/link-local；最多 5 次重定向。

- [ ] **Step 5: 添加 `(platform, version_code)` 唯一索引和下载量原子 increment**

- [ ] **Step 6: 客户端下载临时文件，先哈希后验签再打开**

- [ ] **Step 7: `_checked` 仅在 schema 完整时置位并持久化强更策略**

- [ ] **Step 8: 验证更新链路**

Run: `cd website/API && go test -count=1 -race ./services ./handlers -run Update`

Run: `flutter test test/update_service_test.dart`

### Task 9: 单一模型准入、可追踪 usage 和旧余额语义清理

**Files:**
- Create: `website/API/services/model_admission.go`
- Create: `website/API/services/model_admission_test.go`
- Modify: `website/API/services/deepseek_service.go`
- Modify: `website/API/services/billing_reservation.go`
- Modify: `website/API/models/usage_record.go`
- Modify: `website/API/handlers/chat.go`
- Modify: `website/API/handlers/vision.go`
- Modify: `website/API/services/billing_service.go`
- Modify: `website/API/services/billing_service_test.go`
- Modify: `lib/services/api_service.dart`

**Interfaces:**
- `ResolveModelAdmission(userID uint, modelID string, thinking bool) (*ModelAdmission, error)`。
- UsageRecord 增加 `UsageSource`、`EstimatorVersion`、`EstimateReason`。
- DeepSeek 流请求发送 `stream_options.include_usage=true`。

- [ ] **Step 1: 写禁用/无价格/无密钥模型在计费前拒绝的测试**

- [ ] **Step 2: 写缺失 usage 时不再返回固定 100/100 且记录估算来源的测试**

- [ ] **Step 3: 写响应不再包含 `balance_after` 的测试**

- [ ] **Step 4: 运行失败测试**

Run: `cd website/API && go test -count=1 ./services ./handlers -run 'ModelAdmission|Usage|BalanceAfter'`

- [ ] **Step 5: 实现统一准入并替换模型列表、聊天、计费、上游路由和视觉路径的散落判断**

- [ ] **Step 6: 实现 usage 请求与估算元数据**

估算器按 UTF-8 文本/视觉 JSON 的实际内容计算并版本化；成功响应缺 usage 与流中断分别记录不同原因。

- [ ] **Step 7: 删除 `balance_after` 与生产 `DeductAndRecord` 调用**

- [ ] **Step 8: 验证模型与计费链路**

Run: `cd website/API && go test -count=1 ./services ./handlers`

### Task 10: 全量验证与审计复核

**Files:**
- Modify only where a failing verification proves a defect in Tasks 1-9.

**Interfaces:**
- Produces: 可重复的 Flutter/Go 绿色验证证据和逐项审计映射。

- [ ] **Step 1: 格式化**

Run: `dart format lib test`

Run: `cd website/API && gofmt -w handlers middleware models routes services database`

- [ ] **Step 2: Flutter 静态分析和测试**

Run: `flutter analyze`

Run: `flutter test`

- [ ] **Step 3: Go 无缓存、竞态和构建验证**

Run: `cd website/API && go test -count=1 ./...`

Run: `cd website/API && go test -race -count=1 ./...`

Run: `cd website/API && go build ./...`

- [ ] **Step 4: 差异与安全扫描**

Run: `git diff --check`

Run: `rg -n "quota/refund|balance_after|\?token=|PromptTokens = 100|CompletionTokens = 100|roundsInterval = 5" lib website/API`

- [ ] **Step 5: 对照设计文档逐项确认 P0/P1/P2，无未解释遗漏后再报告完成**
