# 私聊表情包与单轮表情回复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Flutter 私聊中增加本机全局表情库与微信式选择面板，并让智能体通过一次复合 `chat` 工具调用返回文字和最多一个表情；同时为管理员预留视觉识图配置、价格和测试接口。

**Architecture:** Flutter 端新增不参与同步的本地 `stickers` 及消息快照表，表情语义统一为 `[表情]实际描述`。私聊请求动态注入表情清单，`chat` 工具返回 `message` 与可选 `sticker_id`，客户端只解析一次响应。Go 端新增独立视觉配置/价格/测试服务和管理员路由，视觉测试不进入用户聊天计费。

**Tech Stack:** Flutter/Dart、Riverpod、sqflite、image_picker、Go/Gin、自定义 JSON 文件数据库、原生 HTML/CSS/JS 后台。

## Global Constraints

- 只支持私聊；群聊不增加表情功能。
- 表情库本机全局共享，不加入 `SyncService.syncTables`，不上传图片。
- 添加表情只能手动选择图片并填写实际描述；Flutter 不出现 AI 识图入口。
- 智能体每轮最多返回一个表情，聊天和表情必须同一次 API 请求完成，不执行补充请求。
- 新 Dart 代码使用 `withValues(alpha:)`，不使用硬编码黑白颜色。
- 新后台 HTML 拼接必须经过 `escHtml()`，不引入用户数据内联 `onclick`。
- 视觉测试只允许管理员，图片允许 `image/jpeg`、`image/png`、`image/webp`，单图最大 10 MiB，上游超时 30 秒。

---

### Task 1: 添加语义与成本纯函数

**Files:**
- Create: `lib/services/sticker_message_codec.dart`
- Test: `test/sticker_message_codec_test.dart`
- Create: `website/API/services/vision_pricing.go`
- Test: `website/API/services/vision_pricing_test.go`

**Interfaces:**
- Produces `StickerMessageCodec.composeContent(String message, String? description)` and `StickerMessageCodec.parseChatArguments(Map<String,dynamic>)`.
- Produces `CalculateVisionCost(int promptTokens, int completionTokens, float64 inputPricePer1M, float64 outputPricePer1M) (float64, error)`.

- [ ] **Step 1: Write failing tests** for text composition, empty descriptions, valid/invalid `sticker_id`, and token cost.
- [ ] **Step 2: Run `flutter test test/sticker_message_codec_test.dart` and `go test ./services -run VisionPricing`**; confirm missing symbols fail.
- [ ] **Step 3: Implement the minimal Dart codec and Go cost calculator**, rejecting negative/non-finite prices.
- [ ] **Step 4: Re-run both targeted tests** and confirm PASS.

### Task 2: 本地数据库与表情仓储

**Files:**
- Modify: `lib/services/database_service.dart:187-205,307-390,395-475,1232-1260`
- Create: `lib/models/sticker.dart`
- Create: `lib/services/sticker_service.dart`
- Test: `test/sticker_service_test.dart`

**Interfaces:**
- `Sticker` model with `id`, `description`, `imagePath`, `createdAt`, `updatedAt`, `deletedAt`.
- `StickerService.listActive()`, `add({required String sourcePath, required String description})`, `updateDescription(String id, String description)`, `delete(String id)`.
- `DatabaseService.insertSticker`, `getStickers`, `updateSticker`, `softDeleteSticker`, `insertStickerMessageSnapshot`, `getStickerMessageSnapshot`.

- [ ] **Step 1: Add failing repository tests** for global listing, trimmed non-empty descriptions, soft deletion, and message snapshots.
- [ ] **Step 2: Run `flutter test test/sticker_service_test.dart`** and confirm schema/API failures.
- [ ] **Step 3: Upgrade SQLite to version 27**, create `stickers` and `local_sticker_messages`, and implement path-copy plus CRUD.
- [ ] **Step 4: Re-run the repository tests** and verify tables are absent from sync payloads.

### Task 3: 单轮复合 chat 工具

**Files:**
- Modify: `lib/services/api_service.dart:512-550`
- Modify: `lib/providers/chat_provider.dart:25-65,280-335,390-470,700-820`
- Test: `test/sticker_chat_tool_test.dart`

**Interfaces:**
- `ApiService.privateChatTool({required List<Sticker> stickers})` returns one `chat` definition with optional `message` and `sticker_id`.
- `ChatNotifier.sendMessage(String content, {Sticker? sticker})` stores `[表情]实际描述` and sends one request.
- `_ToolLoopResult` carries optional `stickerId` and `stickerDescription` alongside `chatMessage`.

- [ ] **Step 1: Write failing tests** asserting dynamic sticker IDs, normalized user context, one API invocation, valid assistant sticker parsing, and invalid-ID text fallback.
- [ ] **Step 2: Run `flutter test test/sticker_chat_tool_test.dart`** and confirm current tool only accepts `message`/loops.
- [ ] **Step 3: Implement dynamic tool schema and one-response parser; remove private-chat follow-up tool loop while preserving group behavior.**
- [ ] **Step 4: Re-run targeted tests**, then run existing chat provider scope tests.

### Task 4: Flutter 面板与聊天渲染

**Files:**
- Modify: `lib/screens/chat_screen.dart:150-220,1880-2030,2110-2220`
- Modify: `lib/providers/chat_provider.dart:25-65,165-190,295-330`
- Create: `lib/widgets/sticker_panel.dart`
- Test: `test/sticker_panel_test.dart`

**Interfaces:**
- `StickerPanel` exposes `onSelected(Sticker)`, `onAddRequested`, `onEditRequested`, `onDeleteRequested`.
- Chat message rendering uses local snapshot/image if available, otherwise `[表情]描述`.

- [ ] **Step 1: Write failing widget tests** for bottom-sheet states, add/manage controls, and fallback text.
- [ ] **Step 2: Run `flutter test test/sticker_panel_test.dart`** and confirm widget is absent.
- [ ] **Step 3: Implement panel, image picker form, edit/delete confirmation, send button integration, and message rendering with theme colors.**
- [ ] **Step 4: Run widget tests and `flutter analyze` on changed Dart files.**

### Task 5: Go 视觉配置、价格和测试接口

**Files:**
- Create: `website/API/models/vision_model_price.go`
- Create: `website/API/services/vision_service.go`
- Create: `website/API/handlers/vision.go`
- Modify: `website/API/routes/routes.go:300-330`
- Test: `website/API/handlers/vision_test.go`

**Interfaces:**
- `GET/PUT /api/v1/admin/vision/config`.
- `GET/PUT /api/v1/admin/vision/prices/:id`.
- `POST /api/v1/admin/vision/test`.
- `VisionService.Test(ctx, image io.Reader, mime, prompt string) (VisionTestResult, error)`.

- [ ] **Step 1: Write failing Go handler tests** for admin authorization, MIME/10 MiB validation, encrypted key masking, price calculation, and missing usage.
- [ ] **Step 2: Run `go test ./handlers -run Vision`** and confirm missing routes/services fail.
- [ ] **Step 3: Implement model, service, handler, route registration, upstream 30-second timeout, and independent pricing.**
- [ ] **Step 4: Run handler/service tests and `go test ./...`.**

### Task 6: 后台视觉配置与测试页面

**Files:**
- Modify: `website/API/admin/index.html:248-350,860-875`
- Modify: `website/API/admin/js/app.js:30-50,930-1010`
- Modify: `website/API/admin/css/admin.css` only if existing responsive styles require it

**Interfaces:**
- Admin section loads `/admin/vision/config` and `/admin/vision/prices`.
- Test form posts `FormData` to `/admin/vision/test` and renders escaped result/usage/cost.

- [ ] **Step 1: Add a small JS test fixture or browser smoke check** for escaped result rendering and disabled-state handling.
- [ ] **Step 2: Verify it fails because the section/actions do not exist.**
- [ ] **Step 3: Add the disabled-by-default UI, configuration fields, price fields, upload test form, and `escHtml()` rendering without inline user-data handlers.**
- [ ] **Step 4: Run existing admin JS checks if available and manually verify admin flow against the Go endpoint.**

### Task 7: 集成验证

**Files:**
- Modify only files required by failing integration checks.

- [ ] **Step 1: Run `flutter test` and `flutter analyze`; fix only regressions caused by this feature.**
- [ ] **Step 2: Run `cd website/API; go test ./...`.**
- [ ] **Step 3: Verify migration, one-request behavior, local-only storage, and admin-only vision testing with the manual acceptance checklist in the design document.**
- [ ] **Step 4: Review `git diff --stat` and ensure no unrelated pre-existing changes were overwritten.**
