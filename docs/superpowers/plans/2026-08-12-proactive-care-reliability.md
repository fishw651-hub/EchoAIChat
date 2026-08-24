# 主动关心可靠性优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让主动关心在前台、后台 isolate 和失败恢复场景下保持单发、可恢复、正确计数且低耗电。

**Architecture:** 把发送资格与占用状态放进 SQLite 事务，生成器只消费 claim 并提交结果。Android 调度器退化为单个 one-shot alarm，根据启用状态和清醒窗口自我续排。

**Tech Stack:** Flutter/Dart、sqflite、SharedPreferences、android_alarm_manager_plus、flutter_test。

## Global Constraints

- 所有聊天和记忆查询必须按 `agent_id` 过滤。
- 新代码使用 `withValues(alpha:)`，不得新增 `withOpacity()`。
- 群聊不参与主动关心。
- 配额不足静默跳过；生成或提交失败必须退款。
- 不修改或回滚工作区中与本任务无关的现有改动。

---

### Task 1: 回复判定与调度纯逻辑

**Files:**
- Modify: `test/proactive_care_service_test.dart`
- Modify: `lib/services/proactive_care_service.dart`
- Modify: `lib/services/proactive_care_alarm.dart`

**Interfaces:**
- Produces: `ProactiveCarePolicy.hasUserReplied(...) -> bool`
- Produces: `ProactiveCareAlarmScheduler.nextCheckTime(...) -> DateTime`

- [x] 写失败测试：`pending_since` 后出现用户消息时视为已回复，最后一条 AI 消息不影响结论。
- [x] 实现最小纯函数。
- [x] 写 alarm 下一次时间计算测试。

### Task 2: SQLite 原子 claim 与事务提交

**Files:**
- Modify: `lib/services/database_service.dart`
- Modify: `lib/services/database_service_web.dart`（仅在平台实现需要对应入口时）
- Modify: `lib/services/proactive_care_service.dart`
- Test: `test/proactive_care_service_test.dart`

**Interfaces:**
- Produces: `DatabaseService.claimProactiveCare(...) -> ProactiveCareClaim?`
- Produces: `DatabaseService.commitProactiveCare(...) -> bool`
- Produces: `DatabaseService.releaseProactiveCareClaim(...) -> void`

- [x] 写重复 claim、过期 claim 和 baseline 改变的失败测试。
- [x] 数据库版本升至 34，创建 `proactive_care_state`。
- [x] 在事务内实现 eligibility、claim、提交和释放。
- [x] 将发送执行器改为消费 claim，移除 SharedPreferences pending/count 的权威职责。

### Task 3: 配额精确补偿

**Files:**
- Modify: `lib/services/quota_service.dart`
- Modify: `lib/services/proactive_care_service.dart`
- Test: `test/proactive_care_service_test.dart` 或新增定向配额测试

**Interfaces:**
- Produces: `QuotaService.refund(QuotaType type, {int? subscriptionId})`

- [x] 写退款请求包含 `subscription_id` 的失败测试。
- [x] 保存 `consume()` 返回的 `QuotaUsage`。
- [x] 用 `try/finally` 覆盖生成异常、空响应、claim 失效和落库异常；仅成功提交不退款。

### Task 4: Alarm 生命周期

**Files:**
- Modify: `lib/services/proactive_care_alarm.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/agent_create_screen.dart`
- Modify: `lib/providers/auth_provider.dart`

**Interfaces:**
- Produces: `ProactiveCareAlarmScheduler.sync()`

- [x] 删除全天 periodic alarm 注册，改成一个 one-shot alarm。
- [x] 启动、保存、删除后同步 alarm；无启用智能体时取消。
- [x] 注销时取消 alarm，alarm 回调结束后续排。

### Task 5: 验证

**Files:**
- Test: `test/proactive_care_service_test.dart`
- Test: 受影响的配额/数据库测试

- [ ] 运行 `flutter test test/proactive_care_service_test.dart`。
- [ ] 运行相关定向测试。
- [ ] 运行 `flutter analyze`，要求 0 errors。
- [x] 检查 `git diff`，确认没有覆盖用户已有改动。

> 验证阻塞记录：Flutter SDK 的 `bin/cache/lockfile` 为无进程占用的零字节文件，但删除该 SDK 外部文件的审批请求于 2026-08-12 因审批服务 503 被拒。定向 `dart analyze`、`dart format` 和 Flutter 测试均在该锁上超时，尚未取得可运行的测试结果。
