# 表情入口与首页动态卡片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将表情图片入口改为大型正方形加号按钮，并为首页人格画像卡片加入性能友好的声纹、圆环和画像文案轮换。

**Architecture:** 表情入口保持在 `StickerPanel` 内，通过稳定 Key 和固定尺寸验证布局。首页动画拆为独立绘制组件，`HomeProfileSummaryCard` 只负责数据选择和轮换；动画遵循 `TickerMode` 与系统减少动画设置。

**Tech Stack:** Flutter Material 3、Dart、Widget Test、`AnimationController`、`CustomPainter`

## Global Constraints

- 新代码使用 `withValues(alpha:)` 和 `ColorScheme`。
- 不使用模糊滤镜，不在动画中改变布局尺寸。
- 可点击区域至少 48dp；方形图片入口固定 128×128。
- 页面隐藏或系统减少动画时暂停动态效果。
- 不修改表情存储和人格画像数据结构。

---

### Task 1: 表情图片入口

**Files:**
- Modify: `lib/widgets/sticker_panel.dart`
- Test: `test/sticker_panel_test.dart`

**Interfaces:**
- Consumes: `_pickImage()` 与 `_sourcePath`。
- Produces: `ValueKey('stickerImagePicker')` 的 128×128 可点击区域。

- [ ] **Step 1: Write the failing test**

在进入添加态后断言 `stickerImagePicker` 存在、尺寸为 128×128，且页面中不存在“选择本地图片”。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --no-pub test/sticker_panel_test.dart`
Expected: FAIL，旧界面仍显示文字按钮。

- [ ] **Step 3: Write minimal implementation**

用 `Material` + `InkWell` + `SizedBox.square(dimension: 128)` 替换 `OutlinedButton.icon`；未选图显示 `Icons.add_rounded`，已选图显示本地预览。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test --no-pub test/sticker_panel_test.dart`
Expected: PASS。

### Task 2: 首页低开销装饰动画

**Files:**
- Create: `lib/widgets/echo_profile_motion.dart`
- Modify: `lib/widgets/home_profile_summary_card.dart`
- Test: `test/home_profile_summary_card_test.dart`

**Interfaces:**
- Produces: `EchoVoiceWave` 与 `EchoOrbitRings`，均接受 `Color color` 和 `bool animate`。
- Consumes: `MediaQuery.disableAnimationsOf(context)` 与 `TickerMode.of(context)`。

- [ ] **Step 1: Write the failing test**

断言卡片包含 `EchoVoiceWave`、`EchoOrbitRings`，并在减少动画模式下仍静态渲染。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --no-pub test/home_profile_summary_card_test.dart`
Expected: FAIL，组件尚不存在。

- [ ] **Step 3: Write minimal implementation**

两个组件使用独立 `AnimationController` 和 `CustomPainter`，包裹 `RepaintBoundary`；声纹周期 1600ms，圆环周期 4200ms，动画只改变绘制参数。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test --no-pub test/home_profile_summary_card_test.dart`
Expected: PASS。

### Task 3: 画像文案轮换与卡片压缩

**Files:**
- Modify: `lib/widgets/home_profile_summary_card.dart`
- Test: `test/home_profile_summary_card_test.dart`

**Interfaces:**
- Consumes: 最近更新的 `ProfileEntry` 列表。
- Produces: 每 4 秒轮换最近 3–5 条画像的 `AnimatedSwitcher`。

- [ ] **Step 1: Write the failing test**

提供 4 条画像，推进 4 秒后断言“还记得”后的内容切换；同时断言卡片最小高度不超过 168。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --no-pub test/home_profile_summary_card_test.dart`
Expected: FAIL，旧组件为静态文案且最小高度为 184。

- [ ] **Step 3: Write minimal implementation**

将卡片改为 `StatefulWidget`，只在画像不少于 2 条、`TickerMode` 开启且未禁用动画时启动 4 秒计时器；使用 220ms `AnimatedSwitcher`。将卡片最小高度调整为 164，并压缩垂直间距。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test --no-pub test/home_profile_summary_card_test.dart`
Expected: PASS。

### Task 4: 完整验证

**Files:**
- Verify: `lib/widgets/sticker_panel.dart`
- Verify: `lib/widgets/echo_profile_motion.dart`
- Verify: `lib/widgets/home_profile_summary_card.dart`

- [ ] **Step 1: Run focused tests**

Run: `flutter test --no-pub test/sticker_panel_test.dart test/home_profile_summary_card_test.dart`
Expected: PASS。

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze --no-pub`
Expected: 0 errors、0 warnings；既有 info 可接受。

- [ ] **Step 3: Run full suite**

Run: `flutter test --no-pub`
Expected: All tests passed。
