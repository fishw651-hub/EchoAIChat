# Security and Performance Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Go 后端可靠迁移到 SQLite，并修复计费、权限、资源耗尽、客户端凭据和群聊记忆隔离问题。

**Architecture:** Go 数据库使用 `modernc.org/sqlite` 和 `database/sql` 实现 SQLite 文档存储适配层，保留现有 `DB/Table/Filter` API，并为计费提供显式事务。Flutter 使用可注入的安全存储与 HTTP Client，每个并行角色持有独立、不可变的记忆上下文。迁移与安全改造均先写回归测试，再实现最小修复。

**Tech Stack:** Go 1.25、Gin、`database/sql`、`modernc.org/sqlite`、Flutter、Riverpod、sqflite、`flutter_secure_storage`、package:http。

## Global Constraints

- 永远使用中文沟通和错误提示。
- 不修改 `lib/agreements/`。
- 不重新启用 Kotlin 增量编译。
- 不记录 API Key、JWT、密码或完整上游错误响应。
- 不提交 Git；当前工作区包含大量用户未提交修改。
- Go 迁移失败时拒绝启动，禁止 JSON 与 SQLite 双写。
- Flutter `flutter analyze` 必须为 0 errors；现有 info/warning 可单独报告。

---

### Task 1: SQLite 文档存储与 JSON 一次性迁移

**Files:**
- Create: `website/API/database/sqlite_store.go`
- Create: `website/API/database/migration.go`
- Create: `website/API/database/sqlite_store_test.go`
- Modify: `website/API/database/database.go`
- Modify: `website/API/go.mod`

**Interfaces:**
- Produces: `Init(dir string) error` 打开 `data/aichat.db` 并自动迁移。
- Produces: `(*DB).WithTx(context.Context, func(*Tx) error) error`。
- Produces: `(*DB).SQL() *sql.DB`，仅供计费事务仓库使用。
- Preserves: `Register`, `Insert`, `FindByID`, `FindOne`, `FindAll`, `UpdateWhere`, `IncrementField` 与同步批量 API。

- [ ] **Step 1: 写迁移失败测试**

```go
func TestInitMigratesJSONOnce(t *testing.T) {
    dir := t.TempDir()
    require.NoError(t, os.WriteFile(filepath.Join(dir, "User.json"), []byte(`[{"ID":1,"Username":"alice"}]`), 0o600))
    require.NoError(t, Init(dir))
    var user struct{ ID uint; Username string }
    require.True(t, Get().Register("User").FindByID(1, &user))
    require.Equal(t, "alice", user.Username)
    require.NoError(t, Get().Close())
    require.NoError(t, Init(dir))
    require.EqualValues(t, 1, Get().Register("User").Count(nil))
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `go test ./database -run TestInitMigratesJSONOnce -count=1`
Expected: FAIL，因为当前 `Init` 只注册内存 JSON 表，不创建 `aichat.db`。

- [ ] **Step 3: 实现 SQLite schema 和迁移器**

```sql
CREATE TABLE records (
  table_name TEXT NOT NULL,
  id INTEGER NOT NULL,
  payload BLOB NOT NULL,
  user_id INTEGER,
  client_id TEXT,
  order_no TEXT,
  status TEXT,
  updated_at TEXT,
  PRIMARY KEY (table_name, id)
);
CREATE TABLE table_sequences (table_name TEXT PRIMARY KEY, seq INTEGER NOT NULL);
CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
CREATE INDEX idx_records_user ON records(table_name, user_id);
CREATE UNIQUE INDEX idx_records_client ON records(table_name, user_id, client_id) WHERE client_id IS NOT NULL AND client_id <> '';
CREATE INDEX idx_records_order ON records(table_name, order_no);
CREATE INDEX idx_records_status ON records(table_name, status);
CREATE INDEX idx_records_updated ON records(table_name, user_id, updated_at);
```

实现 `modernc.org/sqlite` 驱动、WAL、`busy_timeout=5000`、`foreign_keys=ON`。迁移事务逐个读取 `*.json`，写入 `records`，校验数量后写 migration marker；提交成功后移动到 `legacy-json-<timestamp>`。

- [ ] **Step 4: 将 Table API 改为 SQLite 实现**

`Filter` 保留为闭包兼容路径；`FindByID`、`FindAllByUserID`、`FindByUserIDClientID` 和批量同步方法使用索引列直接查询。所有写操作返回并传播 SQLite 错误，不再调用 `os.WriteFile`。

- [ ] **Step 5: 验证迁移、幂等和回滚**

Run: `go test ./database -count=1`
Expected: PASS，包括损坏 JSON 时无 migration marker、无备份移动、原文件不变。

### Task 2: 事务化计费预留与结算

**Files:**
- Create: `website/API/services/billing_reservation.go`
- Create: `website/API/services/billing_reservation_test.go`
- Modify: `website/API/services/billing_service.go`
- Modify: `website/API/handlers/chat.go`
- Modify: `website/API/models/usage_record.go`

**Interfaces:**
- Produces: `Reserve(ctx, userID, modelID string, maxTokens int, thinking bool) (*BillingReservation, error)`。
- Produces: `Settle(ctx, reservationID string, usage TokenUsage) (cost float64, error)`。
- Produces: `Release(ctx, reservationID string) error`。

- [ ] **Step 1: 写余额不足不调用上游测试**

```go
func TestChatRejectsBeforeCallingUpstream(t *testing.T) {
    upstream := &countingChatService{}
    handler := newTestChatHandler(upstream, testBillingWithQuota(0))
    response := performChat(handler, validChatBody())
    require.Equal(t, http.StatusPaymentRequired, response.Code)
    require.Equal(t, 0, upstream.Calls())
}
```

- [ ] **Step 2: 写并发预留测试并确认 RED**

Run: `go test ./services ./handlers -run 'TestConcurrentReserve|TestChatRejectsBeforeCallingUpstream' -count=1`
Expected: FAIL，当前代码先调用上游，且检查与扣费不是同一事务。

- [ ] **Step 3: 增加持久化预留表和用户级锁**

```sql
CREATE TABLE billing_reservations (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  model_id TEXT NOT NULL,
  reserved_cost REAL NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending','settled','released')),
  created_at TEXT NOT NULL,
  settled_at TEXT
);
CREATE INDEX idx_billing_reservation_user_status ON billing_reservations(user_id, status);
```

`Reserve` 在用户锁和 SQLite transaction 内重新读取 User JSON payload、计算最大费用、增加对应额度字段并插入 reservation。`Settle` 计算真实费用、退回差额、插入 UsageRecord 并将状态改为 settled。上游错误调用 `Release`。

- [ ] **Step 4: 将聊天 Handler 改为 reserve → upstream → settle**

普通和流式接口必须在写响应头前完成预留；流式结算错误只记录服务端错误，不向已经完成的客户端泄露内部状态。

- [ ] **Step 5: 验证所有计费路径**

Run: `go test ./services ./handlers -run 'Billing|Chat' -count=1`
Expected: PASS；并发请求只有一个成功预留，上游失败后额度恢复。

### Task 3: 管理权限与会话状态加固

**Files:**
- Create: `website/API/middleware/admin_test.go`
- Modify: `website/API/middleware/auth.go`
- Modify: `website/API/middleware/admin.go`
- Modify: `website/API/routes/routes.go`
- Modify: `website/API/handlers/admin.go`
- Modify: `website/API/utils/jwt.go`

**Interfaces:**
- Produces: `CurrentUserRequired()` 每次从 SQLite 验证用户状态与当前角色。
- Preserves: `AuthRequired()` 名称，但不再完全信任 JWT role claim。

- [ ] **Step 1: 写普通管理员提权失败测试**

```go
func TestAdminCannotPromoteUserToSuperAdmin(t *testing.T) {
    router := setupAdminRouter("admin")
    response := requestJSON(router, http.MethodPut, "/api/v1/admin/users/2", `{"role":"super_admin"}`)
    require.Equal(t, http.StatusForbidden, response.Code)
}
```

- [ ] **Step 2: 运行并确认 RED**

Run: `go test ./middleware ./handlers -run 'AdminCannot|DisabledUser' -count=1`
Expected: FAIL，当前普通 admin 可写任意 Role，禁用用户旧 JWT 仍可访问。

- [ ] **Step 3: 挂载超级管理员路由和角色白名单**

角色、余额、管理员创建、删除、系统配置、API Key 与证书接口使用 `SuperAdminRequired`。内容审核接口保留 `AdminRequired`。JWT parser 添加 `jwt.WithValidMethods([]string{"HS256"})`。

- [ ] **Step 4: 验证权限矩阵**

Run: `go test ./middleware ./handlers -run 'Admin|Auth|JWT' -count=1`
Expected: PASS。

### Task 4: HTTP 边界、限流器和连接池

**Files:**
- Create: `website/API/middleware/bodylimit.go`
- Create: `website/API/middleware/bodylimit_test.go`
- Modify: `website/API/main.go`
- Modify: `website/API/middleware/ratelimit.go`
- Modify: `website/API/services/deepseek_service.go`
- Modify: `website/API/services/payment_service.go`
- Modify: `website/API/services/ifdian_service.go`
- Modify: `website/API/handlers/sync_ws_handler.go`

**Interfaces:**
- Produces: `BodyLimit(maxBytes int64) gin.HandlerFunc`。
- Produces: package-level shared `*http.Client` instances with tuned transports.

- [ ] **Step 1: 写超限请求和限流淘汰测试**

```go
func TestBodyLimitRejectsOversizedJSON(t *testing.T) {
    router := gin.New()
    router.Use(BodyLimit(32))
    router.POST("/", func(c *gin.Context) { c.Status(http.StatusNoContent) })
    response := requestWithBody(router, strings.Repeat("x", 33))
    require.Equal(t, http.StatusRequestEntityTooLarge, response.Code)
}
```

- [ ] **Step 2: 运行并确认 RED**

Run: `go test ./middleware -run 'BodyLimit|LimiterEvicts' -count=1`
Expected: FAIL，因为尚无请求体中间件且 limiter 永不清理。

- [ ] **Step 3: 实现边界保护**

JSON 默认 4 MiB，同步全量上传 32 MiB，Multipart 使用配置上限。HTTP Server 设置 `ReadHeaderTimeout: 5s`、`ReadTimeout: 30s`、`WriteTimeout: 330s`、`IdleTimeout: 90s`、`MaxHeaderBytes: 1<<20`。`SetTrustedProxies(nil)` 默认不信任代理。

- [ ] **Step 4: 复用 HTTP Transport**

Transport 使用 `MaxIdleConns: 100`、`MaxIdleConnsPerHost: 20`、`IdleConnTimeout: 90s`、`TLSHandshakeTimeout: 10s`、`ResponseHeaderTimeout` 按供应商设置。检查 `NewRequest`、`Marshal`、`ReadAll` 错误并限制错误响应为 64 KiB。

- [ ] **Step 5: 验证网络层**

Run: `go test ./middleware ./services -run 'BodyLimit|Limiter|DeepSeek|Payment|Ifdian' -count=1`
Expected: PASS。

### Task 5: 上传验证和 Go 静态检查清理

**Files:**
- Modify: `website/API/services/file_service.go`
- Modify: `website/API/utils/validator.go`
- Modify: `website/API/handlers/network_agent.go`
- Modify: `website/API/handlers/network_group.go`
- Modify: `website/API/handlers/payment.go`
- Modify: `website/API/services/payment_service.go`
- Create: `website/API/services/file_service_test.go`

- [ ] **Step 1: 写 Base64 大小和扩展名测试**

```go
func TestSaveBase64ImageRejectsOversizeBeforeDecode(t *testing.T) {
    encoded := "data:image/png;base64," + strings.Repeat("A", maxEncodedImageBytes+4)
    _, err := SaveBase64Image(encoded, "network_agents")
    require.ErrorIs(t, err, ErrImageTooLarge)
}
```

- [ ] **Step 2: 运行并确认 RED**

Run: `go test ./services -run SaveBase64Image -count=1`
Expected: FAIL，当前实现直接完整解码。

- [ ] **Step 3: 实现 MIME、大小和目录白名单**

只允许 JPEG/PNG/WebP；使用估算解码长度拒绝超限内容；`subdir` 必须来自内部枚举，不接受路径分隔符。删除 `go vet` 指出的不可达代码。

- [ ] **Step 4: 验证**

Run: `go test ./... && go vet ./...`
Expected: 全部 PASS 且 vet 无输出。

### Task 6: Flutter 系统安全存储迁移

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/providers/auth_provider.dart`
- Create: `lib/services/secure_session_store.dart`
- Create: `test/secure_session_store_test.dart`
- Modify: platform plugin registrants generated by Flutter tooling only if required。

**Interfaces:**
- Produces: `SecureSessionStore.readSession()`、`writeSession()`、`clear()`、`migrateLegacy(SharedPreferences)`。
- Removes: 登录密码持久化和自动密码重登。

- [ ] **Step 1: 写旧凭据迁移测试**

```dart
test('迁移后删除旧令牌和登录密码', () async {
  SharedPreferences.setMockInitialValues(legacyEncryptedValues);
  final secure = FakeSecureStorage();
  final store = SecureSessionStore(storage: secure);
  await store.migrateLegacy(await SharedPreferences.getInstance());
  expect(await secure.read(key: 'auth_jwt'), isNotEmpty);
  expect((await SharedPreferences.getInstance()).containsKey('auth_login_password'), isFalse);
});
```

- [ ] **Step 2: 运行并确认 RED**

Run: `flutter test test/secure_session_store_test.dart`
Expected: FAIL，因为服务和依赖尚不存在。

- [ ] **Step 3: 添加 `flutter_secure_storage` 并实现迁移**

安全存储只保存 JWT、refresh token、API Key 和 API Key ID。旧 XOR 仅用于一次读取；无论迁移成功与否，都删除保存的用户名和密码。刷新失败后要求用户重新登录，不再用密码自动重登。

- [ ] **Step 4: 验证认证测试**

Run: `flutter test test/secure_session_store_test.dart test/auth_state_test.dart`
Expected: PASS。

### Task 7: 群聊记忆上下文隔离和异步写顺序

**Files:**
- Modify: `lib/services/memory_service.dart`
- Modify: `lib/providers/group_provider.dart`
- Modify: `lib/providers/chat_provider.dart`
- Modify: `lib/services/tool_executor.dart`
- Create: `test/memory_service_isolation_test.dart`

**Interfaces:**
- Produces: `MemoryService({String? agentId, String? groupId})`。
- Produces: `MemoryService.scoped({required String agentId, String? groupId})` 返回独立实例。
- Changes: `addShortTermMessage`、`clearShortTerm`、`compressShortTerm` 返回 `Future` 并等待数据库操作。

- [ ] **Step 1: 写并行上下文隔离测试**

```dart
test('两个 scoped memory service 不共享 agent 或 group', () async {
  final first = MemoryService.scoped(agentId: 'a1', groupId: 'g1');
  final second = MemoryService.scoped(agentId: 'a2', groupId: 'g1');
  expect(first.agentId, 'a1');
  expect(second.agentId, 'a2');
  first.setAgentId('changed');
  expect(second.agentId, 'a2');
});
```

- [ ] **Step 2: 运行并确认 RED**

Run: `flutter test test/memory_service_isolation_test.dart`
Expected: FAIL，因为 scoped constructor 尚不存在。

- [ ] **Step 3: 每个角色创建独立实例**

`_runGroupToolLoop`、`_groupMemoryAi` 与 presence 写入均使用局部 `MemoryService`；禁止读取全局 `memoryServiceProvider` 后再修改 agent/group。私聊仍使用 provider 单例，但所有数据库写按调用顺序等待。

- [ ] **Step 4: 验证群聊和记忆测试**

Run: `flutter test test/memory_service_isolation_test.dart test/widget_test.dart`
Expected: PASS。

### Task 8: Flutter SQLite 索引与启动维护

**Files:**
- Modify: `lib/services/database_service.dart`
- Create: `test/database_index_test.dart`

- [ ] **Step 1: 写索引幂等测试**

测试 `_ensureIndexes` 在新库和已有库中均创建 `agent_id/group_id/timestamp/scheduled_time` 组合索引，重复执行不报错。

- [ ] **Step 2: 运行并确认 RED**

Run: `flutter test test/database_index_test.dart`
Expected: FAIL，新建数据库当前不会执行升级分支中的索引逻辑。

- [ ] **Step 3: 提取 `_ensureIndexes` 并移除启动 VACUUM**

`_onCreate`、`_onUpgrade` 和每次 open 后调用幂等索引方法。例行清理只执行批量 DELETE 和 `PRAGMA wal_checkpoint(PASSIVE)`；不在启动路径运行 `VACUUM`。

- [ ] **Step 4: 验证数据库测试**

Run: `flutter test test/database_index_test.dart`
Expected: PASS。

### Task 9: Flutter HTTP 连接复用与 build 同步 I/O 清理

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/services/network_service.dart`
- Modify: `lib/services/sync_service.dart`
- Modify: `lib/screens/chat_screen.dart`
- Create: `test/api_client_lifecycle_test.dart`

**Interfaces:**
- Produces: 各网络服务构造器接受可选 `http.Client`，仅关闭自己创建的 Client。
- Changes: 聊天背景存在状态在 agent/background 变化时异步刷新。

- [ ] **Step 1: 写 Client 复用测试**

```dart
test('ApiService 连续调用复用注入的 client', () async {
  final client = CountingClient(successResponse);
  final service = ApiService(baseUrl: baseUrl, apiKey: key, model: model, client: client);
  await service.chatCompletion(messages: messages, tools: tools);
  await service.chatCompletion(messages: messages, tools: tools);
  expect(client.requestCount, 2);
  expect(client.closeCount, 0);
});
```

- [ ] **Step 2: 运行并确认 RED**

Run: `flutter test test/api_client_lifecycle_test.dart`
Expected: FAIL，当前服务不接受 Client。

- [ ] **Step 3: 实现 Client 生命周期和背景缓存**

所有请求使用实例 Client。`ChatScreen` 不在 build 中调用 `File.existsSync()`，改为缓存的 `_backgroundFileExists`，由 `didChangeDependencies`/agent 变化异步更新。

- [ ] **Step 4: 验证网络层测试**

Run: `flutter test test/api_client_lifecycle_test.dart`
Expected: PASS。

### Task 10: 全量验证与迁移演练

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-security-performance-hardening-design.md` only if implementation constraints changed。

- [ ] **Step 1: Go 全量验证**

Run: `go test ./...`
Expected: PASS。

Run: `go vet ./...`
Expected: 无输出，退出码 0。

- [ ] **Step 2: Flutter 全量验证**

Run: `flutter analyze`
Expected: 0 errors。

Run: `flutter test`
Expected: PASS。

- [ ] **Step 3: 数据迁移演练**

复制脱敏 JSON fixture 到临时目录，运行迁移两次；确认 SQLite 数量一致、第二次无重复、旧 JSON 只在成功后进入备份目录、服务 CRUD 测试全部使用 SQLite。

- [ ] **Step 4: 安全复查**

Run: `rg -n "auth_login_password|_xorTransform|http\.Client\{" lib website/API --glob '*.dart' --glob '*.go'`
Expected: 不再保存密码；XOR 仅存在于受限迁移兼容代码；后端 HTTP Client 只在集中工厂创建。
