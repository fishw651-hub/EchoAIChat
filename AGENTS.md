# AGENTS.md — 回响 (Flutter AI Chat + Go API Server)

> 版本：v5.3.5 (version_code 66) · 最后更新：2026-08-15

## Quick reference

```bash
# Flutter 客户端
flutter analyze                     # 0 errors required
flutter test                        # widget/单元测试（test/ 下 84 个测试文件）
flutter run                         # 连接的设备/模拟器启动
flutter clean && flutter pub get && flutter run   # 清理重建

# Go API 服务器 (website/API/)
cd website/API
go run main.go                      # 启动服务器（端口来自 config.yaml）
go build -o aichat-api.exe .        # 编译
go test ./...                       # 全部测试（约 45 个 Go 测试文件）

# 生产部署
# 1. 编译：go build -o aichat-api.exe .
# 2. 停止旧服务
# 3. 替换 aichat-api.exe
# 4. 启动新服务
# 5. 浏览器硬刷新（Ctrl+F5）后台管理页
```

## 跨盘符 Kotlin 编译问题（关键）

Pub 缓存在 `C:` 但项目在 `D:`，Kotlin 增量编译跨盘符会失败。

`android/gradle.properties` 已禁用增量编译：
```properties
kotlin.incremental=false
kotlin.incremental.useClasspathSnapshot=false
kotlin.compiler.execution.strategy=in-process
```
**永远不要重新启用**，除非 pub 缓存和项目位于同一盘符。

另：`pubspec.yaml` 配置了 `hooks.user_defines.sqlite3.source: system` —— sqlite3 包默认从 GitHub 下载预编译库，中国网络会超时；移动端用原生 sqflite 不受影响，Web 端走 WASM SQLite（`web/sqlite3.wasm`）。

## 项目架构

**两部分项目**：

| 部分 | 位置 | 语言 | 框架 | 数据库 |
|---|---|---|---|---|
| 客户端 (Flutter) | `lib/` | Dart (SDK ^3.11.1) | Flutter / Riverpod 2.x | SQLite (sqflite, WAL 模式)；Web 端 WASM SQLite |
| 服务器 (API 中继) | `website/API/` | Go 1.25 | Gin 1.12 | SQLite（modernc.org/sqlite，records 表 + JSON payload） |
| 后台管理 (Web) | `website/API/admin/` | HTML/JS/CSS | 原生 | 通过 Go API |
| 落地页 | `website/API/landing/` | HTML | Tailwind CDN | 静态 |

**数据流**：Flutter 客户端 → Go API 服务器（中继/代理）→ DeepSeek API。客户端从不直接调用 DeepSeek。

**跨平台抽象**：客户端通过条件导入（`platform_*.dart` 的 `_io`/`_web`/`_stub` 变体）支持 Android/iOS/Windows/Linux/macOS/Web。`database_service_web.dart` / `database_service_noop.dart` 处理 Web 端数据库差异（Web 不支持 WAL checkpoint、文件备份）。Web 端另有 `platform_secure_storage_web.dart`（SubtleCrypto AES-GCM）、`platform_device_id_web.dart`（localStorage UUID）等专用实现。

## Flutter 客户端

### 目录结构

```
lib/
├── main.dart                    # 入口，路由 _AppShell，全局回调注册
├── agreements/                  # 三份协议（用户/隐私/网络使用）
├── config/                      # server_config.dart（gitignored）
├── l10n/                        # 国际化 app_localizations.dart（en/zh）
├── models/                      # 16 个数据模型（agent, memory, group, sticker, chat_message, sync_policy...）
├── providers/                   # 13 个 Riverpod providers
├── repositories/                # 仓储层（agent/chat/memory）
├── screens/                     # 27 个页面
├── services/                    # 78 个服务文件
├── theme/                       # Material 3 主题 app_theme.dart
├── utils/                       # 响应式布局、头像裁剪、range_select 等
└── widgets/                     # 37 个通用组件（含 sub_tab_switcher 胶囊分段控件（智能体/群聊子页切换）、agent_group_tab 合并 tab 容器；chat_screen 抽离的 animated_chat_bubble / voice_input_bar / pending_images_bar / chat_desktop_sidebar / chat_image_viewer / agent_share_dialog / novel_polish_dialog / update_dialog / bouncing_dots_indicator）
```

### 入口路由（`lib/main.dart:_AppShell`）

按优先级依次判定：
1. `accountGuardProvider` 封禁 → `AccountBanScreen`
2. `UpdateService.availableUpdate.isForce` → `ForceUpdateScreen`（强制更新）
3. `isFirstRun == true` → `OnboardingScreen`
4. 否则 → `HomeScreen`（主页，4 tab：首页 / 智能体·群聊（合并，标签跟随当前子页显示"智能体"/"群聊"）/ 发现 / 账户；合并 tab 与发现 tab 显示子页分段控件（`widgets/sub_tab_switcher.dart` 胶囊双选项：智能体 | 群聊）——移动端浮于底部悬浮导航栏上方（AnimatedSlide+Fade 进出），桌面端位于内容区顶部；两个 tab 的子页状态在 `providers/home_tab_provider.dart`，底部悬浮圆角导航栏，桌面端为侧边栏同构）

主题：Ocean 浅蓝为唯一种子色，浅色/深色模式切换带渐变过渡。注意不要用 `ValueKey` 包含 themeMode，否则 MaterialApp 树重建导致 PageController 重置。

### 状态管理

**Riverpod 2.x**（`StateNotifierProvider`），providers 是全局单例位于 `lib/providers/`：

| Provider | 文件 | 职责 |
|---|---|---|
| `settingsProvider` | `settings_provider.dart` | API 配置、主题、思考模式、温度、token 追踪 |
| `agentProvider` | `agent_provider.dart` | 智能体 CRUD、活跃智能体追踪 — SQLite 持久化 |
| `chatProvider` | `chat_provider.dart` | 私聊：发消息、工具循环、记忆管理、画像 AI 触发；续输出——生成绑定发起时 agentId，切走流仍跑完并按发起智能体落库（`_inflightAgentIds` 恢复 isLoading/拦截同智能体并发，`saveRevision` 通知会话列表刷新） |
| `groupProvider` | `group_provider.dart` | 群聊：创建/管理、并行回复（`Future.wait`）、模拟器模式 |
| `memoryProvider` / `baseProvider` | `memory_provider.dart` | 持久化记忆列表、智能体切换监听 |
| `authProvider` | `auth_provider.dart` | 用户登录/鉴权状态 |
| `syncProvider` | `sync_provider.dart` | 多端同步协调 |
| `userProfileProvider` | `user_profile_provider.dart` | 用户画像数据 |
| `planProvider` | `plan_provider.dart` | 计划消息管理 |
| `accountGuardProvider` | `account_guard_provider.dart` | 设备封禁状态（见"设备封禁"） |
| `agentFolderProvider` | `agent_folder_provider.dart` | 智能体编组状态 |
| `homeTabProvider` | `home_tab_provider.dart` | 主页合并 tab / 发现 tab 的子页切换状态 |

### 数据层（客户端）

- **数据库**：sqflite，账号独立数据库，WAL 模式，**version 38**（`database_service.dart` + 同库 part 文件；v36 起三张记忆表 id 全局唯一化为 `L-/B-/GS-` 前缀 UUID；v38 新增旧共享 `aichat.db` 迁移状态表）
- **20+ 张表**：agents、long_term_memories、base_memories、short_term_messages、chat_messages、group_chats、group_members、group_messages、group_shared_memories、group_short_term、providers、token_usage、token_cost、user_profiles、stickers、local_sticker_messages、novel_generations、draft_uploads、debug_logs、local_tombstones、agent_folders、agent_folder_members 等
- **关键规则**：所有记忆/消息查询必须按 `agent_id` 过滤 — 禁止跨智能体数据泄漏。null `agentId` 返回 `[]` 或带警告跳过
- `_ensureGroupTablesExist()` 每次 DB 打开都执行，通过 try/catch `ALTER TABLE` 健壮地添加缺失列
- **备份前必须 WAL 刷盘**：`PRAGMA wal_checkpoint(FULL)`，且必须用 `rawQuery`（execSQL 在 Android 上对返回结果行的语句抛错）；Web 端不支持，直接抛 `UnsupportedError`
- **API keys**：XOR + SHA-256 加密存储在 `providers` 表。加密实现已改为条件导入委托（`encryption_service.dart` → `platform_encryption_io/web.dart`）
- **配置**：`lib/config/server_config.dart` gitignored（真实服务器配置）。模板：`server_config.dart.example`

### API 层（`api_service.dart`）

- DeepSeek-only HTTP 客户端，目标 `v1/chat/completions`，**通过 Go 服务器中继**
- **工具选择**：首次调用 `'required'`，后续 `'auto'`。最多 5 轮
- **思考模式**：添加 `thinking: {type: 'enabled'}` + `reasoning_effort: 'high'`，移除 temperature
- **错误重试**：400 错误剥离不支持参数（tool_choice, thinking）后重试
- **工具集**（`getToolDefinitions(isGroupChat:)`，已与规范一致）：
  - 私聊：`[chat, plan]` — chat 工具由 `StickerMessageCodec.buildChatTool(stickers:)` 动态构建，可携带表情包列表
  - 群聊：`[remember, forget, chatgroup, plan, manage_character]`
- 还包含 Vision API 调用（图片识别，错误前缀 `Vision API error`）
- API keys 永不记录 — `_maskedKey` 仅显示首尾 4 字符

### 三层记忆系统

| 层 | 表 | 容量 | 管理 |
|---|---|---|---|
| 短期 | `short_term_messages` | 20 轮（可配置） | 滑动窗口；`image_path`/`image_paths` 列存图片消息的本地路径 |
| 长期 | `long_term_memories` | ≤15 条，9 字段 | 记忆 AI 自动创建/更新/删除 |
| 基础 | `base_memories` | 无上限 | `setting` 类型永久，`event` 类型可变 |

**短期记忆携带图片**：图片消息写短期记忆时同时存 `image_path`（本地路径）。**多图消息**（v32）：`image_paths` 列存 JSON 数组字符串（`chat_messages`/`short_term_messages` 两表同加，编解码见 `image_paths_codec.dart`）；`image_path` 列保留并写入首图兼容，读取优先 `image_paths`、空则回退 `image_path`。构建聊天上下文时，所选模型 `nativeVision==true` → 窗口内带图消息 content 变数组型（text + image_url，一条多图消息可挂多张，base64 按路径现读，文件缺失降级 `[图片]` 文本），上限按张数跨消息累计、取最近 3 张（`VisionMessageBuilder.maxAttachedImages`，聊天与记忆 AI 共用 `attachImagesToMessages`，纯 Dart 可测，`VisionImageReader` 注入文件读取）；非原生视觉模型行为不变（描述文本已在短期记忆里，多图逐张 describe 后合并为 `[用户发送了N张图片，图片内容：1. … 2. …]`，任一张失败整体失败退配额）；上下文溢出的压缩重试不挂图（仅剥离图片键，防止泄漏进 API 请求）。

**图片暂存区（私聊发图）**：选图后不立即发送——压缩落盘 `chat_images/` 后加入输入栏上方的暂存区（`_pendingImages`，缩略图横排 + 右上角 × 删除并清理临时文件，上限 `maxAttachedImages`=3 张超出 SnackBar 提示），可继续打字/增删；点发送图文作为一条消息经 `sendMessage(text, imagePaths:)` 发出（气泡多图为横向小图排，点击 PageView 大图查看）。canSend = 有文字或暂存图非空且非 isLoading（`chat_send_policy.dart` 纯逻辑）；`sendMessage` 返回 bool，发送失败（退配额等）恢复暂存区；AI 回复中禁止添加；离开聊天页/切换智能体清空暂存（临时文件可留）。

**记忆 AI**：默认运行 `deepseek-v4-flash`（跟随设置页所选模型），与聊天 AI 并行。分析最近 2 轮，直接写 JSON 记忆操作到 DB。所选模型 `nativeVision==true` 时，未处理短期消息中带 `image_path` 的会把真实图片（最多 `VisionMessageBuilder.maxAttachedImages`=3 张，按时间序）附到请求 user 消息，可提炼图片相关记忆；非视觉模型保持 `[图片]` 文本占位（绑定视觉模型的描述文本本就在短期记忆里）。

**用户画像 AI**：当 agent `realInfoEnabled == true` 时，每 10 轮对话触发一次画像 AI 分析，提取对方画像。群聊不触发画像 AI。

### 群聊

- **两阶段流程**：导演 AI（`_decideSpeakers`，1 次 API 调用）选择有序发言者列表 → 所有选定智能体并行回复 → 结果渐进显示（`Stream.fromFutures`）
- 智能体共享相同基础上下文（智能体间无累积上下文）
- **并行记忆隔离**：每个并行 agent 创建独立 `MemoryService()` 实例（`group_provider.dart` `_groupMemoryAi` / `_runGroupToolLoop`），禁止共享全局 `memoryServiceProvider` 后 `setAgentId()` — 会互相覆盖导致记忆写入错误 agent
- **智能体编组**（`agent_folders` / `agent_folder_members` 表，本地数据不参与同步）：一个智能体最多属于一个编组（加入新编组先删旧映射）；解散编组只删编组不删智能体。UI 在 `contact_list.dart`（长按进多选 → 底栏"加入编组"，列表按编组分节，编组 ⋯ 菜单支持创建群聊/重命名/解散）
- **编组一键建群 + 记忆共用（`group_chats.linked_memory`）**：编组 ⋯ → 创建群聊时 `linkedMemory=true`。linked 群中：① 每个 speaker 的 MemoryService 不再 `setGroupId`，记忆 AI 产出与 remember 的 personal 记忆直接写私聊长期/基础表；② 每条群消息镜像写入每个在场成员的私聊 `short_term_messages`（前缀 `[群聊·发言人] `，用户为 `[群聊·我] `），私聊记忆 AI 据此把群聊经历提炼进私聊长期记忆；③ 上下文构建经 `GroupService.getAgentGroupLongTermMemories/getAgentGroupBaseMemories` 的 linked 分支走私聊口径。既有非 linked 群行为完全不变
- **模拟器模式**：强制思考模式。自动创建旁白（主持人，第三人称叙述）通过 `manage_character` 生成 NPC。用户是主角。NPC 第一人称说话，`()` 内为动作
- **旁白字数限制**：每次 `chatgroup` 输出 ≤150 字符，单次（不拆分多轮）
- 群聊不触发画像 AI、不注入真实信息、不消耗真实回复配额

### 其他主要功能模块（客户端）

- **表情包**：`sticker_service.dart` + `sticker_message_codec.dart`，`stickers`/`local_sticker_messages` 表；描述 ≤30 字符；私聊 chat 工具动态注入表情列表
- **小说生成**：`novel_service.dart` + `novel_history_screen.dart`，`novel_generations` 表；内置 6 种风格；失败必须抛异常（不得静默返回空串，否则 UI 空白秒出）
- **OCR**：`ocr_service.dart`（google_mlkit_text_recognition）
- **语音输入**：`voice_input_service.dart`（纯逻辑 + 条件导出）→ `voice_input_service_io.dart`（sherpa_onnx + record 端侧识别，不经服务器也不依赖系统 SpeechRecognizer，中文 ROM 可用）/ `voice_input_service_stub.dart`（Web 恒不可用）。模型 sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23（int8 encoder/joiner + fp32 decoder + tokens.txt，约 30MB）打包在 `assets/voice_model/`，首次 initialize 拷贝到应用文档目录后构建 `OnlineRecognizer`（`modelType: 'zipformer'`、16kHz/80 维 feat、`enableEndpoint: false` 按住说话不切端点）；record 采集 16kHz 单声道 PCM16 流，每 250ms 喂流 decode 回调部分结果（全量文本），stop 喂尾巴 + `inputFinished` flush 后回调最终结果。聊天页输入栏左侧文字/语音切换；语音栏按住说话（实时上屏 + PCM 振幅音量指示条 + 启动中/聆听状态文本），松开后识别文本按模式包装**整体覆盖**填入普通输入框可编辑再发送，空结果 SnackBar 提示；模式切换 = 按住说话期间手指在语音栏左右半侧滑动（`onLongPressMoveUpdate` 取 `localPosition.dx` 与栏宽中线实时判定，左半 语言/右半（动作），同一长按内可来回切换，每次新长按重置为 语言），分段胶囊为纯指示器实时高亮（无点按）；识别失败按 errorMsg 映射具体原因（`voiceErrorKindFor`/`voiceErrorL10nKey`：模型缺失/权限被拒/忙等 l10n 文案）；纯逻辑（`wrapVoiceRecognizedText`/`toggleVoiceSendMode`/`voiceModeForPosition`/`isVoiceInputSupported`/`voiceErrorKindFor`/`pcm16BytesToFloat32`/`pcm16SoundLevel`）可测；Web/Linux 隐藏入口
- **计划消息**：`plan_service.dart`；`onPlanTriggered` 回调**只由 main.dart 全局注册**（调用 `deliverPlannedMessage` 让 AI 主动发言），chat_screen 不得覆盖，否则计划消息退化为系统消息
- **AI 提示词代写**：`ai_prompt_writer_service.dart` + `ai_prompt_writer_dialog.dart`
- **智能体分享**：`agent_share_service.dart` + `agent_export_service.dart` / `group_export_service.dart`；服务器端 `share_service.go` + `share_handler.go` 提供 `POST /user/share/agent`（创建分享码）与 `POST /user/share/redeem`（兑换导入）
- **公告**：`announcement_service.dart` + `widgets/announcement_dialog.dart`；服务器端 `announcement_service.go` + `handlers/announcement.go`，客户端拉取 `GET /announcements/active`
- **草稿箱**：`draft_box_screen.dart`，`draft_uploads` 表
- **设备封禁**：`account_guard_service.dart` — 服务器 `device_ban_service.go` 执行：14 天窗口内同设备登录 ≥3 个不同账号 → 封禁，第 N 次 = 2^(N-1) 天封顶 365；有激活订阅的账号豁免；客户端 fail-open（网络失败放行）
- **订阅中心**：`subscription_center_screen.dart`
- **画像初始化向导**：`profile_init_wizard_screen.dart`
- **AI 主动关心**：`proactive_care_service.dart`（窗口 8:00–20:00 默认、按画像 habits 作息微调；条件=窗口内 ∧ 距上次聊天 ≥ minIntervalHours ∧ 今日已发 < dailyLimit ∧ 上一条主动关心已回复；每条消耗 1 次真实回复配额 + token，配额不足静默跳过）+ `proactive_care_alarm.dart`（android_alarm_manager_plus：窗口期每 30 分钟周期 alarm + 窗口开始精确 alarm，后台 isolate 失败静默降级留给前台补发）。配置字段在 Agent：`proactiveCareEnabled` / `proactiveCareDailyLimit`（1–5）/ `proactiveCareMinIntervalHours`（1–12），仅 realInfoEnabled 时可配。通知 payload `proactive:<agentId>`，点击跳转该智能体聊天页

### UI 约定

- **主题**：Material 3（`ColorScheme.fromSeed`）。`AppTheme.light(seed)` / `AppTheme.dark(seed)`
- **`withOpacity` 已弃用**（Flutter 3.41+）。新代码用 `withValues(alpha: ...)`
- **国际化**：`AppLocalizations.of(context).get('key')`。两种语言：`en`、`zh`。语言模式通过 `LocaleService` 存在 SharedPreferences
- **颜色**：禁止硬编码 `Colors.white`/`Colors.black`，必须用 `Theme.of(context).colorScheme`

## Go API 服务器（`website/API/`）

### 架构

- **框架**：Gin，约 170 条路由注册组织为 auth/public/user/admin/sync 组（`routes/routes.go`）
- **数据库**：SQLite（modernc.org/sqlite），单 `records` 表存 JSON payload + 实体镜像列（user_id/client_id/order_no/status/updated_at，含索引），旧 `data/*.json` 启动时一次性导入。Filter 接口（`FilterEq`/`FilterAnd`...）等值条件下推 SQL（实体列走索引，其余走 `json_extract`），Like/Gte 等不可下推形态自动回退内存过滤；裸闭包用 `database.FilterFunc` 适配。per-key 锁用分片锁 `utils.StripedLock`（内存有界）。后台任务：`StartQuotaResetJob`（配额日重置+过期预留清理，5min）与 `StartRetentionJob`（审计日志/历史预留 90 天、设备登录记录 30 天，每日）已在 main.go 启动。
- **入口**：`main.go` — Gin 引擎设置；源站可按 `tls` 配置直接监听 HTTPS，支持手工证书或 Let's Encrypt ACME 自动签发（HTTP-01 / TLS-ALPN-01）。使用 Cloudflare 时采用 Full (strict)
- **配置**：`config.yaml` — 端口、JWT 密钥、加密密钥、限流、CORS、域名白名单、支付（xiaoshiguang）
- **`jobs/` 目录目前为空**（预留）

### 目录结构

```
website/API/
├── main.go                      # 入口
├── config.yaml                  # 配置（敏感）
├── config/config.go             # 配置加载 + 密钥管理
├── handlers/                    # handler 文件（含 sync_v2_handler、sync_ws_handler、share_handler、announcement、network_ai_review、sync_policy）
├── hub/                         # 事件中枢 sync_hub.go（SyncHub 单例 + app_event/聊天锁广播；services 经 EventPublisher 窄接口注入，不直依赖）
├── services/                    # 31 个 service 文件
├── middleware/                  # 9 个中间件（含 background_pressure、maintenance）
├── models/                      # 25 个模型
├── routes/routes.go             # 路由注册
├── database/database.go         # JSON 文件 DB
├── utils/                       # jwt, response, validator, idlock, today
├── admin/                       # 后台管理前端（生产用）
├── frontend/admin/              # 旧版后台（已弃用，勿修改）
├── landing/                     # 落地页
├── jobs/                        # （空，预留）
├── data/                        # JSON DB 数据文件
├── uploads/                     # 用户上传文件
└── deploy/                      # 邮件服务器部署配置
```

### 核心层

| 层 | 位置 | 关键文件 |
|---|---|---|
| 路由 | `routes/routes.go` | ~170 端点 |
| Handlers | `handlers/` | auth, user, user_agent, chat, payment, admin, config, plan, network_agent, network_group, network_admin, network_ai_review, sync_handler, sync_v2, sync_ws, share, announcement, ifdian, activity, feedback, email, device, update, quota, daily_allowance |
| 中间件 | `middleware/` | JWT auth, admin role, CORS, rate limit (60 RPS/IP), login rate limit, logger, body limit, domain binding, sync subscription, **background_pressure**（后台压力自适应限流）, **maintenance**（站点维护模式，仅拦截 landing/admin 入口 HTML 页，admin 支持 `?maint_key=` + cookie 旁路；页面内嵌于 `maintenance.html`，由 main.go `go:embed` 注入） |
| Services | `services/` | deepseek, billing, billing_reservation, payment, auth, crypto, file, quota, email, ifdian, sync_merge, sync_preview, sync_policy, sync_scope, daily_allowance, **event_publisher**（EventPublisher 窄接口 + SetEventPublisher 注入点，Publish* 系列经它转发到 hub）, **adaptive_limiter**（并发自适应限制）, **audit_service**（审计日志）, **daily_active_service**（日活统计）, **device_ban_service**（设备封禁）, **time_of_use_pricing**（分时定价）, **share_service**（智能体分享码）, **announcement_service**（公告）, **ai_review_service**（网络市场 AI 辅助审核）, **maintenance_service**, remote_models, http_transport |
| Hub | `hub/` | **sync_hub**（SyncHub WebSocket 事件中枢：`var Hub` 单例 + `InitSyncHub`，app_event/聊天锁/sync_notify 广播；main.go 装配 `hub.InitSyncHub()` 后 `services.SetEventPublisher(hub.Hub)`） |
| Models | `models/` | user, user_agent, agent, network_agent, network_group, subscription_plan, subscription_plan_model, user_subscription, api_key, model_price, usage_record, payment_order, system_config, app_version, checkin_record, device, device_ban, feedback, ifdian, activity, audit_log, daily_active_user, sync_models |

### 关键端点

**公开端点**（无需认证）：
- `POST /api/v1/auth/register` / `login` / `refresh` — 用户认证（带登录限流）
- `POST /api/v1/auth/send-code` / `register-with-code` / `reset-password` — 邮箱验证码
- `GET /api/v1/models` — 可用模型列表
- `GET /api/v1/update/check` / `download/:id` / `versions` — 应用更新
- `GET /api/v1/activities` — 活动列表
- `GET /api/v1/payment/ifdian/plans` — 爱发电方案
- `POST /api/v1/payment/ifdian/webhook` — 爱发电回调（**已做签名校验** `BuildSign`）
- `GET/POST /api/v1/payment/notify` — 支付回调
- `GET /api/v1/sync/ws` — WebSocket 同步端点

**用户端点**（需认证）：
- `GET /api/v1/user/profile` / `balance` / `subscriptions` / `usage`
- `PUT /api/v1/user/profile` / `password`
- `POST /api/v1/user/avatar` / `daily-allowance/refresh`
- `GET/POST/PUT/DELETE /api/v1/user/agents` — 用户智能体
- `POST /api/v1/user/share/agent` / `POST /api/v1/user/share/redeem` — 智能体分享码创建/兑换
- `GET /api/v1/announcements/active` — 当前生效公告
- `POST /api/v1/chat/completions` / `completions/stream` — AI 聊天
- `GET /api/v1/quota/usage` / `POST /quota/consume` — 功能配额
- `GET/POST/PUT/DELETE /api/v1/network/agents` / `groups` — 网络市场
- `GET /api/v1/network/my/agents` / `groups` — 我上传的
- `POST /api/v1/network/agents/:id/download` / `groups/:id/download` — 下载
- `GET /api/v1/plans` / `GET /api/v1/user/subscription`
- `POST /api/v1/payment/subscribe` / `zero-drop` / `ifdian/verify`
- `GET /api/v1/payment/order/:orderNo`
- `POST/GET /api/v1/feedback` — 用户反馈

**同步端点**（需认证 + 订阅，`background_pressure` 限流保护大数据量端点）：
- `GET/POST /api/v1/sync/all` / `status` / `DELETE /sync/cloud`
- `GET/POST/DELETE /api/v1/sync/tombstones`
- `GET/POST /api/v1/sync/:table`
- **Sync v2**：`POST /api/v1/sync/v2/preview`（预览冲突）、`POST /api/v1/sync/v2/run`（执行合并）
- `GET/PUT /api/v1/sync/policy` — 同步策略（`sync_policy_service.go`）
- `POST /api/v1/sync/devices/register` / `GET /devices` / `PUT /devices/:device_id/role` / `PUT /devices/:device_id/name` / `DELETE /devices/:device_id` / `PUT /devices/full_sync`

**管理端点**（需认证 + admin 角色）：
- `GET /api/v1/admin/dashboard` / `users` / `orders` / `config`
- `POST/PUT/DELETE /api/v1/admin/users` — 用户管理
- `POST /api/v1/admin/users/:id/reset-test` — 高危测试重置
- `POST/PUT/DELETE /api/v1/admin/network/agents` / `groups` — 网络市场审核
- `POST /api/v1/admin/network/agents/:id/approve` / `reject` — 审核操作
- `GET/PUT /api/v1/admin/ai-review-config` / `POST /admin/network/agents/:id/ai-review` / `groups/:id/ai-review` — 网络市场 AI 辅助审核
- `GET/POST/PUT/DELETE /api/v1/admin/api-keys` / `model-prices` / `plans` / `versions` / `activities`
- `GET/POST/PUT/DELETE /api/v1/admin/announcements` — 公告管理
- `POST /api/v1/admin/model-prices/sync` — 模型价格同步
- `GET/PUT /api/v1/admin/payment-config` / `domain-config` / `config` / `smtp-config`
- `POST /api/v1/admin/smtp-config/test`
- `GET/PUT /api/v1/admin/ifdian/config` / `plans` / `records` / `POST ifdian/sync-plans`
- **分时定价**：`GET/PUT /admin/time-of-use-pricing`
- **审计**：`GET /admin/audit-logs` / `audit-logs/stats`
- **站点维护模式**：`GET/PUT /admin/maintenance-config`（开关 + bypass key；开启且 key 留空时服务端自动生成）

### 计费引擎（`billing_service.go`）

**扣减顺序**（永久余额已移除）：
1. 每日免费配额（0.2/天，**仅免费用户签到后获得**）
2. 订阅每日配额（订阅用户签到记录但不获得 0.2 免费配额）
3. ~~账户余额~~（已移除，`User.Balance` 字段保留仅用于历史数据/后台兼容，业务函数不再读写；残留的 `MistakeBalanceInsufficient`/`BalanceAfter` 仅为兼容输出）

- 按模型定价（缓存命中/缓存未命中/输出），思考模式 3× 倍率
- **分时定价**（`time_of_use_pricing.go`）：不同时段可采用不同价格
- 每日配额午夜重置（`quota_service.go`）
- 订阅购买当日立即生效（`getSubscriptionDailyQuota` 实时遍历有效订阅累加）
- 预留-确认机制（`billing_reservation.go`）：聊天前预留配额，完成后按实际用量确认

### 支付与回调的并发安全

- **支付回调**（`payment_service.go`）：原子状态转换 — `UpdateWhere` 带 `Status=pending` 过滤条件，只有 pending 订单才被激活，并发回调不会双重发放
- **爱发电订单**（`ifdian_service.go`）：`VerifyAndGrant` 使用按 `outTradeNo` 分片的字符串锁（`verifyGrantLocks.LockString`，见 `utils/idlock.go`），检查+发放串行化
- **爱发电 Webhook**（`ifdian.go`）：校验 `sign` + `ts`，签名不符返回 400

### 安全

- **密码**：bcrypt（cost=12）
- **JWT**：HS256，24h 过期（`config.yaml` `expire_hours: 24`）；启动 fail-fast 校验弱/占位密钥；claims 带 `token_version`，改密/重置密码递增 `User.TokenVersion` 使旧 token 立即失效
- **API Keys**：AES-256-GCM 加密存储
- **限流**：60 RPS/IP（通用），登录 5 req/min（认证端点）；`adaptive_limiter.go` 按延迟自适应调整并发
- **支付密钥**：AES 加密，后台 UI 掩码显示
- **加密密钥管理**（4 级优先级）：
  1. 环境变量 `ENCRYPTION_KEY`（生产推荐，密钥不落盘）
  2. 独立密钥文件 `.encryption_key`（0600 权限，与 config.yaml 分离）
  3. `config.yaml` 的 `encryption.key`（向后兼容，不推荐）
  4. 自动生成 48 字符密钥写入 `.encryption_key`
- **管理员密码**：环境变量 `ADMIN_PASSWORD` 或首次启动随机生成 16 字符密码（日志输出一次）
- **登录限流**：令牌桶算法，`LoginPerMin` 次/分钟
- **开放重定向防护**：`isSafeDownloadURL` 校验下载链接（http/https 白名单 + 内网 IP 检测）

### 思考模式中继

服务器代理 DeepSeek 思考模式：请求 `{"thinking":{"type":"enabled"},"reasoning_effort":"high"}` → 响应包含 `reasoning_content`（思维链）+ `content`（最终答案）。

### 多端同步

- **仅订阅用户可用**（`RequireSyncSubscription` 中间件）
- **13 张表全量同步**：聊天记录、短期记忆、设置、用户画像等
- **墓碑机制**：删除操作通过墓碑记录同步（`local_tombstones`）
- **Sync v2**：`/v2/preview` 预览合并冲突 → `/v2/run` 执行（`sync_v2_handler.go` + `sync_merge.go` + `sync_preview_service.go`）；同步策略可配（`/sync/policy`）
- **WebSocket 实时同步**：`/api/v1/sync/ws`（`sync_ws_handler.go` + `hub/sync_hub.go`），100% 同步启用时实时多端更新
- **聊天锁**：同智能体在多端同时发起聊天会被拦截，提示"你处于同步模式，请勿同时对同一聊天发送消息"
- **设备管理**：主机/副机角色，full_sync 模式开关
- 客户端侧有完整配套：`sync_service.dart`、`sync_websocket_service.dart`、`adaptive_sync_scheduler.dart`、`sync_payload_builder.dart`、`sync_response_applier.dart`、`sync_scope.dart`、`sync_status_probe.dart`、`sync_avatar_restore.dart`

### 网络市场

- **所有用户可上传/下载**（免费 + 订阅）
- 智能体和群聊均支持
- **审核流程**：上传后 `pending` → 管理员 `approve` → `published` / `reject` → `rejected`；管理员可用 AI 辅助审核（`network_ai_review.go` + `ai_review_service.go`，配置在 `/admin/ai-review-config`）
- **编辑重置审核**：编辑已发布内容 → Status 重置为 `pending`
- **核心内容保护**：人设、世界观等核心内容管理员不可修改
- **下架机制**：上传者可下架自己的内容，管理员可强制下架（`taken_down`）

## 业务规则清单

1. 网络代理/群组必须经管理员审核后才能发布
2. 编辑已发布的网络代理/群组会重置状态为 `pending` 重新审核
3. 网络代理/群组核心内容（人设、世界观）管理员不可修改
4. `realInfoEnabled` 字段（bool，默认 false）控制用户画像功能，每智能体独立
5. 用户画像 AI 每 10 轮对话触发一次（仅 `realInfoEnabled == true` 的智能体）
6. 群聊不触发画像 AI、不注入真实信息、不消耗真实回复配额
7. 多端同步仅订阅用户可用
8. 网络市场上传/下载对所有用户开放（免费 + 订阅）
9. 13 张用户数据表必须全量同步
10. 三份协议（用户协议、隐私政策含真实信息子协议、网络使用协议）必须签字并本地持久化带版本控制
11. `realInfoEnabled == true` 时，用户画像数据以 Markdown 格式注入聊天 AI 系统提示词
12. 聊天系统提示词必须明确角色定位："你 = 智能体"，"用户/对方 = 对话中的人"
13. 画像 AI 服务必须明确角色定位："我 = 智能体"，"对方 = 用户"，只提取对方画像
14. 100% 同步启用实时多端更新；同智能体多端同时发起聊天会被拦截
15. 免费用户签到后获得 0.2/天免费配额；订阅用户签到仅记录，不获得 0.2 免费配额
16. 订阅购买当日立即生效，当日即可使用订阅配额
17. 永久余额已移除（`User.Balance` 字段保留仅用于历史兼容，业务函数不再读写）
18. 设备 14 天内登录 ≥3 个不同账号触发封禁（2^(N-1) 天，封顶 365），订阅账号豁免，客户端 fail-open
19. AI 主动关心仅 `realInfoEnabled && proactiveCareEnabled` 的私聊智能体触发（群聊不触发）；每条消耗 1 次真实回复配额，配额不足静默跳过；同一智能体的上一条主动关心未被用户回复前不得连发
20. 一个智能体最多属于一个编组；解散编组不删除智能体。`linked_memory=true` 的群聊共用私聊记忆：长期/基础记忆写私聊表、群消息镜像写入在场成员私聊短期记忆；非 linked 群走原有 group_id 群域记忆，行为不变

## 开发注意事项

### 必须遵守

1. `flutter analyze` 必须 0 errors（pre-existing info/warnings 可接受）
2. 所有 DB 查询必须按 `agent_id` 过滤，禁止跨智能体数据泄漏
3. `MemoryService.setAgentId()` 总是重置 `_groupId = null` — 防止群聊上下文泄漏到私聊
4. 新代码用 `withValues(alpha:)` 而非 `withOpacity()`
5. 新代码用 `Theme.of(context).colorScheme` 而非 `Colors.white`/`Colors.black`
6. 所有 innerHTML 拼接必须经过 `escHtml()`（Web 后台）
7. 放弃内联 `onclick` 拼接用户数据，改用 `data-*` + 事件委托（Web 后台）
8. 密钥/敏感配置用环境变量，不写入 config.yaml
9. 根 `.gitignore` 已整体忽略 `/website/`（服务器源码不在客户端仓库，含 config.yaml/`.encryption_key`）——注意 AGENTS.md 旧条目与此矛盾已修正；服务器建议另建独立 git 仓库管理
10. 修改已发布网络内容前提醒用户 Status 会重置为 `pending`
11. 群聊并行回复中必须为每个 agent 创建独立 `MemoryService()`，禁止共享全局 provider 实例
12. `planService.onPlanTriggered` 只在 main.dart 全局注册，页面不得覆盖；回调携带计划归属 agentId，`deliverPlannedMessage` 按它落库
13. 聊天/群聊历史分页加载（`_chatPageSize`/`_groupPageSize`=100，滚动到顶 `loadEarlierMessages`/`loadEarlierGroupMessages` 向上翻页）；服务端使用非流式上游补全，客户端收到完整响应后本地模拟打字并以 50ms 节流渲染（私聊与群聊一致）；release 构建 debugPrint 全局静默（main.dart）——敏感内容不得进系统日志
14. 群聊流程禁止共享全局 `memoryServiceProvider`/`planServiceProvider` 单例（必须 `MemoryService()`/`PlanService(...)` 独立实例）

### 数据库

- DB schema 升级手动进行（`_onUpgrade` 按版本号，当前 36）。**永不自动删除列**
- 客户端 SQLite（`aichat.db`）和服务器 JSON 文件（`data/*.json`）是独立数据库
- 服务器用 SQLite（`database/database.go`，records + JSON payload）——热路径查询走实体列索引/json_extract 下推，勿新增整表内存过滤；连接池 `maxOpenConns=8`（WAL 多读者），写纪律：任何写/RMW/事务必须全程持 `DB.writeMu`（`WithTx` 与 `execWrite` 已内置，新增写路径必须走其一），纯读查询不持锁
- 备份 SQLite 前必须 `PRAGMA wal_checkpoint(FULL)` 刷盘（用 `rawQuery`，不用 execSQL）

### 测试

- Go 测试：`go test ./...`（handlers/services/middleware 下约 45 个测试文件，含 auth, billing, crypto, email, payment, plan, ratelimit, daily_allowance, checkin, admin_security, chat_security, sync_v2, adaptive_limiter, time_of_use, share, announcement, network_ai_review 等）
- Flutter 测试：`flutter test`（test/ 下 84 个测试文件）
- 支付/WebView 功能用真机测试，不用模拟器

### 文件

- `lib/config/server_config.dart` gitignored — 从 `.example` 复制到本地开发
- `website/API/config.yaml` gitignored — 含 JWT 密钥、加密密钥、支付密钥，**保持不提交**；模板为 `website/API/config.yaml.example`
- `website/API/admin/` 是生产后台，`website/API/frontend/admin/` 是旧版已弃用 — **修改只在 `admin/` 进行**
- `lib/agreements/` 含法律协议 — 未经法律审查不要修改

## 部署清单

### 服务器
- [ ] `go build -o aichat-api.exe .` 编译成功
- [ ] `go test ./...` 全部通过
- [ ] 环境变量 `ENCRYPTION_KEY` 已设置（生产推荐）
- [ ] 环境变量 `ADMIN_PASSWORD` 已设置（或首次启动记录随机密码）
- [ ] `.encryption_key` 已在 `.gitignore` 中忽略
- [ ] 停止旧服务 → 替换 exe → 启动新服务
- [ ] 后台浏览器硬刷新（Ctrl+F5）

### 客户端
- [ ] `flutter analyze` 0 errors
- [ ] `flutter test` 通过
- [ ] `assets/vision.json` 的 `version_code` 与 `pubspec.yaml` 的 build number 一致（当前均为 66）
- [ ] 服务器端发布对应 version_code 的版本记录以触发更新提示
- [ ] 真机测试支付/WebView 功能

## 关键文件快速索引

| 用途 | 文件 |
|---|---|
| Flutter 入口 | `lib/main.dart` |
| 路由配置 | `lib/main.dart:_AppShell` |
| API 服务 | `lib/services/api_service.dart` |
| 数据库服务 | `lib/services/database_service.dart`（version 38；纯静态外观 + 一行委托，方法体按表域拆在同库 part 文件：`database_agent_store.dart`/`database_memory_store.dart`/`database_chat_store.dart`/`database_misc_store.dart`/`database_sync_store.dart`/`database_maintenance.dart`/`database_schema.dart`/`account_database_migration.dart`） |
| 服务器配置 | `lib/config/server_config.dart`（gitignored）；服务端配置模板 `website/API/config.yaml.example` |
| Go 入口 | `website/API/main.go` |
| 路由注册 | `website/API/routes/routes.go` |
| 配置加载 | `website/API/config/config.go` |
| JSON DB | `website/API/database/database.go` |
| 计费引擎 | `website/API/services/billing_service.go` |
| 同步 Hub | `website/API/hub/sync_hub.go` |
| Sync v2 | `website/API/handlers/sync_v2_handler.go` + `services/sync_merge.go` |
| 后台管理 | `website/API/admin/index.html` + `admin/js/app.js` |
| 版本配置 | `assets/vision.json` + `pubspec.yaml` |
| 项目文档 | `README.md` / `ENGLISH.md` / `website/API/API文档.md` |
