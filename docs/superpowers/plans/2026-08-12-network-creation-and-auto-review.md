# 网络创建入口、作品归属与自动审核 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Flutter 客户端加入中央创建入口、网络作品归属与上传流程，并让 Go 服务端自动审核后自动上架或拒绝。

**Architecture:** 在 `Agent` / `GroupChat` 上保存网络来源元数据，SQLite v33 持久化并沿用现有同步负载；用纯逻辑策略统一上传资格和开场白校验。客户端复用 `NetworkUploadScreen` 完成标签补充与上传，服务端继续使用现有网络作品表并以 `UploaderID` 为权限权威，AI 审核写回时增加状态流转与版本保护。

**Tech Stack:** Flutter 3.41+、Dart 3.11、Riverpod 2.x、sqflite、Go 1.25、Gin、自定义 JSON DB。

## Global Constraints

- 永远使用中文回复。
- `flutter analyze` 必须 0 errors；既存 info/warnings 可接受。
- 新 Flutter 代码使用 `withValues(alpha:)`，不用 `withOpacity()`。
- UI 颜色使用 `Theme.of(context).colorScheme`，不用硬编码白/黑。
- 所有本地消息和记忆查询继续按 `agent_id` 隔离。
- `MemoryService.setAgentId()` 必须继续重置 `_groupId = null`。
- 群聊并行回复继续为每个 agent 创建独立 `MemoryService()`。
- 下载副本在官方客户端内完全禁止上传或更新网络作品。
- 智能体和群聊网络上传的开场白都必须非空。
- 编辑已发布网络作品后重置为 `pending` 并重新审核。
- 不回退或覆盖工作区已有无关改动，不提交当前脏工作区。

---

### Task 1: 网络来源模型、上传策略与 SQLite v33

**Files:**
- Create: `lib/services/network_copy_policy.dart`
- Modify: `lib/models/agent.dart`
- Modify: `lib/models/group_chat.dart`
- Modify: `lib/services/database_service.dart`
- Test: `test/network_copy_policy_test.dart`
- Test: `test/network_source_model_test.dart`
- Test: `test/database_network_source_migration_test.dart`

**Interfaces:**
- Produces: `NetworkCopySource.none|owner|downloaded` 字符串常量。
- Produces: `canUploadNetworkCopy(String source)`、`hasRequiredOpeningLine(String?)`。
- Produces: `Agent.networkId/networkUploaderId/networkSource/networkVersion`。
- Produces: `GroupChat.openingLine/networkId/networkUploaderId/networkSource/networkVersion`。

- [ ] **Step 1: 写上传资格和开场白失败测试**

```dart
test('downloaded copies cannot upload', () {
  expect(canUploadNetworkCopy(NetworkCopySource.downloaded), isFalse);
  expect(canUploadNetworkCopy(NetworkCopySource.none), isTrue);
  expect(canUploadNetworkCopy(NetworkCopySource.owner), isTrue);
});

test('opening line rejects null empty and whitespace', () {
  expect(hasRequiredOpeningLine(null), isFalse);
  expect(hasRequiredOpeningLine('  '), isFalse);
  expect(hasRequiredOpeningLine('你好'), isTrue);
});
```

- [ ] **Step 2: 运行策略测试确认 RED**

Run: `flutter test test/network_copy_policy_test.dart`
Expected: FAIL，提示 `network_copy_policy.dart` 或目标符号不存在。

- [ ] **Step 3: 实现最小策略模块**

```dart
abstract final class NetworkCopySource {
  static const none = 'none';
  static const owner = 'owner';
  static const downloaded = 'downloaded';
}

bool canUploadNetworkCopy(String source) =>
    source != NetworkCopySource.downloaded;

bool hasRequiredOpeningLine(String? value) =>
    value != null && value.trim().isNotEmpty;
```

- [ ] **Step 4: 写模型往返与 v33 迁移失败测试**

```dart
test('agent preserves network ownership metadata', () {
  final agent = Agent(
    name: 'A', persona: 'P', networkId: 7,
    networkUploaderId: 3, networkSource: NetworkCopySource.owner,
    networkVersion: 2,
  );
  final restored = Agent.fromMap(agent.toMap());
  expect(restored.networkId, 7);
  expect(restored.networkSource, NetworkCopySource.owner);
});

test('group preserves opening line and downloaded source', () {
  final group = GroupChat(
    name: 'G', openingLine: '欢迎', networkId: 9,
    networkUploaderId: 4, networkSource: NetworkCopySource.downloaded,
    networkVersion: 1,
  );
  final restored = GroupChat.fromMap(group.toMap());
  expect(restored.openingLine, '欢迎');
  expect(restored.networkSource, NetworkCopySource.downloaded);
});
```

- [ ] **Step 5: 运行模型与迁移测试确认 RED**

Run: `flutter test test/network_source_model_test.dart test/database_network_source_migration_test.dart`
Expected: FAIL，提示构造参数或数据库迁移函数/列不存在。

- [ ] **Step 6: 增加模型字段和数据库版本 33**

`agents` / `group_chats` 新增：

```sql
network_id INTEGER,
network_uploader_id INTEGER,
network_source TEXT NOT NULL DEFAULT 'none',
network_version INTEGER
```

`group_chats` 额外新增：

```sql
opening_line TEXT
```

更新构造函数、`copyWith`、`toMap`、`fromMap`、`_onCreate`、`_onUpgrade(oldVersion < 33)` 和 `_ensureGroupTablesExist()`。

- [ ] **Step 7: 运行 Task 1 测试确认 GREEN**

Run: `flutter test test/network_copy_policy_test.dart test/network_source_model_test.dart test/database_network_source_migration_test.dart`
Expected: PASS。

### Task 2: 下载导入写入来源元数据

**Files:**
- Modify: `lib/services/agent_export_service.dart`
- Modify: `lib/services/group_export_service.dart`
- Modify: `lib/providers/agent_provider.dart`
- Modify: `lib/providers/group_provider.dart`
- Test: `test/network_download_source_test.dart`

**Interfaces:**
- Produces: `AgentExportService.deserializeDownloaded` 返回 `networkSource=downloaded` 的新本地副本。
- Produces: `GroupExportService.importDownloadedGroup(...)` 原子导入群聊与成员并返回本地 `GroupChat`。
- Produces: `AgentNotifier.createAgent(...)` 返回创建的 `Agent`。
- Produces: `GroupNotifier.createGroup(...)` 返回创建的 `GroupChat`。

- [ ] **Step 1: 写下载来源失败测试**

```dart
test('downloaded agent records immutable market provenance', () async {
  final agent = await AgentExportService.deserializeDownloaded({
    'version': 4,
    'agent': {
      'id': 12, 'uploader_id': 8, 'name': 'A', 'persona': 'P',
      'opening_line': 'Hi',
    },
  });
  expect(agent.networkId, 12);
  expect(agent.networkUploaderId, 8);
  expect(agent.networkSource, NetworkCopySource.downloaded);
  expect(agent.networkVersion, 4);
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/network_download_source_test.dart`
Expected: FAIL，下载副本没有来源元数据。

- [ ] **Step 3: 实现导入元数据和返回值**

在反序列化时从下载响应读取网络 ID、上传者 ID 和版本，生成新的本地 UUID，并写入 `downloaded`。群聊导入使用现有数据库方法在事务中插入群聊、成员智能体和成员映射；任一步异常回滚。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `flutter test test/network_download_source_test.dart`
Expected: PASS。

### Task 3: Go 上传校验、群聊开场白与来源限制

**Files:**
- Modify: `website/API/models/network_group.go`
- Modify: `website/API/handlers/network_agent.go`
- Modify: `website/API/handlers/network_group.go`
- Test: `website/API/handlers/network_upload_validation_test.go`

**Interfaces:**
- Consumes: 请求字段 `source_kind`，值为 `none|owner|downloaded`。
- Produces: `NetworkGroup.OpeningLine` 加密存储和解密响应。
- Produces: 空白开场白返回 BadRequest；`source_kind=downloaded` 返回 Forbidden。

- [ ] **Step 1: 写服务端失败测试**

```go
func TestNetworkAgentUploadRejectsBlankOpeningLine(t *testing.T) {
    setupAiReviewTestDB(t)
    router := gin.New()
    router.POST("/agents", func(c *gin.Context) {
        c.Set("user_id", uint(1))
        (&NetworkAgentHandler{}).Upload(c)
    })
    recorder := doJSON(router, http.MethodPost, "/agents",
        `{"name":"A","persona":"P","opening_line":"  ","source_kind":"none"}`)
    var resp utils.Response
    _ = json.Unmarshal(recorder.Body.Bytes(), &resp)
    if resp.Code != utils.CodeBadRequest { t.Fatalf("got %d", resp.Code) }
}

func TestNetworkGroupUploadRejectsBlankOpeningLine(t *testing.T) {
    setupAiReviewTestDB(t)
    router := gin.New()
    router.POST("/groups", func(c *gin.Context) {
        c.Set("user_id", uint(1))
        (&NetworkGroupHandler{}).UploadGroup(c)
    })
    recorder := doJSON(router, http.MethodPost, "/groups",
        `{"name":"G","group_persona":"P","opening_line":"","source_kind":"none"}`)
    var resp utils.Response
    _ = json.Unmarshal(recorder.Body.Bytes(), &resp)
    if resp.Code != utils.CodeBadRequest { t.Fatalf("got %d", resp.Code) }
}

func TestNetworkUploadRejectsDownloadedSource(t *testing.T) {
    setupAiReviewTestDB(t)
    router := gin.New()
    router.POST("/agents", func(c *gin.Context) {
        c.Set("user_id", uint(1))
        (&NetworkAgentHandler{}).Upload(c)
    })
    recorder := doJSON(router, http.MethodPost, "/agents",
        `{"name":"A","persona":"P","opening_line":"Hi","source_kind":"downloaded"}`)
    var resp utils.Response
    _ = json.Unmarshal(recorder.Body.Bytes(), &resp)
    if resp.Code != utils.CodeForbidden { t.Fatalf("got %d", resp.Code) }
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd website/API; go test ./handlers -run 'TestNetwork(Agent|Group)Upload|TestNetworkUploadRejectsDownloadedSource'`
Expected: FAIL，当前端点接受空开场白/下载来源。

- [ ] **Step 3: 实现最小服务端校验**

新建和编辑请求均执行：

```go
if strings.TrimSpace(req.OpeningLine) == "" {
    utils.BadRequest(c, "开场白是必须书写的")
    return
}
if req.SourceKind == "downloaded" {
    utils.Forbidden(c, "下载的作品不能上传")
    return
}
```

群聊的 `OpeningLine` 使用 `encryptField` 存储、`decryptField` 输出。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `cd website/API; go test ./handlers -run 'TestNetwork(Agent|Group)Upload|TestNetworkUploadRejectsDownloadedSource'`
Expected: PASS。

### Task 4: AI 审核自动状态流转与版本保护

**Files:**
- Modify: `website/API/handlers/network_ai_review.go`
- Modify: `website/API/handlers/network_ai_review_test.go`

**Interfaces:**
- Produces: `aiReviewUpdates(verdict, err, now)` 同步更新 AI 字段和市场 `Status`。
- Produces: 自动任务按 `ID + Version + Status=pending` 条件写回。

- [ ] **Step 1: 扩展审核状态失败测试**

```go
func TestAutoReviewPassPublishesCurrentVersion(t *testing.T) {
    updates := aiReviewUpdates(services.AiReviewVerdict{Pass: true, Reason: "正常"}, nil)
    if updates["Status"] != "approved" { t.Fatalf("got %v", updates["Status"]) }
}

func TestAutoReviewRejectMarksRejectedAndReason(t *testing.T) {
    updates := aiReviewUpdates(services.AiReviewVerdict{Pass: false, Reason: "违规"}, nil)
    if updates["Status"] != "rejected" || updates["RejectReason"] != "违规" {
        t.Fatalf("got %+v", updates)
    }
}

func TestAutoReviewErrorKeepsPending(t *testing.T) {
    updates := aiReviewUpdates(services.AiReviewVerdict{}, errors.New("timeout"))
    if _, changesStatus := updates["Status"]; changesStatus {
        t.Fatalf("error must keep pending: %+v", updates)
    }
}

func TestStaleAutoReviewCannotOverwriteNewVersion(t *testing.T) {
    setupAiReviewTestDB(t)
    tbl := database.Get().Register("NetworkAgent")
    agent := models.NetworkAgent{Name: "A", Status: "pending", Version: 2}
    _ = tbl.Insert(&agent)
    applyAiReviewAgentResult(agent.ID, 1,
        services.AiReviewVerdict{Pass: true, Reason: "旧结果"}, nil)
    var after models.NetworkAgent
    tbl.FindByID(agent.ID, &after)
    if after.Status != "pending" { t.Fatalf("stale result changed status to %q", after.Status) }
}
```

- [ ] **Step 2: 运行审核测试确认 RED**

Run: `cd website/API; go test ./handlers -run 'Test(AutoReview|StaleAutoReview|AiReviewAgentManual|AiReviewGroupManual)'`
Expected: FAIL，当前只写 AI 字段，不改变市场状态且无版本保护。

- [ ] **Step 3: 实现状态映射和条件写回**

通过时写 `approved`，拒绝时写 `rejected` 和 `RejectReason`，异常保留 `pending`；写回过滤器同时包含 ID、触发时版本和 pending 状态。手动 AI 审核复用同一映射，但管理员仍可后续覆盖。

- [ ] **Step 4: 运行审核测试确认 GREEN**

Run: `cd website/API; go test ./handlers -run 'Test(AutoReview|StaleAutoReview|AiReviewAgentManual|AiReviewGroupManual)'`
Expected: PASS。

### Task 5: 网络上传页绑定本地作品并回写归属

**Files:**
- Modify: `lib/screens/network_upload_screen.dart`
- Modify: `lib/services/network_service.dart`
- Create: `lib/services/network_upload_payload.dart`
- Test: `test/network_upload_payload_test.dart`

**Interfaces:**
- Produces: `NetworkUploadScreen(localAgent/localGroup, existingData)`。
- Produces: `buildAgentNetworkPayload(Agent, tags)`、`buildGroupNetworkPayload(GroupChat, members, tags)`。
- Produces: 上传成功响应返回网络 ID、上传者 ID、版本并回写本地对象为 `owner`。

- [ ] **Step 1: 写 payload 和资格失败测试**

```dart
test('agent payload carries original source and opening line', () async {
  final payload = await buildAgentNetworkPayload(agent, const ['治愈']);
  expect(payload['opening_line'], '你好');
  expect(payload['source_kind'], 'none');
});

test('downloaded copy payload throws before HTTP', () async {
  expect(() => buildAgentNetworkPayload(downloaded, const []), throwsStateError);
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/network_upload_payload_test.dart`
Expected: FAIL，payload 模块不存在。

- [ ] **Step 3: 实现 payload、上传响应和本地归属回写**

群聊 payload 包含 `opening_line`；首次上传发送 `source_kind=none`，作者更新调用 PUT。成功后更新本地模型为 `networkSource=owner`，并保存网络 ID、上传者 ID和版本。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `flutter test test/network_upload_payload_test.dart`
Expected: PASS。

### Task 6: 创建/编辑页面上传按钮与同步询问

**Files:**
- Modify: `lib/screens/agent_create_screen.dart`
- Modify: `lib/screens/group_create_screen.dart`
- Modify: `lib/screens/group_manage_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/network_edit_sync_policy_test.dart`

**Interfaces:**
- Produces: `shouldOfferNetworkSync(source, networkId)` 纯逻辑。
- Consumes: `NetworkUploadScreen(localAgent/localGroup, existingData)`。

- [ ] **Step 1: 写同步询问策略失败测试**

```dart
test('only owned bound works offer network sync', () {
  expect(shouldOfferNetworkSync(NetworkCopySource.owner, 7), isTrue);
  expect(shouldOfferNetworkSync(NetworkCopySource.none, null), isFalse);
  expect(shouldOfferNetworkSync(NetworkCopySource.downloaded, 7), isFalse);
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/network_edit_sync_policy_test.dart`
Expected: FAIL，策略函数不存在。

- [ ] **Step 3: 实现按钮、开场白输入和编辑后询问**

创建/保存主按钮下方加入上传按钮；下载副本显示禁用说明。原作者保存后弹出“仅保存本地 / 同步修改”；同步分支打开带当前本地对象和原网络 ID 的标签确认页。补齐中英文 l10n 文案。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `flutter test test/network_edit_sync_policy_test.dart`
Expected: PASS。

### Task 7: 发现点击下载跳转与底部中央创建按钮

**Files:**
- Modify: `lib/screens/network_content_tab.dart`
- Modify: `lib/screens/network_group_detail_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Test: `test/home_create_action_test.dart`
- Test: `test/network_navigation_policy_test.dart`

**Interfaces:**
- Produces: 中央创建按钮不改变 `_currentIndex`。
- Produces: `NetworkContentTab` 智能体和群聊点击均完成下载后导航。

- [ ] **Step 1: 写导航策略和按钮 Widget 失败测试**

```dart
testWidgets('center create action exposes agent and group choices', (tester) async {
  await tester.pumpWidget(testHome());
  await tester.tap(find.byKey(const Key('home-create-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('create-agent-action')), findsOneWidget);
  expect(find.byKey(const Key('create-group-action')), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/home_create_action_test.dart test/network_navigation_policy_test.dart`
Expected: FAIL，中央按钮和统一下载导航不存在。

- [ ] **Step 3: 实现中央按钮和下载导航**

移动端自定义底栏布局为两个 Tab、中央圆形加号、两个 Tab；弹出悬浮菜单并进入对应创建页。发现页群聊卡片直接下载，成功后进入 `GroupChatScreen`；智能体成功后进入 `ChatScreen`。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `flutter test test/home_create_action_test.dart test/network_navigation_policy_test.dart test/home_page_mapping_test.dart`
Expected: PASS。

### Task 8: 状态展示、格式化与完整回归

**Files:**
- Modify: `lib/screens/my_network_agents_screen.dart`
- Modify: `website/API/models/network_agent.go`
- Modify: `website/API/models/network_group.go`
- Modify: 本计划涉及且被格式化器调整的文件

**Interfaces:**
- Produces: “我上传的”展示审核中、已上架、已拒绝原因、审核异常、已下架。

- [ ] **Step 1: 更新既有状态展示测试或添加最小状态映射测试**

```dart
test('rejected upload exposes reject reason', () {
  final view = networkUploadStatusView({'status': 'rejected', 'reject_reason': '违规'});
  expect(view.reason, '违规');
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/network_upload_status_test.dart`
Expected: FAIL，状态映射不存在或未返回原因。

- [ ] **Step 3: 实现状态映射并格式化**

Run: `dart format lib test`

Run: `cd website/API; gofmt -w models/network_agent.go models/network_group.go handlers/network_agent.go handlers/network_group.go handlers/network_ai_review.go handlers/network_ai_review_test.go handlers/network_upload_validation_test.go`

- [ ] **Step 4: 运行相关快速回归**

Run: `flutter test test/network_copy_policy_test.dart test/network_source_model_test.dart test/network_download_source_test.dart test/network_upload_payload_test.dart test/network_edit_sync_policy_test.dart test/home_create_action_test.dart test/home_page_mapping_test.dart`
Expected: PASS。

Run: `cd website/API; go test ./handlers ./services`
Expected: PASS。

- [ ] **Step 5: 运行完整验证**

Run: `flutter analyze`
Expected: 0 errors。

Run: `flutter test`
Expected: 全部测试 PASS。

Run: `cd website/API; go test ./...`
Expected: 全部测试 PASS。

Run: `cd website/API; go build -o aichat-api.exe .`
Expected: exit 0。
