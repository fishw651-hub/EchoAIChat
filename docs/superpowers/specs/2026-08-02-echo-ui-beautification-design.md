# Echo 三界面氛围强化美化设计（首页 / 账户 / 设置）

> 日期：2026-08-02 · 状态：已获用户批准 · 方向：氛围强化（三个页面一起改）

## 背景与目标

首页 tab、账户 tab、设置页三个界面已有基础装饰（首页画像卡、账户/设置各一张渐变 hero 卡），但存在：

- 装饰语言不统一：设置页图标容器 32/36/38/40px 四种规格混用；账户页订阅/同步入口卡样式不一致
- 头部朴素：三页 AppBar 均为纯文字标题，无氛围
- 信息层次弱：账户余额统计为平铺小字；首页会话列表纯平铺与高装饰画像卡反差大；未登录账户页空旷；设置备份区为无说明的裸按钮

目标：以首页画像卡的 Echo 设计语言为基准，统一并强化三个页面的视觉氛围，同时保住所有回归测试硬约束。

## 总体设计语言

1. **Echo 氛围锚点**：每个页面的头部/hero 区域使用 primary 系柔和渐变 + `EchoOrbitRings` / `EchoVoiceWave`（复用现有组件，不引入新动画库）+ `AppTheme.brXl` + `AppTheme.primaryShadow*`。
2. **统一图标徽标 `EchoIconBadge`**：新共享组件，加入 `lib/widgets/echo_visual_surface.dart`（现有共享视觉容器文件），40×40、`brMd`、primaryContainer → primary 低透明度渐变底 + primary 图标。替换设置页四种混用规格与账户页入口图标块。
3. **动效克制**：时长/曲线沿用 `AppTheme.durFast/durBase` 与 `AppTheme.curve`。
4. **样式规范**：`withValues(alpha:)`（禁 `withOpacity`）、`Theme.of(context).colorScheme`（禁硬编码 `Colors.white/black`）、新文案补 l10n key（当前仅中文）。

## 首页 `lib/screens/home_tab_screen.dart`

1. **头部氛围**：SliverAppBar 背后加顶部渐隐光晕（primary ~10% → 透明），标题与 `_QuotaPill` 浮于其上；额度胶囊略放大，金额用 titleMedium 强调。
2. **会话列表卡片化**：`ConversationListWidget` 外层包 `brXl` 卡片（细描边 + 微阴影），分隔线收进卡片内；会话头像加 0.5px 描边。
3. 画像卡、空态装饰保持不变。
4. **禁止**：恢复任何形式的时间问候语（测试断言源码不得含 `_greeting`）。

## 账户 `lib/screens/account_screen.dart`

1. **Hero 卡强化**（保留 `key: accountProfileHero`）：现有渐变上加右上角 `EchoOrbitRings` 小装饰；头像加 primary 描边光环。
2. **余额卡重做**：三列统计改为三个指标块（大数值 + 小标签 + 微型图标，块间竖分隔线）；「今日已用」加迷你进度条（已用/总额度）。
3. **入口卡统一**：订阅中心与多端同步统一为"功能卡"布局（EchoIconBadge + 标题 + 副标题 + 状态徽标 + chevron）；订阅卡保留 primaryContainer 强调底。
4. **未登录态引导**：hero 卡下方加引导块（渐变圆角插画区 + 图标 + 文案 + 登录按钮）。

## 设置 `lib/screens/settings_screen.dart`

1. **Overview 卡**（保留 `key: settingsOverview`）：与账户 hero 同款氛围（渐变 + 轨道环小装饰）。
2. **图标统一**：所有 section 列表项图标容器换用 `EchoIconBadge`。
3. **主题选择升级**：Dropdown 改为 SegmentedButton（跟随系统/浅色/深色），不恢复主题色选择（Ocean 唯一种子色）。
4. **备份区**：两个按钮补充说明文案（备份内容范围、恢复会覆盖现有数据的提示）。
5. **必须保留**：`ListView.builder` 懒构建、`_roundsSaveTimer` 防抖、`onEditingComplete` 立即保存。

## 回归测试硬约束（`test/ui_cleanup_regression_test.dart`）

- `account_screen.dart` 含 `ValueKey('accountProfileHero')`
- `settings_screen.dart` 含 `ValueKey('settingsOverview')`、`ListView.builder`、`_roundsSaveTimer`、`onEditingComplete`
- `home_tab_screen.dart` 不得出现 `_greeting`
- 设置页/settings_provider 不得出现 `themeColor`/`updatePrimaryColor`/`primaryColor`
- `app_theme.dart` 保持 `InkRipple.splashFactory`，禁 `InkSparkle`
- `home_screen.dart` 保持 `_LazyIndexedStack`；`main.dart` 保持 `settingsProvider.select`
- 画像卡 key（`homeProfileCardSurface`/`homeProfileOrbitRings`/`homeProfileVoiceWave`）不动

## 实施拆分

1. 共享组件 `EchoIconBadge` + 头部光晕装饰辅助
2. 账户页（hero 装饰、余额卡、入口卡统一、未登录引导）
3. 首页（头部氛围、会话列表卡片化）
4. 设置页（overview 氛围、图标统一、主题 SegmentedButton、备份说明）
5. l10n key 补全 → `flutter analyze`（0 errors）→ `flutter test`（全绿）

## 成功标准

- 三页头部/hero 视觉语言一致，图标容器规格统一
- 余额统计可读性提升（大数值 + 进度条）
- analyze 0 errors，全部测试通过（含 ui_cleanup_regression_test）
