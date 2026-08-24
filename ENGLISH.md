# 回响 Echo — Project Documentation

[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)

ENGLISH/[中文](README.md).

> Repository: https://github.com/fishw651-hub/EchoAIChat · License: Mozilla Public License 2.0 (open source, commercial use allowed, attribution required)

> A Flutter-based DeepSeek API AI chat application featuring a three-tier memory system, parallel Memory AI architecture, multi-agent group chat with simulator mode, Material 3 theme, and strict tool calling mechanisms.

> [!WARNING]
> This software was developed with AI programming assistance. If you are allergic to AI programming, please do not use it.

---

## Quick Start

### Client (Flutter)

```bash
# 1. Copy the server config template and fill in your server address
cp lib/config/server_config.dart.example lib/config/server_config.dart
#   Then edit lib/config/server_config.dart, replacing YOUR_SERVER_IP with the real address

# 2. Install dependencies and run
flutter pub get
flutter run
```

### Server (Go API relay)

The server source lives in [`website/API/`](website/API/), in the same repository as the client.

```bash
cd website/API

# 1. Copy the config template and replace placeholders (jwt.secret must be a ≥32-char random strong key)
cp config.yaml.example config.yaml

# 2. Run
go run main.go              # port from config.yaml (default 8080)
go build -o aichat-api .    # or build an executable
go test ./...               # run tests
```

Key server files (clickable on GitHub):

| Purpose | File |
|---|---|
| Go entry | [website/API/main.go](website/API/main.go) |
| Routes | [website/API/routes/routes.go](website/API/routes/routes.go) |
| Config loader | [website/API/config/config.go](website/API/config/config.go) |
| Billing engine | [website/API/services/billing_service.go](website/API/services/billing_service.go) |
| Sync Hub | [website/API/hub/sync_hub.go](website/API/hub/sync_hub.go) |
| Admin panel | [website/API/admin/index.html](website/API/admin/index.html) |
| Landing page | [website/API/landing/index.html](website/API/landing/index.html) |
| API docs | [website/API/API文档.md](website/API/API文档.md) |

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Tool System](#tool-system)
4. [System Prompt & Memory AI](#system-prompt--memory-ai)
5. [Three-tier Memory System](#three-tier-memory-system)
6. [Group Chat System & Simulator Mode](#group-chat-system--simulator-mode)
7. [API Service Layer](#api-service-layer)
8. [Provider Management](#provider-management)
9. [Onboarding Flow](#onboarding-flow)
10. [Multilingual Support](#multilingual-support)
11. [Core Code File Index](#core-code-file-index)

---

## Project Overview

**Tech Stack**: Flutter 3.x + Dart + Riverpod + sqflite + shared_preferences + XOR encryption + Material 3  
**Target Platforms**: Android / iOS  
**App Name**: 回响 (package: com.aichat.aichat)  
**Core Capabilities**:
- DeepSeek-dedicated API calls (chat + vision), with thinking mode support (reasoning_effort: high)
- Mandatory tool calls (tool_choice: required → auto)
- Three-tier memory + group-shared memory, strict agent_id isolation (no cross-agent data leaks)
- Parallel Memory AI: background deepseek-v4-flash analyzes conversation and auto-manages memories
- Multi-agent (Agent) and group chat
- Simulator mode: AI narrator auto-creates NPC characters and drives the story
- Per-agent configurable opening line
- Proactive care, planned messages, local notifications
- DeepSeek provider management, token usage statistics
- Onboarding flow (3-page wizard: splash → theme/language → API config)
- Chinese-English bilingual localization
- Material 3 design theme (AppTheme)

---

## Architecture Overview

```
lib/
├── main.dart                       # Entry: MaterialApp, ProviderScope, theme/locale/notification init
├── theme/
│   └── app_theme.dart              # Material 3 design tokens: spacing, radii, shadows, ThemeData
├── l10n/
│   └── app_localizations.dart      # Chinese-English bilingual localization
├── utils/
│   └── responsive_layout.dart      # Responsive layout helpers (breakpoints, scaling)
├── services/
│   ├── api_service.dart            # HTTP requests, tool definitions, vision API, error handling & retry
│   ├── memory_service.dart         # Three-tier memory CRUD + prompt gen, agent_id/group_id isolation
│   ├── memory_ai_service.dart      # Parallel Memory AI: auto-analyze conversations, write memories (deepseek-v4-flash)
│   ├── tool_executor.dart          # Tool executor (remember/forget/chat/chatgroup/plan/manage_character)
│   ├── model_service.dart          # Fetch model list from API
│   ├── database_service.dart       # sqflite database (v17) + backup/restore + _ensureGroupTablesExist
│   ├── encryption_service.dart     # XOR + SHA-256 encryption of API keys
│   ├── notification_service.dart   # Local notifications (planned messages + proactive care)
│   ├── plan_service.dart           # Planned message scheduling
│   ├── locale_service.dart         # IP language detection + preference persistence
│   ├── group_service.dart          # Group chat CRUD + shared memory + system prompt (narrator/NPC/normal branches)
│   └── agent_export_service.dart   # Agent JSON import/export (avatar/background as base64)
├── repositories/
│   └── memory_repository.dart      # Memory data access layer, all methods require agentId
├── providers/
│   ├── chat_provider.dart          # Chat state, _runToolLoop, parallel Memory AI, proactive care
│   ├── settings_provider.dart      # DeepSeek provider CRUD, theme color, thinking mode, temperature, tokens
│   ├── memory_provider.dart        # Riverpod state for long-term/base memory
│   ├── group_provider.dart         # Group/member/message state, simulator mode, batch parallel replies
│   └── agent_provider.dart         # Agent state
├── models/
│   ├── agent.dart                  # Agent (opening_line, avatar, chat_background, is_sim_character)
│   ├── long_term_memory.dart       # Long-term memory (9 fields + agent_id + group_id)
│   ├── base_memory.dart            # Base memory (setting/event + agent_id + group_id)
│   ├── short_term_message.dart     # Short-term message (agent_id + group_id)
│   ├── planned_message.dart        # Planned message
│   ├── provider_config.dart        # Provider configuration
│   ├── group_chat.dart             # Group chat (isSimulatorMode, worldSetting)
│   ├── group_member.dart           # Group member
│   ├── group_message.dart          # Group message (with toolLogs)
│   └── group_shared_memory.dart    # Group shared memory
└── screens/
    ├── chat_screen.dart            # Chat UI (long-press popup, multi-select, memory panel)
    ├── settings_screen.dart        # Settings (provider/model/thinking/temperature/theme/language)
    ├── onboarding_screen.dart      # Onboarding wizard (3-page)
    ├── memory_screen.dart          # Memory management (short-term/long-term/base tabs)
    ├── agent_create_screen.dart    # Agent create/edit form
    ├── group_chat_screen.dart      # Group chat UI (long-press menu, multi-select, memory panel, tool logs)
    ├── group_create_screen.dart    # Group creation (simulator mode toggle)
    ├── group_manage_screen.dart    # Group management
    ├── group_list_screen.dart      # Group list
    ├── plan_screen.dart            # Planned messages
    ├── token_usage_screen.dart     # Token usage chart
    └── novel_history_screen.dart   # Novel generation history
```

---

## Tool System

Tools are defined through the DeepSeek API's `tools` parameter. `ApiService.getToolDefinitions(isGroupChat: ...)` returns **two different tool sets** depending on the scenario.

### Private Chat Tools (2)

Private chat (with a single agent) uses 2 tools. Memory is managed automatically by the parallel Memory AI and is not exposed as tools:

| Tool | Purpose |
|------|---------|
| `chat` | Send a natural language reply to the user (must be called every turn) |
| `plan` | Schedule a future message (optional, for reminders or surprises) |

### Group Chat Tools (5)

Group chat uses a separate tool set including memory management (personal/shared) and character management:

| Tool | Purpose |
|------|---------|
| `remember` | Create/update memory (group_scope: personal / shared) |
| `forget` | Delete memory (memory_source: personal / shared) |
| `chatgroup` | Send a message in the group chat |
| `plan` | Schedule a future group message |
| `manage_character` | Create or remove NPC characters (simulator mode's core tool) |

### Tool Call Flow

1. First call: `tool_choice: 'required'` — forces the AI to call a tool
2. Execute tool calls, inject results into the message array
3. If `chat` / `chatgroup` was called → extract the reply and stop
4. Otherwise continue calling: `tool_choice: 'auto'`
5. Max 5 rounds, then return whatever is available

---

## System Prompt & Memory AI

### Dual AI Architecture

The app uses a **parallel dual AI** architecture:

| AI | Model | Role |
|----|-------|------|
| **Chat AI** | User-chosen model (deepseek-v4-pro / deepseek-v4-flash) | Conversation, tool calls, generating replies |
| **Memory AI** | deepseek-v4-flash (hardcoded) | Analyze short-term context, auto-create/update/delete long-term and base memories |

### Execution Flow

```
User sends message
    │
    ├── Build system prompt (time + persona + long-term memories + base memories)
    │
    ├── Launch Memory AI (parallel Future)
    │     └── Analyze last 2 rounds → JSON memory operations → directly write to DB
    │
    ├── _runToolLoop (Chat AI)
    │     ├── API call (tool_choice: required)
    │     ├── Execute tools → inject results
    │     └── Detect chat tool → extract reply
    │
    └── Await Memory AI → refresh memory lists
```

### System Prompt Structure

```
【Current Actual Time】2026-06-13 14:30 (Friday)

{{PERSONA}}

## Your Memory
Automatically managed by the system. You need only reference them to understand the user.

【Long-term Memory】
L001 [relationships] The user has a friend named Lao Zhang...

【Base Memory】
B001 [setting] You are the user's personal AI companion named Xiaoyan...

## Available Tools
- chat: Send your natural language reply (must be used every turn)
- plan: Schedule a future message (optional)

## Conversation Style
Strictly follow your persona. Integrate memory information naturally into conversation.
Replies should be warm, relaxed, like a real person.
```

---

## Three-tier Memory System

### Short-term Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `short_term_messages` (private), `group_short_term` (group) |
| **ID Format** | `S001` ~ `S999` |
| **Capacity** | Default 20 turns (configurable via maxShortTermRounds) |
| **Content** | Original conversation text (role + content + timestamp) |
| **Management** | Circular overwrite: oldest entries deleted when capacity exceeded |
| **Usage** | Directly injected into API request `messages` array |

### Long-term Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `long_term_memories` |
| **ID Format** | `L001` ~ `L999` |
| **Capacity** | Recommended ≤ 15 entries |
| **Fields** | `time`, `location`, `current_events`, `characters`, `relationships`, `goals`, `thoughts`, `status`, `to_do` |
| **Management** | Memory AI auto-creates/updates/deletes; manual management also available via memory screen |

### Base Memory

| Attribute | Value |
|-----------|-------|
| **Storage Table** | `base_memories` |
| **ID Format** | `B001` ~ `B999` |
| **Types** | `setting` (persona/permanent, cannot be deleted), `event` (historical events) |

### Scope Isolation (agent_id / group_id)

All long-term/base memory tables carry `agent_id` and `group_id` (nullable):
- `agent_id != null, group_id == null`: private chat memory
- `group_id != null`: group chat memory

**Hard rule**: All memory read/write operations must include `agentId`. Reads with null agentId return empty lists; writes skip with a warning. `setAgentId()` always resets `_groupId = null` to prevent group context leaking into private chat.

---

## Group Chat System & Simulator Mode

### Data Models

Group chat has its own conversations, memories, and tool sets. Core tables:

- `group_chats`: name, description, group persona, speech mode, `isSimulatorMode`, `worldSetting`
- `group_members`: agent_id, role (moderator/member), is_present
- `group_messages`: sender type/ID/name, content, tool_call_data (tool execution logs)
- `group_short_term`: group short-term memory
- `group_shared_memories`: group shared memory

### Group Message Flow (Batch Parallel Replies)

```
User input
    │
    ├── Write group_messages (sender_type=user)
    ├── Read group_short_term as base context
    ├── For each present Agent, call API in parallel (Future.wait)
    │     └── All agents share the same base context (no accumulated context)
    ├── Tool calls:
    │     remember(group_scope=shared) → group_shared_memories
    │     remember(group_scope=personal) → long_term_memories
    │     manage_character(action: add) → create NPC and join group
    │     chatgroup → write group_messages
    └── Refresh UI after all complete
```

### Simulator Mode

Groups can switch to simulator mode for AI-driven storytelling:

- **Narrator**: Auto-created as moderator. Uses `manage_character` to create NPCs, uses `chatgroup` for scene narration (third-person narrative prose)
- **NPC Characters**: AI agents created by the narrator; speak in first-person with `()` action format
- **User is the protagonist**: user's input is the protagonist's words and actions; the narrator never commands or substitutes
- **Thinking mode forced ON**: simulator mode sets `thinkingMode: true` regardless of global setting
- **Batch parallel replies**: all present characters generate replies independently (same base context, no accumulation)
- **Duplicate prevention**: `manage_character` checks existing members before creating, preventing duplicate characters

---

## API Service Layer

### Core Parameters

| Parameter | Private Chat | Group / Simulator |
|-----------|-------------|-------------------|
| `model` | User-chosen (default deepseek-v4-flash) | Same as user choice |
| `tool_choice` | First `required`, subsequent `auto` | First `required`, subsequent `auto` |
| `thinking` | Per global setting | Simulator mode forces `enabled` |
| `reasoning_effort` | `'high'` (only high/max are valid) | `'high'` |
| `temperature` | Only sent when thinking mode is OFF (0~2, default 1.0) | Same |

### Error Handling & Auto-Retry

```
SocketException    → "Network connection failed"
TimeoutException   → "Request timed out"
FormatException    → "Response format abnormal"
HTTP 401           → "API Key invalid or expired"
HTTP 403           → "Access denied"
HTTP 404           → "Incorrect Base URL or model does not exist"
HTTP 429           → "Too many requests"
HTTP 5xx           → "Server error"

400 (tool_choice rejected) → Remove tool_choice and retry
400 (thinking rejected)    → Remove thinking + reasoning_effort and retry
```

### API Key Security

- **Storage**: XOR + SHA-256 encrypted before writing to SQLite
- **Memory**: Decrypted during `SettingsNotifier._init()` into memory
- **Logging**: `_maskedKey` shows only first 4 and last 4 characters (`sk-a...b1c2`)
- **Export**: Config export only includes masked key, never the full key
- **Never** appears in plaintext in logs or exports

---

## Provider Management

### Preset Providers

| Provider | API Base URL | Models |
|----------|-------------|--------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash`, `deepseek-v4-pro` |
| Custom | (custom) | (manual input) |

### Model Fetching

Users can click the "Fetch" button in Settings to retrieve the available model list via the API's `/v1/models` endpoint and cache it. When a cache is available, a dropdown is shown; otherwise, a free-text input field is displayed.

### Thinking Mode & Temperature

- **Thinking Mode**: DeepSeek reasoning chain for better answers (increases response time). Forced on in simulator mode
- **Temperature**: 0–2 slider (0.1 step), only sent when thinking mode is OFF (DeepSeek API ignores temperature during thinking)

---

## Onboarding Flow

A 3-page wizard is shown on first launch:

| Page | Content |
|------|---------|
| **Page 1 — Welcome** | Displays `assets/1.jpg`, proportionally scaled with black fill, doubles as loading screen |
| **Page 2 — Theme & Language** | Theme mode (Auto/Light/Dark) + 8 color picker + language (Auto/中文/English) + live preview card |
| **Page 3 — API Config** | API Key input (with visibility toggle) + model input + thinking mode toggle + temperature slider + "Get DeepSeek API Key" link → `platform.deepseek.com/api_keys` |

On completion: auto-creates DeepSeek provider, saves all settings, marks `isFirstRun = false`, navigates to agent creation.

Subsequent launches use `_AppShell` routing: `isFirstRun` → onboarding → `agents.isEmpty` → simple onboarding → `ChatScreen`.

---

## Multilingual Support

| Mode | Description |
|------|-------------|
| **Auto** | On startup, detect country code via `ip-api.com/json`. CN/HK/TW/MO/SG → Chinese, others → English |
| **Manual** | User selects language in settings or onboarding, persisted to SharedPreferences (key `language_mode`) |

`lib/l10n/app_localizations.dart` contains Chinese-English bilingual key-value pairs. All UI text is retrieved via `AppLocalizations.of(context).get('key')`.

---

## Core Code File Index

| File | Core Responsibility |
|------|---------------------|
| `lib/main.dart` | App entry, theme/locale/notification init, _AppShell routing |
| `lib/providers/chat_provider.dart` | Chat state, _runToolLoop, parallel Memory AI, system prompt, proactive care |
| `lib/screens/chat_screen.dart` | Chat UI: bubble animations, long-press popup (icon grid), multi-select delete, memory panel |
| `lib/services/database_service.dart` | CRUD for 17 tables, backup/restore, _ensureGroupTablesExist resilient migration |
| `lib/services/api_service.dart` | HTTP requests, tool definitions (private/group sets), vision API, error handling & auto-retry |
| `lib/services/memory_service.dart` | Short-term/long-term/base memory CRUD, agent_id/group_id isolation, prompt assembly |
| `lib/services/memory_ai_service.dart` | Parallel Memory AI: analyze conversation → JSON parsing (3-tier fallback) → auto-write memories |
| `lib/services/group_service.dart` | Group/member/message/shared memory CRUD, 3-branch system prompt builder |
| `lib/providers/settings_provider.dart` | DeepSeek provider CRUD, theme color, thinking mode, temperature, token tracking |
| `lib/providers/group_provider.dart` | Group state, batch parallel replies, _runGroupToolLoop, simulator mode |
| `lib/providers/memory_provider.dart` | Riverpod state for long-term/base memory, agent change listener |
| `lib/providers/agent_provider.dart` | Agent CRUD state |
| `lib/services/tool_executor.dart` | 6-tool execution logic, execution logs, duplicate name check |
| `lib/screens/onboarding_screen.dart` | 3-page wizard: welcome image → theme/language → API config |
| `lib/screens/group_chat_screen.dart` | Group chat UI: multi-bubble, long-press menu, multi-select, memory panel, tool logs |
| `lib/screens/settings_screen.dart` | Settings: provider/model dropdown/thinking/temperature/theme/language |
| `lib/screens/memory_screen.dart` | Memory management (short-term/long-term/base tabs) |
| `lib/screens/agent_create_screen.dart` | Agent create/edit form (with persona placeholder quick-insert buttons) |
| `lib/screens/group_create_screen.dart` | Group creation (multi-select Agents + simulator mode toggle) |
| `lib/theme/app_theme.dart` | Material 3 design tokens & ThemeData (spacing/radii/shadows/animations) |
| `lib/l10n/app_localizations.dart` | Chinese-English bilingual localization |
| `lib/services/encryption_service.dart` | XOR + SHA-256 encryption/decryption |
| `lib/services/locale_service.dart` | IP detection + language preference persistence |
| `lib/services/notification_service.dart` | Local notification scheduling |
| `lib/services/plan_service.dart` | Planned message persistence & triggering |
| `lib/services/model_service.dart` | Fetch model list from API |

---

> **Version**: v3.0  
> **Generated**: 2026-06-13  
> **Tech Stack**: Flutter 3.x / Dart / Riverpod / sqflite / Material 3 / DeepSeek API
