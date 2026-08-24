# Device-Aware Selective Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为回响增加稳定设备身份、账号级智能体同步范围、带预览的单次双向同步，并让持续实时同步服从该范围。

**Architecture:** 服务端持久化带版本号的 `SyncPolicy`，并用短时 `SyncPreview` 绑定用户、设备、策略版本和范围快照；服务端与客户端都通过同一六表闭包规则过滤数据。Flutter 用平台条件导入构建 `DeviceIdentity`，同步执行器负责快照、预览、双向合并和失败保留，界面只操作策略和运行命令。

**Tech Stack:** Flutter/Dart、Riverpod、sqflite、Go、Gin、项目内 SQLite 记录仓储、WebSocket。

## Global Constraints

- 保留旧 `/api/v1/sync/all`、`/api/v1/sync/devices/full_sync` 的兼容行为。
- `selected` 范围仅包含 `agents`、`chat_messages`、`short_term_messages`、私聊 `long_term_memories`、私聊 `base_memories`、私聊 `planned_messages`。
- 所有客户端数据库读取、写入和墓碑应用都必须按 `agent_id` 隔离。
- 单次同步不修改账号级策略，取消选择不生成删除墓碑。
- 所有新 Go/Flutter 生产行为先写失败测试再实现。
- 不修改 `website/API/frontend/admin/`，不覆盖现有聊天隔离改动。

---

### Task 1: Device Identity and Automatic Registration

**Files:**
- Create: `lib/models/device_identity.dart`
- Create: `lib/services/platform_device_identity.dart`
- Create: `lib/services/platform_device_identity_io.dart`
- Create: `lib/services/platform_device_identity_web.dart`
- Modify: `lib/services/device_id_service.dart`
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/providers/auth_provider.dart`
- Test: `test/device_identity_test.dart`

**Interfaces:**
- Produces: `DeviceIdentity(id, displayName, clientKind, platform, browser)`。
- Produces: `DeviceIdService.identity` 与 `AuthService.registerCurrentDevice()`。

- [ ] **Step 1: Write failing identity tests**

```dart
test('web identity keeps persisted id and reports browser', () async {
  final store = FakeDeviceIdentityStore(existingId: 'web-uuid');
  final identity = await buildWebDeviceIdentity(store, 'Mozilla/5.0 Edg/126.0');
  expect(identity.id, 'web-uuid');
  expect(identity.clientKind, 'web');
  expect(identity.browser, 'Edge');
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/device_identity_test.dart`
Expected: FAIL because `DeviceIdentity` and browser parsing do not exist.

- [ ] **Step 3: Implement platform-neutral identity**

```dart
class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.displayName,
    required this.clientKind, required this.platform, this.browser});
  final String id;
  final String displayName;
  final String clientKind;
  final String platform;
  final String? browser;
}
```

Use conditional exports so `SyncDevicesScreen` and providers never import `dart:io`; web stores one UUID per browser profile in local storage and parses Edge/Chrome/Firefox before generic Safari.

- [ ] **Step 4: Register after every authenticated session transition**

Call `registerCurrentDevice()` after login, credential re-login, token restore/refresh, and authenticated app startup. Registration sends `device_id`, `device_name`, `client_kind`, `platform`, and `browser`; failures remain retryable and do not log the user out.

- [ ] **Step 5: Verify green**

Run: `flutter test test/device_identity_test.dart`
Expected: PASS.

### Task 2: Server Device and Policy Contract

**Files:**
- Modify: `website/API/models/device.go`
- Create: `website/API/services/sync_policy_service.go`
- Modify: `website/API/handlers/device_handler.go`
- Modify: `website/API/routes/routes.go`
- Test: `website/API/services/sync_policy_service_test.go`
- Test: `website/API/handlers/device_handler_test.go`

**Interfaces:**
- Consumes: `X-Device-ID` and registration payload from Task 1.
- Produces: `GET /api/v1/sync/policy`, `PUT /api/v1/sync/policy`.

- [ ] **Step 1: Write failing policy tests**

```go
func TestUpdateSyncPolicyRejectsStaleVersion(t *testing.T) {
    current := models.SyncSetting{UserID: 7, ScopeMode: "selected", PolicyVersion: 3}
    _, err := mergeSyncPolicy(current, models.SyncPolicyUpdate{ExpectedVersion: 2})
    require.ErrorIs(t, err, ErrSyncPolicyConflict)
}

func TestLegacyFullSyncMigratesToRealtimeAll(t *testing.T) {
    policy := policyFromSetting(models.SyncSetting{FullSyncEnabled: true})
    assert.Equal(t, "all", policy.ScopeMode)
    assert.True(t, policy.RealtimeEnabled)
}
```

- [ ] **Step 2: Verify red**

Run: `cd website/API && go test ./services ./handlers -run 'Test(UpdateSyncPolicy|LegacyFullSync|RegisterDevice)'`
Expected: FAIL because policy fields and service do not exist.

- [ ] **Step 3: Extend models and policy service**

```go
type SyncSetting struct {
    ID uint `json:"id"`; UserID uint `json:"user_id"`
    FullSyncEnabled bool `json:"full_sync_enabled"`
    ScopeMode string `json:"scope_mode"`
    SelectedAgentIDs []string `json:"selected_agent_ids"`
    RealtimeEnabled bool `json:"realtime_enabled"`
    PolicyVersion uint64 `json:"policy_version"`
    CreatedAt time.Time `json:"created_at"`; UpdatedAt time.Time `json:"updated_at"`
}
```

`GetPolicy(userID)` normalizes legacy records to `scope_mode=all`, maps `FullSyncEnabled` to `RealtimeEnabled`, and initializes version 1. `UpdatePolicy` validates mode, at most 500 unique non-empty agent IDs, checks `ExpectedVersion`, increments version atomically under a service mutex, and broadcasts `sync_policy`.

- [ ] **Step 4: Extend device heartbeat fields**

Add `ClientKind`, `Browser`, and `LastSyncAt` to `Device`; registration upserts on `(UserID, DeviceID)` and refreshes metadata without changing user-edited names when the incoming name is empty.

- [ ] **Step 5: Verify green**

Run: `cd website/API && go test ./services ./handlers -run 'Test(UpdateSyncPolicy|LegacyFullSync|RegisterDevice)'`
Expected: PASS.

### Task 3: Shared Scope Filtering and LWW Merge

**Files:**
- Create: `website/API/services/sync_scope.go`
- Create: `website/API/services/sync_merge.go`
- Test: `website/API/services/sync_scope_test.go`
- Test: `website/API/services/sync_merge_test.go`

**Interfaces:**
- Produces: `SyncScope{Mode string, AgentIDs []string}`.
- Produces: `FilterPayload(scope, table, items)` and `MergeByClientID(local, cloud)`.

- [ ] **Step 1: Write failing closure and LWW tests**

```go
func TestSelectedScopeKeepsOnlyPrivateAgentClosure(t *testing.T) {
    scope := NewSelectedSyncScope([]string{"agent-a"})
    got := FilterSyncItems(scope, "long_term_memories", []map[string]any{
        {"agent_id":"agent-a", "group_id":""}, {"agent_id":"agent-b", "group_id":""},
        {"agent_id":"agent-a", "group_id":"group-1"},
    })
    require.Len(t, got, 1)
}

func TestLWWKeepsNewerUpdatedAt(t *testing.T) {
    winner := NewerSyncItem(itemAt("old", 100), itemAt("new", 200))
    assert.Equal(t, "new", winner["value"])
}
```

- [ ] **Step 2: Verify red**

Run: `cd website/API && go test ./services -run 'Test(SelectedScope|LWW)'`
Expected: FAIL because scope and merge helpers do not exist.

- [ ] **Step 3: Implement exact table closure**

`all` allows all 13 legacy tables. `selected` allows only the six agent tables; agent rows match `client_id`, child rows match `agent_id`, and memory/plan rows additionally require empty `group_id`. Tombstones for child tables are accepted only when their current cloud row resolves to an in-scope agent; agent tombstones match selected agent IDs directly.

- [ ] **Step 4: Implement normalized LWW**

Parse RFC3339 strings and millisecond integers from `sync_updated_at`, `updated_at`, or domain timestamps in that priority. Equal timestamps keep the cloud record to make retries idempotent.

- [ ] **Step 5: Verify green**

Run: `cd website/API && go test ./services -run 'Test(SelectedScope|LWW)'`
Expected: PASS.

### Task 4: Preview Token and V2 Sync Run

**Files:**
- Add: `website/API/models/sync_run.go`
- Create: `website/API/services/sync_preview_service.go`
- Create: `website/API/handlers/sync_v2_handler.go`
- Modify: `website/API/routes/routes.go`
- Test: `website/API/services/sync_preview_service_test.go`
- Test: `website/API/handlers/sync_v2_handler_test.go`

**Interfaces:**
- Consumes: Task 2 policy and Task 3 filtering/LWW.
- Produces: `POST /api/v1/sync/v2/preview` and `POST /api/v1/sync/v2/run`.

- [ ] **Step 1: Write failing token binding tests**

```go
func TestPreviewRejectsChangedPolicyOrDevice(t *testing.T) {
    token := store.Issue(PreviewBinding{UserID: 9, DeviceID: "d1", PolicyVersion: 4})
    require.ErrorIs(t, store.Consume(token, PreviewBinding{UserID: 9, DeviceID: "d2", PolicyVersion: 4}), ErrPreviewChanged)
    require.ErrorIs(t, store.Consume(token, PreviewBinding{UserID: 9, DeviceID: "d1", PolicyVersion: 5}), ErrPreviewChanged)
}
```

- [ ] **Step 2: Verify red**

Run: `cd website/API && go test ./services ./handlers -run 'TestPreview|TestSyncV2'`
Expected: FAIL because preview store and handlers do not exist.

- [ ] **Step 3: Implement bounded preview store**

Use `crypto/rand` 32-byte URL-safe tokens, five-minute expiry, single-use consumption, a mutex-protected map, and a maximum of five active previews per `(user, device)`. Store only counts, hashes, IDs, timestamps, and scope metadata—never chat or memory content.

- [ ] **Step 4: Implement preview/run handlers**

Both handlers require a registered `X-Device-ID`. `preview` validates mode (`immediate` uses current policy, `one_shot` uses request IDs), filters both upload and cloud sides, computes upload/download/overwrite/delete/conflict counts, then issues a token. `run` consumes the token, repeats scope validation, applies LWW and tombstones in a database transaction per complete run, returns merged per-table rows, and updates device `LastSyncAt` only after success.

- [ ] **Step 5: Verify green**

Run: `cd website/API && go test ./services ./handlers -run 'TestPreview|TestSyncV2'`
Expected: PASS.

### Task 5: Flutter Sync Scope and Local Safety

**Files:**
- Create: `lib/models/sync_policy.dart`
- Create: `lib/services/sync_scope.dart`
- Modify: `lib/services/database_service.dart`
- Modify: `lib/services/sync_service.dart`
- Test: `test/sync_scope_test.dart`
- Test: `test/sync_service_scope_test.dart`

**Interfaces:**
- Consumes: V2 JSON contract from Task 4.
- Produces: `SyncScope.accountPolicy(policy)` and `SyncScope.oneShot(agentIds)`.
- Produces: `SyncService.preview(scope)` and `SyncService.run(previewToken)`.

- [ ] **Step 1: Write failing six-table closure tests**

```dart
test('selected scope emits one agent private six-table closure', () async {
  final payload = await fixture.buildPayload(SyncScope.oneShot({'agent-a'}));
  expect(payload.keys, equals(agentClosureTables));
  for (final rows in payload.values) {
    expect(rows.items.every((row) => row['agent_id'] == 'agent-a' || row['client_id'] == 'agent-a'), isTrue);
  }
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/sync_scope_test.dart test/sync_service_scope_test.dart`
Expected: FAIL because `SyncScope` and scoped payload APIs do not exist.

- [ ] **Step 3: Implement scoped reads and tombstones**

`SyncScope` owns table admission and agent predicates. `SyncService` queries selected child rows with `agent_id IN (...)`; memory and plan queries add `group_id IS NULL`; all dynamic placeholders use `whereArgs`. Tombstones are joined back to the current row or agent ID before inclusion. Empty `selected` produces empty agent payload without error.

- [ ] **Step 4: Implement snapshot and atomic response application**

Before `run`, call `PRAGMA wal_checkpoint(FULL)` and create the existing DB backup. Apply every returned table and tombstone in one SQLite transaction, re-checking scope for every row. Clear only the exact acknowledged local tombstone IDs and update last-sync time only after commit; failures retain backup and tombstones.

- [ ] **Step 5: Verify green**

Run: `flutter test test/sync_scope_test.dart test/sync_service_scope_test.dart`
Expected: PASS.

### Task 6: Provider and Sync Management UI

**Files:**
- Modify: `lib/providers/sync_provider.dart`
- Modify: `lib/screens/sync_devices_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/sync_provider_test.dart`
- Test: `test/sync_devices_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 identity and Task 5 sync service.
- Produces: policy editing, immediate sync, one-shot picker, preview confirmation.

- [ ] **Step 1: Write failing provider/UI tests**

```dart
test('one-shot run leaves account policy unchanged', () async {
  final before = notifier.state.policy;
  await notifier.runOneShot({'agent-c'});
  expect(notifier.state.policy, before);
});
```

Widget test pumps `SyncDevicesScreen`, selects “指定智能体”, checks A only, verifies selected count and the “新建智能体默认不同步” hint, then opens one-shot picker and confirms the preview dialog shows upload/download/overwrite/delete counts.

- [ ] **Step 2: Verify red**

Run: `flutter test test/sync_provider_test.dart test/sync_devices_screen_test.dart`
Expected: FAIL because policy actions and controls do not exist.

- [ ] **Step 3: Implement provider state machine**

State includes `policy`, `devices`, `preview`, `isLoading`, `isRunning`, and `error`. Policy saves send `expected_version`; HTTP 409 reloads policy and shows a conflict message. Immediate and one-shot both preview then require explicit confirmation; one-shot never calls policy update.

- [ ] **Step 4: Replace 100% sync UI**

Remove `dart:io`; render scope segmented control, agent checkbox list, realtime switch, immediate and one-shot actions, preview dialog, then device cards with browser/platform/current/last-active/last-sync. Use theme color scheme only.

- [ ] **Step 5: Verify green**

Run: `flutter test test/sync_provider_test.dart test/sync_devices_screen_test.dart`
Expected: PASS.

### Task 7: Scope-Aware WebSocket Realtime Sync

**Files:**
- Modify: `website/API/services/sync_hub.go`
- Modify: `website/API/handlers/sync_ws_handler.go`
- Modify: `lib/services/sync_websocket_service.dart`
- Modify: `lib/providers/sync_provider.dart`
- Test: `website/API/services/sync_hub_test.go`
- Test: `test/sync_websocket_service_test.dart`

**Interfaces:**
- Consumes: `SyncPolicy` and `DeviceIdentity`.
- Produces: source-excluding `sync_notify(table, agent_id, policy_version)`.

- [ ] **Step 1: Write failing broadcast tests**

```go
func TestNotifyDataChangeExcludesSourceAndUnselectedAgent(t *testing.T) {
    hub := newTestHub()
    hub.NotifyDataChange(3, "source", "chat_messages", "agent-b", selectedPolicy("agent-a"))
    assertNoMessage(t, sourceClient)
    assertNoMessage(t, otherClient)
}
```

- [ ] **Step 2: Verify red**

Run: `cd website/API && go test ./services -run 'TestNotifyDataChange'`
Expected: FAIL because scoped notification API does not exist.

- [ ] **Step 3: Implement source and scope filtering**

WebSocket handshake verifies `device_id` belongs to the authenticated user and stores browser-aware display name. `NotifyDataChange` excludes source device; selected policy drops out-of-scope agent events; policy changes still broadcast to all devices. Chat-lock conflict text uses the registered device display name.

- [ ] **Step 4: Trigger scoped pulls on Flutter**

Client includes `device_id` in every connection and ignores its own source ID. `sync_notify` runs a debounced immediate V2 sync only when realtime is enabled and the event agent is allowed; policy events reload policy before deciding.

- [ ] **Step 5: Verify green**

Run: `cd website/API && go test ./services -run 'TestNotifyDataChange'`
Run: `flutter test test/sync_websocket_service_test.dart`
Expected: both PASS.

### Task 8: Client ID Migration and Full Verification

**Files:**
- Modify: `lib/services/database_service.dart`
- Test: `test/database_sync_migration_test.dart`

**Interfaces:**
- Consumes: installation-level device ID.
- Produces: collision-safe `client_id` for legacy numeric rows.

- [ ] **Step 1: Write failing migration test**

```dart
test('numeric legacy client ids receive device namespace', () async {
  await fixture.insertLegacy('chat_messages', id: 12, clientId: '12');
  await fixture.migrate(deviceId: 'device-a');
  expect(await fixture.clientId('chat_messages', 12), 'device-a:chat_messages:12');
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/database_sync_migration_test.dart`
Expected: FAIL because numeric IDs remain un-namespaced.

- [ ] **Step 3: Implement non-destructive migration**

Increment DB version, checkpoint WAL before migration, update only `client_id` values matching `^[0-9]+$` in auto-increment tables to `<deviceId>:<table>:<id>`, and preserve UUID/string IDs. Run in the upgrade transaction; never drop source tables.

- [ ] **Step 4: Run focused and full verification**

Run: `cd website/API && go test ./...`
Run: `flutter test`
Run: `flutter analyze`
Expected: Go and Flutter tests PASS; analyzer reports 0 errors.

- [ ] **Step 5: Review requirements**

Confirm device auto-registration, account-wide policy, all/selected semantics, six-table closure, one-shot policy immutability, preview binding, LWW, source-excluding realtime events, failed-run tombstone retention, and legacy full-sync migration each have a passing test.
