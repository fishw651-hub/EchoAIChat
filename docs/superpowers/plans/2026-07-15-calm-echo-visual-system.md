# 回响「静谧回响」完整视觉系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 A「静谧回响」完整应用到 Flutter 首页、会话、聊天、人格画像和记忆管理界面。

**Architecture:** 保留现有 Riverpod、导航和数据库逻辑，在 `AppTheme` 上建立统一设计令牌，并通过小型通用 Widget 让首页、私聊和群聊共享表面与气泡样式。页面仅调整布局与展示，不改变消息归属、持久化和同步行为。

**Tech Stack:** Flutter 3.41+、Material 3、Riverpod 2.x、Flutter Widget Test、Widget Previewer

## Global Constraints

- 新代码使用 `withValues(alpha:)`，禁止 `withOpacity()`。
- 新代码颜色来自 `Theme.of(context).colorScheme`，禁止 `Colors.white`/`Colors.black`。
- 数据库和消息查询继续强制按 `agent_id` 隔离。
- 触控区域最低 44dp，动效使用 150–300ms。
- 响应式判断基于 `LayoutBuilder` 或可用宽度，不按设备类型判断。
- 不提交、不创建分支、不回滚工作区既有修改。

---

### Task 1: 视觉令牌与通用表面

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Create: `lib/widgets/echo_visual_surface.dart`
- Create: `test/echo_visual_surface_test.dart`

**Interfaces:**
- Produces: `AppTheme.echoSeed`、`EchoPanel`、`EchoSectionHeader`、`EchoBubbleSurface`。
- Consumes: Flutter `ColorScheme` 与现有 `ResponsiveLayout.bubbleMaxWidth` 返回值。

- [ ] **Step 1: 写失败测试**：验证品牌种子色、面板圆角、AI/用户气泡方向和 44dp 触控约束。
- [ ] **Step 2: 运行红灯**：`flutter test test/echo_visual_surface_test.dart`，预期因组件不存在失败。
- [ ] **Step 3: 最小实现**：新增通用表面并清理 `AppTheme` 的乱码注释和高饱和主题逻辑。
- [ ] **Step 4: 运行绿灯**：同一命令预期 PASS。
- [ ] **Step 5: 复核**：运行 `dart format lib/theme/app_theme.dart lib/widgets/echo_visual_surface.dart test/echo_visual_surface_test.dart`。

### Task 2: 首页人格卡与会话列表

**Files:**
- Modify: `lib/widgets/home_profile_summary_card.dart`
- Modify: `lib/widgets/echo_conversation_tile.dart`
- Modify: `lib/widgets/conversation_list.dart`
- Modify: `lib/screens/home_tab_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `test/home_profile_summary_card_test.dart`
- Modify: `test/echo_conversation_tile_test.dart`

**Interfaces:**
- Consumes: `EchoPanel`、`EchoSectionHeader`、现有 `AgentAvatar`/`GroupAvatar`。
- Produces: 首页画像主卡、紧凑额度胶囊、微信式扁平会话列表、统一浮动导航。

- [ ] **Step 1: 写失败测试**：断言正确中文、“由 N 条观察构成”、可点击语义和会话分隔层级。
- [ ] **Step 2: 运行红灯**：`flutter test test/home_profile_summary_card_test.dart test/echo_conversation_tile_test.dart`。
- [ ] **Step 3: 最小实现**：重排首页首屏，修复相关乱码文案，取消逐项卡片阴影。
- [ ] **Step 4: 运行绿灯**：相关测试预期 PASS。
- [ ] **Step 5: 响应式检查**：Widget 测试分别以 390dp 和 1024dp 宽度 pump，预期无 overflow 异常。

### Task 3: 私聊与群聊统一气泡

**Files:**
- Modify: `lib/screens/chat_screen.dart`
- Modify: `lib/screens/group_chat_screen.dart`
- Create: `test/echo_chat_surface_test.dart`

**Interfaces:**
- Consumes: `EchoBubbleSurface`。
- Produces: 私聊和群聊一致的用户/AI 气泡、边框、圆角、阴影与 hover/选中状态。

- [ ] **Step 1: 写失败测试**：验证用户气泡右下短角、AI 气泡左下短角、选中态边框和最大宽度。
- [ ] **Step 2: 运行红灯**：`flutter test test/echo_chat_surface_test.dart`。
- [ ] **Step 3: 最小实现**：替换两处重复 `BoxDecoration`，保留原消息内容、图片、推理和操作回调。
- [ ] **Step 4: 运行绿灯**：相关测试预期 PASS。
- [ ] **Step 5: 静态检查**：`flutter analyze lib/screens/chat_screen.dart lib/screens/group_chat_screen.dart` 无 error。

### Task 4: 人格画像与记忆管理

**Files:**
- Modify: `lib/widgets/profile_mindmap_widget.dart`
- Modify: `lib/screens/memory_screen.dart`
- Create: `test/memory_visual_hierarchy_test.dart`

**Interfaces:**
- Consumes: `EchoPanel`、`EchoSectionHeader` 和 `AppTheme` 令牌。
- Produces: 统一画像头部、分类节点、记忆分组操作区与空状态。

- [ ] **Step 1: 写失败测试**：断言画像正确中文标题、观察数量、可编辑提示和记忆页四个标签。
- [ ] **Step 2: 运行红灯**：`flutter test test/memory_visual_hierarchy_test.dart`。
- [ ] **Step 3: 最小实现**：替换乱码标题与结构性 emoji，收敛卡片、Chip 和危险操作层级。
- [ ] **Step 4: 运行绿灯**：相关测试预期 PASS。
- [ ] **Step 5: 格式化**：格式化本任务修改文件。

### Task 5: Preview 与全量验证

**Files:**
- Create: `lib/widgets/echo_visual_preview.dart`
- Modify: `test/app_theme_test.dart`

**Interfaces:**
- Consumes: 所有通用视觉组件。
- Produces: 浅色/深色、手机宽度的视觉预览入口。

- [ ] **Step 1: 新增 Preview**：用 `@Preview` 展示人格卡、会话项和两类气泡，不引用原生插件。
- [ ] **Step 2: 主题测试**：验证浅色/深色表面对比与导航高度。
- [ ] **Step 3: 定向验证**：运行所有本轮新增和修改的 Widget 测试。
- [ ] **Step 4: 全量验证**：运行 `flutter analyze` 与 `flutter test`。
- [ ] **Step 5: 自检**：确认无新增硬编码白/黑、无 `withOpacity()`、无数据库或同步逻辑改动。

