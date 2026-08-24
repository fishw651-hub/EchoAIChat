# 设计：同步状态修复、tab 动画修复、反馈追踪、AI 主动关心

> 日期：2026-07-28 · 状态：已获用户批准

## 1. 多端同步状态显示修复

- **"从未同步"误报**：`SyncState.lastSyncTime` 纯内存，重启丢失。`sync_service.dart` 已持久化 `last_sync_time` 到 SharedPreferences 但不回读。修复：`SyncNotifier` 初始化时回灌。
- **"未订阅"延迟**：订阅信息仅登录时与 6 小时定时器刷新。修复：设置页同步分区/账户页同步入口可见时触发 `refreshSubscription()`（60s 节流）；订阅中心购买返回后主动刷新。

## 2. Tab 栏大跨度切换动画修复

`home_screen.dart _switchTo()` 对任意跨度用 `animateToPage(250ms)`，跨多页时闪过中间页。修复：跨度 >1 用 `jumpToPage`，相邻保留动画。

## 3. 反馈追踪

服务器能力已备（`GET /api/v1/feedback` 返回本人反馈含 status/reply；admin 回复置"已回复"）。客户端新增：

- 设置页"意见反馈"下方"反馈追踪"入口 → `feedback_track_screen.dart`
- 列表：分类、摘要、时间、状态徽章（待处理/处理中/已回复/已关闭），已回复展开显示开发者回复，下拉刷新
- `FeedbackService.listMine()`；服务器确认 ListMine 倒序返回 status/reply

## 4. AI 主动关心（客户端触发 + 服务器正常计费）

### 4.1 配置
- Agent 新字段：`proactiveCareEnabled`（默认关）、`proactiveCareDailyLimit`（默认 1，1–5）、`proactiveCareMinIntervalHours`（默认 3，1–12）。仅 realInfoEnabled 时可配
- 创建/编辑智能体界面新增"主动关心"分区；DB 28→29；同步 payload 补字段

### 4.2 触发
- 窗口默认 8:00–20:00，按画像 habits 作息微调，解析失败回退默认
- 条件：窗口内 ∧ 距上次聊天 ≥ 最小间隔 ∧ 今日已发 < 每日上限 ∧ 最后一条不是未回复的主动关心消息
- 每条消耗 1 次真实回复配额 + token；配额不足静默跳过

### 4.3 保活（Android）
- `android_alarm_manager_plus` 后台定时（窗口期每 30 分钟 + 窗口开始精确闹钟），后台 isolate：检查 → 中继生成 → 写 SQLite → 弹通知
- 前台 15 分钟定时器补充
- 已知边界：国内 ROM 杀后台无法 100% 保证，引导用户开自启动

### 4.4 通知（仿微信）
- `flutter_local_notifications` MessagingStyle：大图标=智能体头像（默认头像兜底）、标题=名字、内容=全文
- 点击 → 打开对应智能体聊天页（payload agent id，main.dart 路由）

### 4.5 权限
开启开关时依次请求：通知权限（Android 13+）、忽略电池优化、引导自启动设置。拒绝仍可用但提示后果。
