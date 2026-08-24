# 设备感知与选择性智能体同步设计

**日期**：2026-07-15  
**状态**：设计已确认，待实施计划  
**范围**：Flutter 移动端与 Web、Go API、多端同步协议与同步管理界面

## 1. 目标

本次改造解决三个问题：

1. 每个原生安装和浏览器配置文件都能被稳定识别为独立设备。
2. 用户可以在账号级选择“全部智能体”或“指定智能体”持续同步。
3. 用户可以临时选择智能体执行一次双向同步，且不修改长期同步策略。

智能体同步必须覆盖智能体的创建、编辑、删除，以及其私聊记录、短期记忆、长期记忆、基础记忆和计划消息。不同智能体的数据不得混入同一同步范围。

## 2. 已确认的产品决策

### 2.1 设备识别

- 每个原生应用安装实例是一台独立设备。
- 每个浏览器配置文件是一台独立设备；同一电脑上的 Chrome、Edge、Firefox 分别显示。
- Web 设备 ID 使用浏览器本地持久化 UUID，不使用不透明硬件指纹。
- 设备在登录成功、恢复登录和应用启动时自动注册，不依赖用户打开设备管理页。
- 每个同步 HTTP 请求和 WebSocket 连接都携带来源设备 ID。

### 2.2 账号级同步范围

账号保存一份统一的同步策略，所有设备共用：

- `all`：同步所有现有智能体，以及以后新创建的智能体。
- `selected`：只同步用户勾选的智能体；新建智能体默认不参与，直到用户手动勾选。

从 `selected` 中取消一个智能体只停止后续同步，不删除本机、云端或其他设备已有数据。

### 2.3 同步方式

- 持续实时同步：替代现有“100% 同步”，遵循账号级范围。
- 立即同步：按账号级范围执行一次双向合并。
- 单次同步：临时勾选智能体执行一次双向合并，不修改账号级范围和持续同步开关。

### 2.4 冲突规则

- 同一条记录在多个设备被修改时采用 Last-Write-Wins。
- 以规范化的 `updated_at` / `sync_updated_at` 比较，较新版本覆盖较旧版本。
- 同步执行前展示上传、下载、覆盖、删除的预览摘要。
- 删除通过墓碑传播；只有整个同步运行成功后才清理已确认墓碑。

## 3. 同步数据闭包

选择一个智能体时，同步模块构建以下完整数据闭包：

| 本地表 | 范围条件 | 行为 |
|---|---|---|
| `agents` | `id IN selected_agent_ids` | 创建、编辑、删除智能体 |
| `chat_messages` | `agent_id IN selected_agent_ids` | 私聊历史 |
| `short_term_messages` | `agent_id IN selected_agent_ids` | 短期上下文 |
| `long_term_memories` | `agent_id IN selected_agent_ids AND group_id IS NULL` | 长期记忆 |
| `base_memories` | `agent_id IN selected_agent_ids AND group_id IS NULL` | 基础记忆 |
| `planned_messages` | `agent_id IN selected_agent_ids AND group_id IS NULL` | 计划消息 |

群聊表、用户全局画像和供应商配置不隐式跟随“指定智能体”运行。`all` 模式保持现有全账号同步能力；后续如需细分群聊或全局数据，再设计独立分类，不把它们猜测性地绑定到某个智能体。

智能体删除时，其智能体墓碑和闭包内子记录墓碑一并进入同步计划。未选择智能体的项目和墓碑不得上传、下载或应用。

## 4. 深模块与接口

### 4.1 `SyncPolicy` 模块

账号级策略由服务器持久化，接口只暴露策略读取和原子更新：

```text
SyncPolicy
  scope_mode: all | selected
  selected_agent_ids: string[]
  realtime_enabled: bool
  version: integer
  updated_at: timestamp
```

约束：

- `scope_mode=selected` 时允许列表为空，此时持续同步不传输智能体数据。
- `scope_mode=all` 时忽略 `selected_agent_ids`。
- 策略更新使用版本号做乐观并发控制，防止两台设备互相覆盖选择列表。
- 本地新建但尚未上传的 UUID 可以先加入选择列表，随后同步创建。

### 4.2 `SyncScope` 模块

客户端只向同步执行器传递一个范围：

```text
accountPolicy() -> all 或账号级 selected
oneShot(agentIds) -> 临时 selected
```

表过滤、数据闭包、墓碑过滤和预览统计全部隐藏在该模块内部，界面不得自行拼装表查询。

### 4.3 `SyncRun` 模块

一次同步运行包含：

```text
run_id
user_id
source_device_id
scope_snapshot
policy_version
mode: realtime | immediate | one_shot
status
preview_counts
started_at / completed_at
```

一次运行要么完成所有范围内表的合并，要么保留本地快照、墓碑和失败状态供重试。不得在部分表失败时报告整体成功。

## 5. 设备身份设计

### 5.1 客户端设备描述

新增平台中立的设备描述接口：

```text
DeviceIdentity
  id
  display_name
  client_kind: native | web
  platform
  browser
```

- 原生端通过条件导入返回系统平台和安装级 UUID。
- Web 端使用 `localStorage` UUID，并通过 `navigator.userAgentData`、降级 User-Agent 解析浏览器和操作系统。
- `SyncDevicesScreen` 不再直接导入 `dart:io`，确保 Web 可运行。
- 用户可编辑显示名称，但 ID 不随名称变化。

### 5.2 注册与心跳

- 登录成功、会话自动恢复、应用启动后调用设备注册。
- 同步请求携带 `X-Device-ID`，服务器验证设备属于当前用户并刷新 `last_active_at`。
- WebSocket 查询参数携带 `device_id`，Hub 保存连接来源。
- 服务器向其他设备广播同步事件时排除来源设备，避免回环执行。
- 设备列表显示浏览器、操作系统、当前设备、最后活跃、最后同步时间。

## 6. 协议设计

保留旧 `/sync/all` 端点供旧客户端兼容，新客户端使用版本化接口：

```text
GET  /api/v1/sync/policy
PUT  /api/v1/sync/policy
POST /api/v1/sync/v2/preview
POST /api/v1/sync/v2/run
```

### 6.1 预览

客户端提交设备 ID、范围和本地摘要。服务器验证订阅、设备、策略版本和智能体 ID 格式，返回：

```text
preview_token
expires_at
upload_count
download_count
overwrite_local_count
overwrite_cloud_count
delete_count
conflict_count
```

### 6.2 执行

客户端携带短时 `preview_token` 执行。服务器拒绝范围、策略版本或设备身份已变化的预览，要求重新生成。

服务器必须在读取和写入两侧都按范围过滤，不能只依赖客户端过滤。响应携带最终合并项目、分表结果、服务器时间和新的策略版本。

## 7. 持续实时同步改造

现有 `FullSyncEnabled` 迁移为 `RealtimeEnabled`：

- 旧账号若已开启 100% 同步，升级后默认 `scope_mode=all` 且持续实时同步开启。
- 未开启的账号保留关闭状态，默认 `scope_mode=all`。
- `selected` 模式下 WebSocket 事件必须携带 `agent_id`；未选智能体事件不触发拉取。
- 策略变更广播给账号所有在线设备。
- 新增选择执行一次补齐同步；取消选择不发删除墓碑。
- 同智能体聊天锁显示具体来源设备，例如“Windows · Chrome 正在聊天”。

## 8. 客户端界面

同步管理页分为三部分：

1. **同步范围**
   - “全部智能体”与“指定智能体”分段选择。
   - 指定模式展示智能体多选列表、已选数量和新建智能体默认不同步提示。
2. **同步方式**
   - 持续实时同步开关。
   - “按当前范围立即同步”。
   - “单次同步”按钮，打开临时智能体选择器。
   - 执行前展示同步预览并二次确认。
3. **设备管理**
   - 展示浏览器、平台、角色、当前设备、最后活跃和最后同步。
   - 支持重命名、切换主设备和删除非当前设备。

持续同步开启但指定列表为空时不报错、不传输智能体数据，并在界面显示“尚未选择同步智能体”。

## 9. 本地数据库与兼容迁移

- 升级数据库版本，为缺少可靠更新时间的同步表补齐规范化更新时间。
- 修复旧自增表中仅为裸数字的 `client_id`，转换为设备命名空间或 UUID，防止不同设备 ID 碰撞。
- 已是 UUID 的智能体 ID 保持不变。
- 迁移前执行 WAL checkpoint；迁移失败不得删除原表或原记录。
- 服务端 `SyncSetting` 增加范围模式、选择列表、策略版本和实时同步字段，同时兼容读取旧 `FullSyncEnabled`。
- `Device` 增加客户端类型、浏览器和最后同步时间；现有设备记录允许首次心跳时补全。

## 10. 错误处理与安全

- 所有策略和同步接口继续要求订阅权限。
- 服务器按 `user_id` 隔离设备、策略、运行记录和同步数据。
- 服务器验证上传项目的 `agent_id` 位于本次范围内。
- 单次选择数量和请求体大小有限制，拒绝异常大范围。
- 同步开始前创建本地安全快照；失败后保留快照和墓碑。
- 设备身份无效返回明确错误，客户端重新注册后可重试。
- 不记录聊天正文、记忆正文、API Key 或其他敏感内容到同步运行日志。

## 11. 测试与验收

### 11.1 Flutter

- Chrome、Edge 和 Firefox 的浏览器配置文件生成不同设备 ID。
- 相同浏览器配置文件刷新后保持同一 ID。
- Web 同步设备页不依赖 `dart:io`。
- `all` 模式自动包含新建智能体。
- `selected` 模式不自动包含新建智能体。
- 选择一个智能体时只生成其六表数据闭包。
- 未选智能体的数据和墓碑不进入请求，也不应用响应。
- 单次同步不修改账号级策略。
- 部分表失败时不清理墓碑，不更新成功时间。

### 11.2 Go

- 设备按 `(user_id, device_id)` 唯一区分并更新心跳。
- 策略更新执行版本冲突检查。
- 服务端对上传和下载进行双向范围过滤。
- LWW 正确选择较新记录。
- 预览 token 过期、策略变化或设备变化时拒绝执行。
- WebSocket 广播排除来源设备并过滤未选智能体。
- 旧 `FullSyncEnabled` 数据正确迁移。

### 11.3 端到端验收

1. 同一电脑的 Chrome 和 Edge 显示为两个设备。
2. 账号选择 A、B 后，手机和网页都只持续同步 A、B；C 保持本地独立。
3. `all` 模式下创建 D，其他设备自动获得 D 及其后续数据。
4. `selected` 模式下创建 E，其他设备不会获得 E；勾选 E 后补齐同步。
5. 单次选择 C 后完成双向合并，但长期策略仍为 A、B。
6. 两台设备修改同一智能体时，预览显示冲突，执行后较新版本胜出。
7. 任一同步失败后本地数据、云端数据和墓碑均不会被误清空。

## 12. 非目标

- 不实现字段级 CRDT 或多人实时协同编辑。
- 不使用硬件指纹跨浏览器识别同一物理电脑。
- 不因取消选择而自动清理其他设备或云端的历史数据。
- 本次不新增群聊、用户画像和供应商配置的细粒度选择器。
