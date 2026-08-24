# Creation Flow UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将创建智能体与创建群聊重构为单页分组界面，前置 AI 快捷入口、置顶群聊类型选择，并为两页保留清晰可见的“创建并上传到网络市场”路径。

**Architecture:** 继续使用现有 `AgentCreateScreen`、`GroupCreateScreen`、Riverpod provider 和 `NetworkUploadScreen`。新增一个只负责视觉分组与底部完成操作的轻量共享组件文件；两个页面保留各自控制器、保存、OCR、权限和导航逻辑，避免数据层改动。

**Tech Stack:** Flutter 3.41+、Dart 3.11、Material 3、Riverpod 2.x、flutter_test。

## Global Constraints

- 新代码使用 `withValues(alpha:)`，不使用 `withOpacity()`。
- 颜色全部来自 `Theme.of(context).colorScheme`，不新增硬编码 `Colors.white`/`Colors.black`。
- 手机端保持单列滚动，交互触达区域至少 44dp。
- 不修改 `Agent`、`GroupChat`、数据库 schema 和 provider 对外接口。
- 创建后跳转、网络审核、网络来源限制和现有错误语义保持不变。
- `flutter analyze` 必须 0 errors。

---

### Task 1: 创建页共享视觉组件

**Files:**
- Create: `lib/widgets/creation_form_section.dart`
- Create: `test/creation_form_section_test.dart`

**Interfaces:**
- Produces: `CreationFormSection`，用于显示标题、说明、尾部操作与内容。
- Produces: `CreationQuickActions`，用于两个等宽的快捷创建入口。
- Produces: `CreationSubmitActions`，用于一个本地主按钮和一个带云图标的上传按钮，并统一 loading/disabled 状态。

- [ ] **Step 1: 写失败的 widget 测试**

测试应断言：分组标题与说明可见；快捷入口都可点击；提交区显示本地创建和“创建并上传到网络市场”；loading 时两个按钮均禁用且显示进度。

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/creation_form_section_test.dart`
Expected: FAIL，因为 `creation_form_section.dart` 和对应组件尚不存在。

- [ ] **Step 3: 实现最小共享组件**

使用 Material 原生 `InkWell`/`FilledButton`/`OutlinedButton`，通过构造参数接收文案、图标、回调和 loading 状态，不承载业务状态。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `flutter test test/creation_form_section_test.dart`
Expected: PASS。

### Task 2: 重排创建智能体页面

**Files:**
- Modify: `lib/screens/agent_create_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/agent_create_screen_layout_test.dart`

**Interfaces:**
- Consumes: `CreationFormSection`、`CreationQuickActions`、`CreationSubmitActions`。
- Preserves: `_persistAgent`、`_save`、`_saveAndUpload`、OCR、头像、主动关心、删除与网络同步逻辑。

- [ ] **Step 1: 写失败的页面布局测试**

测试应断言：基础身份与核心设定默认可见；AI 帮我创建、从聊天导入可见；更多设置默认折叠；点击后显示世界观、真实信息、主动关心与聊天背景；底部同时存在本地创建和网络上传动作。

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/agent_create_screen_layout_test.dart`
Expected: FAIL，因为当前页面没有新分组 key、折叠区域和新上传文案。

- [ ] **Step 3: 重排页面并保留行为**

新增稳定 widget key；将头像、名称、描述放入身份区；AI 帮写和聊天导入放入快捷入口；人设与开场白放入核心设定；性别、世界观、聊天背景、真实信息、主动关心放入默认折叠的更多设置。使用 `CreationSubmitActions` 调用原有 `_save` 与 `_saveAndUpload`。

- [ ] **Step 4: 运行页面与共享组件测试确认 GREEN**

Run: `flutter test test/agent_create_screen_layout_test.dart test/creation_form_section_test.dart`
Expected: PASS。

### Task 3: 重排创建群聊并接通上传路径

**Files:**
- Modify: `lib/screens/group_create_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Create: `test/group_create_screen_layout_test.dart`

**Interfaces:**
- Consumes: `CreationFormSection`、`CreationQuickActions`、`CreationSubmitActions`。
- Produces: `_persistGroup({required bool requireOpeningLine}) -> Future<GroupChat?>`，供本地创建和创建并上传共享。
- Produces: `_saveAndUpload()`，携带 `localGroup` 打开 `NetworkUploadScreen(type: 'group')`。

- [ ] **Step 1: 写失败的页面交互测试**

测试应断言：普通群聊/模拟器类型选择位于首屏；普通模式显示成员区；切到模拟器隐藏成员区并显示世界设定；更多设置包含公开开场白；底部显示“创建并上传到网络市场”。

- [ ] **Step 2: 运行测试确认 RED**

Run: `flutter test test/group_create_screen_layout_test.dart`
Expected: FAIL，因为当前模式切换仍是弱化开关，且没有群聊创建并上传入口。

- [ ] **Step 3: 抽取共享保存并实现上传**

将创建逻辑抽为 `_persistGroup`，返回 provider 创建出的 `GroupChat`；普通保存后进入群聊；上传保存要求 `hasRequiredOpeningLine`，失败时展开更多设置并聚焦开场白；成功后将 `localGroup` 传给现有上传页。加入 `_saving` 防重复提交，并确保导入发言人只创建一次。

- [ ] **Step 4: 重排群聊页面**

身份基础和快捷入口置顶；使用 `SegmentedButton<bool>` 选择普通群聊/模拟器；普通区域显示发言规则、导入状态和成员；模拟器区域显示世界设定；群人格、公开开场白和记忆共用放入更多设置；底部使用统一提交组件。

- [ ] **Step 5: 运行页面测试确认 GREEN**

Run: `flutter test test/group_create_screen_layout_test.dart test/creation_form_section_test.dart`
Expected: PASS。

### Task 4: 回归验证与格式化

**Files:**
- Modify only files changed by Tasks 1-3 through formatting.

- [ ] **Step 1: 格式化**

Run: `dart format lib/widgets/creation_form_section.dart lib/screens/agent_create_screen.dart lib/screens/group_create_screen.dart lib/l10n/app_localizations.dart test/creation_form_section_test.dart test/agent_create_screen_layout_test.dart test/group_create_screen_layout_test.dart`
Expected: exit 0。

- [ ] **Step 2: 运行相关测试**

Run: `flutter test test/creation_form_section_test.dart test/agent_create_screen_layout_test.dart test/group_create_screen_layout_test.dart test/creation_provider_return_test.dart test/network_upload_payload_test.dart`
Expected: 全部 PASS。

- [ ] **Step 3: 静态分析**

Run: `flutter analyze`
Expected: 0 errors；已有 info/warnings 可记录但不得新增 error。

- [ ] **Step 4: 检查差异范围**

Run: `git diff -- lib/widgets/creation_form_section.dart lib/screens/agent_create_screen.dart lib/screens/group_create_screen.dart lib/l10n/app_localizations.dart test/creation_form_section_test.dart test/agent_create_screen_layout_test.dart test/group_create_screen_layout_test.dart`
Expected: 仅包含创建流程 UI、上传入口、文案和测试相关改动。
