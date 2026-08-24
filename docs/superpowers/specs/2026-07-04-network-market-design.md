# 网络智能体/群聊市场 设计文档

**日期**：2026-07-04
**状态**：已确认，进入实现

## 目标

在客户端"新建智能体"和"新建群聊"页面 AppBar 右侧增加"网络市场"和"草稿箱"入口，用户可上传/下载/搜索智能体与群聊。管理员在后台审核，通过后才在市场公开。支持预设+自由混合标签。

## 核心决策

| 决策点 | 选择 |
|---|---|
| 审核流程 | 先审后公开（pending → approved） |
| 标签机制 | 混合：管理员预设标签库 + 用户自由输入 |
| 群聊导出范围 | 仅元数据 + 成员设定（不含消息/记忆） |
| 上传者权限 | 可编辑 + 可下架（编辑后 Status 重置为 pending） |
| 市场入口位置 | AppBar 右侧图标按钮 |
| 草稿箱 | 本地 SQLite（draft_uploads 表） |
| 下载副本关系 | 独立副本，不随云端更新 |
| 搜索范围 | 名称 + 描述 + 标签全文搜索 |
| 标签筛选逻辑 | OR（任一匹配即返回） |
| 旧 data/Agent.json | 丢弃，从空开始 |

## 架构方案

**方案 B**：新建独立的 NetworkAgent / NetworkGroup 表，与现有 UserAgent（私有同步）完全隔离。

## 数据模型

### 服务端新增表

#### NetworkAgent
```
ID, UploaderID, UploaderName, Name, Gender, Description,
Persona(AES-GCM 加密), OpeningLine(加密), Worldview(加密),
AvatarColor, AvatarPath, ChatBackground,
Tags([]string), Status(pending/approved/rejected/taken_down),
RejectReason, Version, DownloadCount,
CreatedAt, UpdatedAt, ReviewedAt, ReviewerID
```

#### NetworkGroup
```
ID, UploaderID, UploaderName, Name, Description,
GroupPersona(加密), WorldSetting(加密),
SpeechMode, IsSimulatorMode, AvatarColor,
Tags([]string), Status, RejectReason, Version, DownloadCount,
MembersJSON(加密, 成员设定数组),
CreatedAt, UpdatedAt, ReviewedAt, ReviewerID
```

#### MembersJSON 结构
```json
[{"name":"...","gender":"...","description":"...",
  "persona":"...","avatar_color":0,"avatar":"data:image/...;base64,...",
  "role":"member"}]
```

#### 预设标签库
存 SystemConfig 表，键 `network_preset_tags`，值逗号分隔。

### 客户端新增表（v20 → v21）

```sql
CREATE TABLE draft_uploads (
  id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT,
  data TEXT NOT NULL, cover_color INTEGER,
  updated_at INTEGER, created_at INTEGER
);
```

## 服务端 API

### 用户端（AuthRequired）

| 方法 | 路径 |
|---|---|
| GET | `/api/v1/network/tags` |
| GET | `/api/v1/network/agents?q=&tags=&page=&sort=` |
| GET | `/api/v1/network/agents/:id` |
| POST | `/api/v1/network/agents/:id/download` |
| GET | `/api/v1/network/groups?...` |
| GET | `/api/v1/network/groups/:id` |
| POST | `/api/v1/network/groups/:id/download` |
| GET | `/api/v1/network/my/agents` |
| GET | `/api/v1/network/my/groups` |
| POST | `/api/v1/network/agents` |
| POST | `/api/v1/network/groups` |
| PUT | `/api/v1/network/agents/:id` |
| PUT | `/api/v1/network/groups/:id` |
| DELETE | `/api/v1/network/agents/:id` (下架) |
| DELETE | `/api/v1/network/groups/:id` |

### 管理端（AuthRequired + AdminRequired）

| 方法 | 路径 |
|---|---|
| GET | `/api/v1/admin/network/agents?status=` |
| GET | `/api/v1/admin/network/groups?status=` |
| POST | `/api/v1/admin/network/agents/:id/approve` |
| POST | `/api/v1/admin/network/agents/:id/reject` |
| POST | `/api/v1/admin/network/groups/:id/approve` |
| POST | `/api/v1/admin/network/groups/:id/reject` |
| PUT | `/api/v1/admin/network/agents/:id` |
| DELETE | `/api/v1/admin/network/agents/:id` |
| GET/PUT | `/api/v1/admin/network/preset-tags` |

### 关键规则
- 编辑后 Status 重置为 pending，Version+1，DownloadCount 保留
- 下载计数用 IncrementField 原子操作
- 头像走文件上传接口，存 /uploads/network_avatars/

## 客户端

### 新增 Screen
- NetworkMarketScreen（市场列表）
- NetworkAgentDetailScreen / NetworkGroupDetailScreen
- NetworkUploadScreen（含现写/从现有选择两种模式）
- DraftBoxScreen
- MyUploadsScreen

### 新增 Service
- NetworkService（HTTP 客户端）
- GroupExportService（群聊序列化/反序列化）
- 扩展 AgentExportService

### AppBar 入口
agent_create_screen.dart 和 group_create_screen.dart 的 AppBar actions：
- 网络市场图标（cloud_outlined）
- 草稿箱图标（drafts_outlined）

### 群聊上传面板内嵌创建智能体
"添加成员"底部 sheet：[选择现有] / [新建智能体]，新建的同时保存到本地 agents 表。

## 管理后台

替换 admin/index.html 的 agents section 为"网络内容管理"，三个子 Tab：
- 智能体市场
- 群聊市场
- 预设标签库

状态筛选：全部 / 待审核(N) / 已通过 / 已拒绝 / 已下架。
操作按状态变化：通过、拒绝（必填理由）、编辑（仅名称/描述/标签/强制下架）、删除、恢复。

管理员不可改核心内容（persona 等），保护作者原创性。

## 删除的旧代码

服务端：
- models/agent.go
- handlers/agent.go
- handlers/admin.go 的 ListAgents/CreateAgent/UpdateAgent/DeleteAgent
- routes.go 的旧 agent 路由
- data/Agent.json

管理后台：
- admin/index.html 的 agents section 表格/模态框
- admin/js/app.js 的 agent 相关函数

## 保留不动

- UserAgent（用户私有同步）
- 现有 agent_export_service.dart 的导入导出（扩展，不替换）
