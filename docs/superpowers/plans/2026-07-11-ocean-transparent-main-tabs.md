# 海洋通透主界面美化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Flutter 客户端的五个主 Tab 统一为清晰、通透且支持深浅色模式的海洋视觉风格。

**Architecture:** 以 `AppTheme` 的 Material 3 主题令牌为唯一视觉基础，页面仅从 `ColorScheme` 获取颜色。主导航在 `HomeScreen` 统一处理；首页、列表页、网络和账户页在各自现有组件内更新表面层级、间距和状态展示，不调整数据读取与导航行为。

**Tech Stack:** Flutter、Dart、Material 3、Riverpod、flutter_test。

## Global Constraints

- 不增加第三方 UI、字体或动画依赖。
- 不修改服务层、provider、数据库、API、路由及本地化数据。
- 保留现有点击、长按、下拉刷新、加载和页面跳转行为。
- 新增样式必须从 `ColorScheme` 派生，以支持浅色与深色模式。
- 使用 `withValues(alpha: ...)`，不使用已弃用的 `withOpacity`。
- `flutter analyze` 不得产生 error，并运行 `flutter test`。

---

## File Structure

- `lib/theme/app_theme.dart`：主界面共享的表面、卡片、按钮和导航主题令牌。
- `lib/screens/home_screen.dart`：移动底部栏与桌面侧栏的视觉层次。
- `lib/screens/home_tab_screen.dart`：首页顶部快捷信息和会话列表的分组间距。
- `lib/widgets/contact_list.dart`：智能体卡片列表和空状态。
- `lib/widgets/group_list_tab.dart`：群聊卡片列表和空状态。
- `lib/screens/network_content_tab.dart`：网络 Tab 的标题区、筛选器与内容表面。
- `lib/screens/account_screen.dart`：账户信息、额度和操作分组。

### Task 1: 完善全局海洋主题

**Files:**
- Modify: `lib/theme/app_theme.dart`

**Interfaces:**
- Produces: 更一致的 `ThemeData`，供所有 `Theme.of(context).colorScheme` 消费者使用。

- [ ] **Step 1: 更新主题表面与组件主题**

在 `_buildTheme` 中调整 `scaffoldBackgroundColor`、`cardTheme`、`appBarTheme`、`navigationBarTheme`、`listTileTheme`、`dividerTheme` 和按钮主题；所有色值从 `scheme` 派生，卡片使用 16 至 20dp 圆角、细描边与弱表面色。

- [ ] **Step 2: 格式化主题文件**

Run: `dart format lib/theme/app_theme.dart`
Expected: 文件格式化成功。

- [ ] **Step 3: 验证静态分析**

Run: `flutter analyze lib/theme/app_theme.dart`
Expected: `No issues found!` 或仅已有 info/warning，且无 error。

### Task 2: 美化主导航壳

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `AppTheme` 令牌和 `ColorScheme`。
- Produces: 保持五个 Tab 与 `_switchTo(int)` 行为不变的海洋通透导航。

- [ ] **Step 1: 更新移动端底部导航**

为底栏增加左右外边距、圆角顶部表面与弱阴影，保留安全区；将当前入口渲染为 `primaryContainer` 基础上的胶囊，图标和文字使用 `onPrimaryContainer`，避免硬编码白色。

- [ ] **Step 2: 更新桌面端侧栏**

为侧栏品牌区加入弱色背景，导航项使用统一圆角、内边距和 `primaryContainer` 选中态；不改变 220px 宽度、入口数量、图标和 `IndexedStack`。

- [ ] **Step 3: 格式化并验证**

Run: `dart format lib/screens/home_screen.dart && flutter analyze lib/screens/home_screen.dart`
Expected: 格式化成功且没有 analyzer error。

### Task 3: 美化首页与会话入口

**Files:**
- Modify: `lib/screens/home_tab_screen.dart`
- Modify: `lib/widgets/conversation_list.dart`

**Interfaces:**
- Consumes: 现有最近会话数据和 `ConversationListWidget`。
- Produces: 不改变会话查询和跳转的首页快捷区与会话列表分组。

- [ ] **Step 1: 调整首页顶部区块**

将 `SliverAppBar` 的顶部信息包入统一留白区域；余额卡与最近会话卡采用低饱和表面、描边和一致圆角，保留原有点击跳转与动态额度数据。

- [ ] **Step 2: 调整会话列表表面**

在 `ConversationListWidget` 中为会话列表项目和空状态接入与主 Tab 一致的卡片表面、间距、头像和文字层级，不修改消息预览或点击逻辑。

- [ ] **Step 3: 格式化并验证**

Run: `dart format lib/screens/home_tab_screen.dart lib/widgets/conversation_list.dart && flutter analyze lib/screens/home_tab_screen.dart lib/widgets/conversation_list.dart`
Expected: 格式化成功且没有 analyzer error。

### Task 4: 美化智能体与群聊列表

**Files:**
- Modify: `lib/widgets/contact_list.dart`
- Modify: `lib/widgets/group_list_tab.dart`

**Interfaces:**
- Consumes: 现有 agent/group provider、创建页和聊天页跳转。
- Produces: 保持创建、进入、编辑、删除、长按菜单不变的卡片式列表。

- [ ] **Step 1: 更新智能体页**

为标题区创建入口设置 tonal 按钮或带容器的图标按钮；列表使用 `ListView` 外层留白和无分隔线卡片；空状态使用统一的图标容器、说明和主按钮。

- [ ] **Step 2: 更新群聊页**

以相同尺寸、圆角、描边和文字层级更新群聊列表及空状态，保留 `GroupAvatar`、排序和全部长按操作。

- [ ] **Step 3: 格式化并验证**

Run: `dart format lib/widgets/contact_list.dart lib/widgets/group_list_tab.dart && flutter analyze lib/widgets/contact_list.dart lib/widgets/group_list_tab.dart`
Expected: 格式化成功且没有 analyzer error。

### Task 5: 美化网络和账户主 Tab

**Files:**
- Modify: `lib/screens/network_content_tab.dart`
- Modify: `lib/screens/account_screen.dart`

**Interfaces:**
- Consumes: 现有网络列表状态、认证状态和账户操作回调。
- Produces: 保持数据加载、下载、登录、订阅、同步与退出行为不变的分组化主页面。

- [ ] **Step 1: 更新网络页标题和内容容器**

将类型切换控件和右上角操作组合为一致的通透表面；为列表与加载、错误、空状态使用统一页面留白和卡片层级，不改变分页与下载调用。

- [ ] **Step 2: 更新账户页信息分组**

为用户资料、余额、订阅/同步入口和底部操作设置统一间距及卡片层级；保留退出操作错误色和所有既有回调。

- [ ] **Step 3: 格式化并验证**

Run: `dart format lib/screens/network_content_tab.dart lib/screens/account_screen.dart && flutter analyze lib/screens/network_content_tab.dart lib/screens/account_screen.dart`
Expected: 格式化成功且没有 analyzer error。

### Task 6: 全量验证

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/home_tab_screen.dart`
- Modify: `lib/widgets/conversation_list.dart`
- Modify: `lib/widgets/contact_list.dart`
- Modify: `lib/widgets/group_list_tab.dart`
- Modify: `lib/screens/network_content_tab.dart`
- Modify: `lib/screens/account_screen.dart`

**Interfaces:**
- Consumes: 所有前序视觉改动。
- Produces: 已验证的五个主 Tab 美化结果。

- [ ] **Step 1: 执行全量静态分析**

Run: `flutter analyze`
Expected: 0 errors。

- [ ] **Step 2: 执行现有测试**

Run: `flutter test`
Expected: 所有现有测试通过。

- [ ] **Step 3: 检查最终差异**

Run: `git diff --check && git diff --stat`
Expected: 无空白错误，差异仅涉及计划列出的视觉文件和文档。
