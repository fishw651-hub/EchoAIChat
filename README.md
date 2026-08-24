# 回响 Echo — 项目文档

[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)

中文/[English](ENGLISH.md).

> 仓库：https://github.com/fishw651-hub/EchoAIChat · 协议：Mozilla Public License 2.0（免费开源、允许商用、使用需署名）

> 一个基于 Flutter 的 DeepSeek API AI 聊天应用，具备三层记忆系统、并行 Memory AI 架构、多智能体群聊与模拟器模式、Material 3 主题，以及严格的工具调用机制。

> [!WARNING]
> 这是一个AI编程辅助出来的软件，AI编程过敏者请不要使用

---

## 快速开始

### 客户端（Flutter）

```bash
# 1. 复制服务器配置模板并填入你的服务器地址
cp lib/config/server_config.dart.example lib/config/server_config.dart
#   然后编辑 lib/config/server_config.dart 把 YOUR_SERVER_IP 改成真实地址

# 2. 安装依赖并运行
flutter pub get
flutter run
```

### 服务端（Go API 中继）

服务端源码位于 [`website/API/`](website/API/)，与客户端在同一仓库。

```bash
cd website/API

# 1. 复制配置模板并替换占位值（jwt.secret 必须改成 ≥32 字符随机强密钥）
cp config.yaml.example config.yaml

# 2. 启动
go run main.go              # 端口来自 config.yaml（默认 8080）
go build -o aichat-api .    # 或编译为可执行文件
go test ./...               # 运行测试
```

关键服务端文件（可在 GitHub 上点击跳转）：

| 用途 | 文件 |
|---|---|
| Go 入口 | [website/API/main.go](website/API/main.go) |
| 路由注册 | [website/API/routes/routes.go](website/API/routes/routes.go) |
| 配置加载 | [website/API/config/config.go](website/API/config/config.go) |
| 计费引擎 | [website/API/services/billing_service.go](website/API/services/billing_service.go) |
| 同步 Hub | [website/API/hub/sync_hub.go](website/API/hub/sync_hub.go) |
| 后台管理 | [website/API/admin/index.html](website/API/admin/index.html) |
| 落地页 | [website/API/landing/index.html](website/API/landing/index.html) |
| API 文档 | [website/API/API文档.md](website/API/API文档.md) |

---

## 目录

1. [项目概述](#项目概述)
2. [架构概览](#架构概览)
3. [工具系统](#工具系统)
4. [系统提示词与记忆 AI](#系统提示词与记忆-ai)
5. [三层记忆系统](#三层记忆系统)
6. [群聊系统与模拟器模式](#群聊系统与模拟器模式)
7. [API 服务层](#api-服务层)
8. [供应商管理](#供应商管理)
9. [引导流程](#引导流程)
10. [多语言支持](#多语言支持)
11. [核心代码文件索引](#核心代码文件索引)

---

## 项目概述

**技术栈**：Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + XOR 加密 + Material 3  
**目标平台**：Android / iOS  
**应用名称**：回响（包名 com.aichat.aichat）  
**核心能力**：
- DeepSeek 专用 API 调用（聊天 + 视觉），支持思考模式（reasoning_effort: high）
- 强制工具调用（tool_choice: required → auto）
- 三层记忆 + 群聊共享记忆，严格的 agent_id 隔离（无跨智能体数据泄漏）
- 并行 Memory AI：对话时后台运行 deepseek-v4-flash 自动分析并更新记忆
- 多智能体（Agent）与群聊（Group Chat）
- 模拟器模式：AI 旁白自动创建 NPC 角色并推动剧情
- 每个 Agent 可配置开场白（opening line）
- 主动关心、计划消息、本地通知
- DeepSeek 供应商管理、Token 用量统计
- 引导流程（3 页向导：启动图 → 主题/语言 → API 配置）
- 中英双语本地化
- Material 3 设计主题（AppTheme）

---

## 架构概览

```
lib/
├── main.dart                       # 入口：MaterialApp、ProviderScope、初始化主题/多语言/通知
├── theme/
│   └── app_theme.dart              # Material 3 设计令牌：间距、圆角、阴影、ThemeData
├── l10n/
│   └── app_localizations.dart      # 中英双语本地化
├── utils/
│   └── responsive_layout.dart      # 响应式布局辅助（断点、缩放）
├── services/
│   ├── api_service.dart            # HTTP 请求、工具定义、视觉 API、错误处理与自动重试
│   ├── memory_service.dart         # 三层记忆 CRUD + 提示词生成，agent_id / group_id 隔离
│   ├── memory_ai_service.dart      # 并行 Memory AI：对话时自动分析并写入记忆（deepseek-v4-flash）
│   ├── tool_executor.dart          # 工具执行器（remember/forget/chat/chatgroup/plan/manage_character）
│   ├── model_service.dart          # 从 API 获取模型列表
│   ├── database_service.dart       # sqflite 数据库（v17）+ 备份恢复 + _ensureGroupTablesExist
│   ├── encryption_service.dart     # XOR + SHA-256 加密 API Key
│   ├── notification_service.dart   # 本地通知（计划消息 + 主动关心）
│   ├── plan_service.dart           # 计划消息调度
│   ├── locale_service.dart         # IP 语言检测 + 偏好持久化
│   ├── group_service.dart          # 群聊 CRUD + 共享记忆 + 系统提示词构建（旁白/NPC/普通三分支）
│   └── agent_export_service.dart   # 智能体 JSON 导入导出（含头像/背景 base64）
├── repositories/
│   └── memory_repository.dart      # 记忆数据访问层，所有方法要求 agentId
├── providers/
│   ├── chat_provider.dart          # 聊天状态、_runToolLoop 工具循环、并行 Memory AI、主动关心
│   ├── settings_provider.dart      # DeepSeek 供应商 CRUD、主题色、思考模式、温度、Token 累计
│   ├── memory_provider.dart        # 长期/基础记忆的 Riverpod 状态
│   ├── group_provider.dart         # 群聊、成员、群消息状态、模拟器模式、批量并行回复
│   └── agent_provider.dart         # 智能体状态
├── models/
│   ├── agent.dart                  # 智能体（含 opening_line、avatar、chat_background、is_sim_character）
│   ├── long_term_memory.dart       # 长期记忆（9 字段 + agent_id + group_id）
│   ├── base_memory.dart            # 基础记忆（setting/event + agent_id + group_id）
│   ├── short_term_message.dart     # 短期消息（agent_id + group_id）
│   ├── planned_message.dart        # 计划消息
│   ├── provider_config.dart        # 供应商配置
│   ├── group_chat.dart             # 群聊（含 isSimulatorMode、worldSetting）
│   ├── group_member.dart           # 群成员
│   ├── group_message.dart          # 群消息（含 toolLogs）
│   └── group_shared_memory.dart    # 群共享记忆
└── screens/
    ├── chat_screen.dart            # 聊天主页面（长按弹出菜单、多选、记忆面板）
    ├── settings_screen.dart        # 设置页（供应商/模型/思考模式/温度/主题/语言）
    ├── onboarding_screen.dart      # 引导流程（3 页向导）
    ├── memory_screen.dart          # 记忆管理页（短期/长期/基础）
    ├── agent_create_screen.dart    # 智能体创建/编辑页
    ├── group_chat_screen.dart      # 群聊对话页（长按菜单、多选、记忆面板、工具日志）
    ├── group_create_screen.dart    # 群聊创建页（含模拟器模式开关）
    ├── group_manage_screen.dart    # 群聊管理页
    ├── group_list_screen.dart      # 群聊列表
    ├── plan_screen.dart            # 计划消息页
    ├── token_usage_screen.dart     # Token 用量图表页
    └── novel_history_screen.dart   # 小说生成历史页
```

---

## 工具系统

AI 通过 DeepSeek API 的 `tools` 参数定义工具。`ApiService.getToolDefinitions(isGroupChat: ...)` 根据场景返回**两组不同**的工具集。

### 私聊工具（2 个）

私聊（与单个智能体）使用 2 个工具。记忆由并行的 Memory AI 自动管理，不暴露为工具：

| 工具 | 用途 |
|------|------|
| `chat` | 向用户发送自然语言回复（每次对话必须使用） |
| `plan` | 安排未来发送的消息（可选，用于提醒或惊喜） |

### 群聊工具（5 个）

群聊场景使用独立的工具集，包含记忆管理（个人/群共享）和角色管理：

| 工具 | 用途 |
|------|------|
| `remember` | 创建/更新记忆（group_scope: personal / shared） |
| `forget` | 删除记忆（memory_source: personal / shared） |
| `chatgroup` | 在群聊中发送消息 |
| `plan` | 安排未来群聊消息 |
| `manage_character` | 创建或移除 NPC/配角（模拟器模式核心工具） |

### 工具调用流程

1. 第一次调用：`tool_choice: 'required'` —— 强制 AI 调用工具
2. 执行工具调用，将结果注入消息数组
3. 如果调用了 `chat` / `chatgroup` → 提取回复并停止
4. 否则继续调用：`tool_choice: 'auto'`
5. 最多 5 轮，超出后返回已有内容

---

## 系统提示词与记忆 AI

### 双 AI 架构

应用采用**并行双 AI** 架构：

| AI | 模型 | 职责 |
|----|------|------|
| **Chat AI** | 用户选择的模型（deepseek-v4-pro / deepseek-v4-flash） | 对话、工具调用、生成回复 |
| **Memory AI** | deepseek-v4-flash（硬编码） | 分析短期上下文，自动创建/更新/删除长期和基础记忆 |

### 执行流程

```
用户发送消息
    │
    ├── 构建系统提示词（时间 + 人设 + 长期记忆 + 基础记忆）
    │
    ├── 启动 Memory AI（并行 Future）
    │     └── 分析最近 2 轮对话 → JSON 格式记忆操作 → 直接写入 DB
    │
    ├── _runToolLoop（Chat AI）
    │     ├── API 调用（tool_choice: required）
    │     ├── 执行工具 → 注入结果
    │     └── 检测 chat 工具 → 提取回复
    │
    └── 等待 Memory AI 完成 → 刷新记忆列表
```

### 系统提示词结构

```
【当前真实时间】2026-06-13 14:30（星期五）

{{PERSONA}}

## 你的记忆
由系统自动管理，你只需参考它们来了解用户。

【长期记忆】
L001 [relationships] 用户有一个朋友叫老张...

【基础记忆】
B001 [setting] 你是用户的私人AI伴侣，名字叫小言...

## 可用工具
- chat：向用户说出回复（每次必须使用）
- plan：安排未来消息（可选）

## 对话风格
严格按照人设说话，把记忆信息自然融入对话。回复温暖、松弛，像个真人。
```

---

## 三层记忆系统

### 短期记忆（Short-term）

| 属性 | 值 |
|------|-----|
| **存储表** | `short_term_messages`（私聊）、`group_short_term`（群聊） |
| **ID 格式** | `S001` ~ `S999` |
| **容量** | 默认 20 轮（可配置 maxShortTermRounds） |
| **内容** | 最近对话原文（role + content + timestamp） |
| **管理** | 环形覆盖：超过容量时删除最旧条目 |
| **用途** | 直接注入 API 请求的 `messages` 数组 |

### 长期记忆（Long-term）

| 属性 | 值 |
|------|-----|
| **存储表** | `long_term_memories` |
| **ID 格式** | `L001` ~ `L999` |
| **容量** | 建议 ≤ 15 条 |
| **字段** | `time`, `location`, `current_events`, `characters`, `relationships`, `goals`, `thoughts`, `status`, `to_do` |
| **管理** | Memory AI 自动创建/更新/删除；也可在记忆管理页面手动操作 |

### 基础记忆（Base）

| 属性 | 值 |
|------|-----|
| **存储表** | `base_memories` |
| **ID 格式** | `B001` ~ `B999` |
| **类型** | `setting`（设定/人设，永久不可删除）、`event`（历史事件） |

### 范围隔离（agent_id / group_id）

所有长期/基础记忆表带有 `agent_id` 和 `group_id`（可空）：
- `agent_id != null, group_id == null`：私聊记忆
- `group_id != null`：群聊记忆

**强制规则**：所有记忆读写操作必须传入 `agentId`。`null` agentId 的读操作返回空列表，写操作跳过并警告。`setAgentId()` 始终重置 `_groupId = null` 防止群聊上下文泄漏到私聊。

---

## 群聊系统与模拟器模式

### 数据模型

群聊拥有独立的对话、记忆、工具集。核心表：

- `group_chats`：名称、描述、群人设、发言模式、`isSimulatorMode`、`worldSetting`
- `group_members`：agent_id、role（moderator/member）、is_present
- `group_messages`：发送者类型/ID/名称、内容、tool_call_data（工具日志）
- `group_short_term`：群聊短期记忆
- `group_shared_memories`：群共享记忆

### 群聊消息流（批量并行回复）

```
用户输入
    │
    ├── 写入 group_messages (sender_type=user)
    ├── 读取 group_short_term 作为基础上下文
    ├── 为每个在场 Agent 并行调用 API（Future.wait）
    │     └── 所有 Agent 共享同一份基础上下文（无上下文累积）
    ├── 工具调用：
    │     remember(group_scope=shared) → group_shared_memories
    │     remember(group_scope=personal) → long_term_memories
    │     manage_character(action: add) → 创建 NPC 角色并加入群聊
    │     chatgroup → 写入 group_messages
    └── 全部完成后刷新 UI
```

### 模拟器模式

群聊可切换为模拟器模式，实现 AI 驱动的故事叙述：

- **旁白（Narrator）**：自动创建，角色为 moderator。使用 `manage_character` 创建 NPC，使用 `chatgroup` 输出场景叙述（第三人称纯叙述文）
- **NPC 角色**：由旁白创建的 AI 智能体，用第一人称说话，`()` 表达动作表情
- **user 是主角**：user 输入的文字即主角的言行，旁白不指挥、不替代
- **思考模式强制开启**：模拟器模式下 `thinkingMode: true` 无视全局设置
- **批量并行回复**：所有在场角色独立生成回复（同一基础上下文，不累积）
- **创建防重**：`manage_character` 在添加前检查已存在成员，防止重复创建

---

## API 服务层

### 核心参数

| 参数 | 私聊 | 群聊 / 模拟器 |
|------|------|-------------|
| `model` | 用户选择（默认 deepseek-v4-flash） | 同用户选择 |
| `tool_choice` | 首次 `required`，后续 `auto` | 首次 `required`，后续 `auto` |
| `thinking` | 根据全局设置 | 模拟器模式强制 `enabled` |
| `reasoning_effort` | `'high'`（仅 high/max 有效） | `'high'` |
| `temperature` | 仅思考模式关闭时发送（0~2，默认 1.0） | 同左 |

### 错误处理与自动重试

```
SocketException    → "网络连接失败"
TimeoutException   → "请求超时"
FormatException    → "响应格式异常"
HTTP 401           → "API Key 无效或已过期"
HTTP 403           → "无权访问"
HTTP 404           → "Base URL 不正确或模型不存在"
HTTP 429           → "请求过于频繁"
HTTP 5xx           → "服务端错误"

400（tool_choice 被拒）   → 移除 tool_choice 后重试
400（thinking 被拒）      → 移除 thinking + reasoning_effort 后重试
```

### API Key 安全

- **存储**：XOR + SHA-256 加密后写入 SQLite
- **内存**：`SettingsNotifier._init()` 时解密到内存
- **日志**：`_maskedKey` 仅显示前 4 位和后 4 位（`sk-a...b1c2`）
- **导出**：配置导出仅包含脱敏 Key，不含完整 Key
- **永不**在日志或导出中出现明文 Key

---

## 供应商管理

### 预设供应商

| 供应商 | API Base URL | 模型列表 |
|--------|-------------|---------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash`、`deepseek-v4-pro` |
| Custom | （自定义） | （手动输入） |

### 模型获取

用户可在设置页点击"获取模型"按钮，通过 API 请求 `/v1/models` 获取可用模型列表并缓存。无缓存时显示文本输入框，有缓存时显示下拉菜单。

### 思考模式与温度

- **思考模式**：DeepSeek 推理链，提升回答质量（增加响应时间）。模拟器模式强制开启
- **温度**：0~2 滑块（0.1 步长），仅思考模式关闭时发送（DeepSeek API 在思考期间忽略温度参数）

---

## 引导流程

首次启动时展示 3 页引导向导：

| 页面 | 内容 |
|------|------|
| **第 1 页 — 欢迎** | 显示 `assets/1.jpg`，等比例缩放黑色填充，兼作加载画面 |
| **第 2 页 — 主题与语言** | 主题模式选择（自动/浅色/深色）+ 8 色主题色选择 + 语言（自动/中文/English）+ 实时预览卡片 |
| **第 3 页 — API 配置** | API Key 输入（带可见性切换）+ 模型输入 + 思考模式开关 + 温度滑块 + "获取 DeepSeek API Key" 超链接 → `platform.deepseek.com/api_keys` |

完成后自动创建 DeepSeek 供应商、保存所有设置、标记 `isFirstRun = false`，跳转至创建智能体页面。

后续启动通过 `_AppShell` 路由决策：`isFirstRun` → 引导页 → `agents.isEmpty` → 简单引导 → `ChatScreen`。

---

## 多语言支持

| 模式 | 说明 |
|------|------|
| **自动** | 启动时调用 `ip-api.com/json` 检测国家码，CN/HK/TW/MO/SG → 中文，其他 → English |
| **手动** | 用户在设置页或引导页选择后持久化到 SharedPreferences（键 `language_mode`） |

`lib/l10n/app_localizations.dart` 包含中英双语键值对，所有 UI 文本通过 `AppLocalizations.of(context).get('key')` 获取。

---

## 核心代码文件索引

| 文件 | 核心职责 |
|------|---------|
| `lib/main.dart` | 应用入口、主题/多语言/通知初始化、_AppShell 路由决策 |
| `lib/providers/chat_provider.dart` | 聊天状态、_runToolLoop 工具循环、并行 Memory AI、系统提示词、主动关心 |
| `lib/screens/chat_screen.dart` | 聊天 UI：气泡动画、长按弹出菜单（图标网格）、多选删除、记忆面板 |
| `lib/services/database_service.dart` | 17 张表的 CRUD、备份恢复、_ensureGroupTablesExist 弹性迁移 |
| `lib/services/api_service.dart` | HTTP 请求、工具定义（私聊/群聊两套）、视觉 API、错误处理与自动重试 |
| `lib/services/memory_service.dart` | 短期/长期/基础记忆 CRUD、agent_id/group_id 隔离、提示词组装 |
| `lib/services/memory_ai_service.dart` | 并行 Memory AI：分析对话 → JSON 解析（3 级回退）→ 自动写入记忆 |
| `lib/services/group_service.dart` | 群聊、成员、群消息、共享记忆 CRUD、系统提示词三分支构建 |
| `lib/providers/settings_provider.dart` | DeepSeek 供应商 CRUD、主题色、思考模式、温度、Token 累计 |
| `lib/providers/group_provider.dart` | 群聊状态、批量并行回复、_runGroupToolLoop、模拟器模式 |
| `lib/providers/memory_provider.dart` | 长期/基础记忆的 Riverpod 状态，agent 切换监听 |
| `lib/providers/agent_provider.dart` | 智能体 CRUD 状态 |
| `lib/services/tool_executor.dart` | 6 工具执行逻辑、执行日志、重复角色名检查 |
| `lib/screens/onboarding_screen.dart` | 3 页引导向导：欢迎图 → 主题/语言 → API 配置 |
| `lib/screens/group_chat_screen.dart` | 群聊对话 UI：多气泡、长按菜单、多选、记忆面板、工具日志查看 |
| `lib/screens/settings_screen.dart` | 设置页：供应商/模型下拉/思考模式/温度/主题/语言 |
| `lib/screens/memory_screen.dart` | 记忆管理页（短期/长期/基础三个 Tab） |
| `lib/screens/agent_create_screen.dart` | 智能体创建/编辑表单（含人设占位符快捷按钮） |
| `lib/screens/group_create_screen.dart` | 群聊创建（多选 Agent + 模拟器模式开关） |
| `lib/theme/app_theme.dart` | Material 3 设计令牌与 ThemeData（间距/圆角/阴影/动画） |
| `lib/l10n/app_localizations.dart` | 中英双语本地化 |
| `lib/services/encryption_service.dart` | XOR + SHA-256 加解密 |
| `lib/services/locale_service.dart` | IP 检测 + 语言偏好持久化 |
| `lib/services/notification_service.dart` | 本地通知调度 |
| `lib/services/plan_service.dart` | 计划消息持久化与触发 |
| `lib/services/model_service.dart` | 从 API 获取模型列表 |

---

> **版本**：v3.0  
> **生成时间**：2026-06-13  
> **技术栈**：Flutter 3.x / Dart / Riverpod / sqflite / Material 3 / DeepSeek API
