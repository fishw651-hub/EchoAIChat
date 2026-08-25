# 折射液态玻璃移动端底栏实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将移动端主页底栏升级为带真实边缘折射的五槽液态玻璃导航，并将中心创建入口改为与 Tab 同行的放大加号。

**Architecture:** `LiquidGlassBottomNavBar` 继续负责视觉布局，新增内部 `_LiquidGlassSurface` 处理片元滤镜加载、Impeller 能力检查和模糊降级。`MobileCreateAction` 保持菜单和回调，仅删除可见圆形容器并适配五槽中心位置；页面状态、PageView 与桌面侧栏不变。

**Tech Stack:** Flutter 3.41、Dart 3.11、Material 3、`BackdropFilter`、`ImageFilter.shader`、Flutter Runtime Effect、Widget Test。

## 全局约束

- 仅修改移动端底部悬浮 Tab 栏；桌面侧边栏与 PageView 映射保持不变。
- 使用现有 `ColorScheme`，不得新增 `Colors.white`、`Colors.black` 或第三方依赖。
- 新代码使用 `withValues(alpha: ...)`，不得使用 `withOpacity`。
- Shader 仅用于 `ImageFilter.isShaderFilterSupported` 为 true 的 Impeller 后端；其他后端必须使用低强度模糊降级，且不得抛出 `UnsupportedError`。
- 主底栏、选中胶囊和创建菜单必须继续使用 SafeArea、extendBody、减少动态效果和至少 48dp 的触控区域。
- 中心入口只有约 32dp 的加号，不得有圆形玻璃、上浮偏移或独立阴影；创建菜单行为保持不变。
- 工作区存在无关修改；不得回滚、覆盖或自动提交其他文件。

---

## 文件地图

- `shaders/liquid_glass_refraction.frag`：针对 ImageFilter 输入纹理的圆角边缘采样位移。
- `pubspec.yaml`：声明 shader 资源。
- `lib/screens/liquid_glass_bottom_nav_bar.dart`：五槽结构、表面分层、Shader 加载和降级、选中胶囊动画。
- `lib/screens/home_screen.dart`：创建入口的无圆形点击表面。
- `test/liquid_glass_bottom_nav_bar_test.dart`：布局、圆形容器移除、降级和动画回归。
- `test/home_create_action_test.dart`：创建入口图标尺寸和菜单行为回归。

### Task 1: 建立折射 Shader 资源与声明

**Files:**
- Create: `shaders/liquid_glass_refraction.frag`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: shader asset `shaders/liquid_glass_refraction.frag`，uniform 顺序为 `vec2 u_size`、`float u_radius`、`float u_edge_width`、`float u_strength`、`sampler2D u_backdrop`。
- Consumed by: `_LiquidGlassSurface` 通过 `FragmentProgram.fromAsset` 创建 `ImageFilter.shader`。

- [ ] **Step 1: 创建 Runtime Effect**

```glsl
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_radius;
uniform float u_edge_width;
uniform float u_strength;
uniform sampler2D u_backdrop;

out vec4 frag_color;

float roundedBoxDistance(vec2 point, vec2 halfSize, float radius) {
  vec2 corner = abs(point) - halfSize + vec2(radius);
  return min(max(corner.x, corner.y), 0.0) + length(max(corner, 0.0)) - radius;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 point = FlutterFragCoord().xy - u_size * 0.5;
  float distance = roundedBoxDistance(point, u_size * 0.5, u_radius);
  float depth = clamp(-distance / u_edge_width, 0.0, 1.0);
  float ring = 4.0 * depth * (1.0 - depth);
  vec2 inward = normalize(-point + vec2(0.0001));
  vec2 refractedUv = uv + inward * ring * u_strength / u_size;
  frag_color = texture(u_backdrop, clamp(refractedUv, vec2(0.0), vec2(1.0)));
}
```

- [ ] **Step 2: 在 `flutter:` 下声明 shader**

```yaml
  shaders:
    - shaders/liquid_glass_refraction.frag
```

- [ ] **Step 3: 获取资源并确认 Shader 能被编译**

Run: `flutter --suppress-analytics pub get`

Expected: 退出码 0；无 YAML 或 shader asset 声明错误。

### Task 2: 先写五槽与无圆形创建入口的失败测试

**Files:**
- Modify: `test/liquid_glass_bottom_nav_bar_test.dart`
- Modify: `test/home_create_action_test.dart`

**Interfaces:**
- Consumes: 现有 `LiquidGlassBottomNavBar` 与 `MobileCreateAction`。
- Produces: 对 `center-create-slot`、`glass-refraction-fallback`、无 `ClipOval` 和五槽中心加号的回归要求。

- [ ] **Step 1: 在底栏测试新增失败断言**

```dart
expect(find.byKey(const Key('center-create-slot')), findsOneWidget);
expect(find.byKey(const Key('glass-refraction-fallback')), findsOneWidget);
expect(find.descendant(
  of: find.byType(LiquidGlassBottomNavBar),
  matching: find.byType(ClipOval),
), findsNothing);

final center = tester.getCenter(find.byKey(const Key('center-create-slot')));
final tab0 = tester.getCenter(find.byKey(const Key('tab-0')));
expect(center.dy, closeTo(tab0.dy, 8));
```

- [ ] **Step 2: 在创建入口测试新增图标与可见容器断言**

```dart
final addIcon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
expect(addIcon.size, 32);
expect(find.byType(ClipOval), findsNothing);
```

- [ ] **Step 3: 运行测试确认现有实现不符合新要求**

Run: `flutter --suppress-analytics test test/liquid_glass_bottom_nav_bar_test.dart test/home_create_action_test.dart`

Expected: FAIL；旧版本不存在 `center-create-slot` 或仍渲染 `ClipOval`。

### Task 3: 实现可降级的折射玻璃表面与五槽布局

**Files:**
- Modify: `lib/screens/liquid_glass_bottom_nav_bar.dart`
- Test: `test/liquid_glass_bottom_nav_bar_test.dart`

**Interfaces:**
- Consumes: `ColorScheme scheme`、`BorderRadius radius`、`double refractionStrength`、子组件。
- Produces: 私有 `_LiquidGlassSurface`，对支持的后端应用 `ImageFilter.shader`，否则使用 `ImageFilter.blur(sigmaX: 3, sigmaY: 3)`；`LiquidGlassBottomNavBar` 以五个 `Expanded` 槽位展示 Tab 0、1、加号、2、3。

- [ ] **Step 1: 添加内部表面组件和全局程序缓存**

```dart
final Future<FragmentProgram> _liquidGlassProgram =
    FragmentProgram.fromAsset('shaders/liquid_glass_refraction.frag');

class _LiquidGlassSurface extends StatefulWidget {
  const _LiquidGlassSurface({
    required this.scheme,
    required this.radius,
    required this.refractionStrength,
    required this.child,
  });

  final ColorScheme scheme;
  final BorderRadius radius;
  final double refractionStrength;
  final Widget child;
}
```

在 State 中异步读取 `_liquidGlassProgram`。`ImageFilter.isShaderFilterSupported` 为 false 或 program 尚未就绪时，构造 `ImageFilter.blur(sigmaX: 3, sigmaY: 3)`；为 true 时依次设置 `setFloat(2, radius)`、`setFloat(3, 9)`、`setFloat(4, refractionStrength)`，并构造 `ImageFilter.shader(shader)`。缓存当前 `FragmentShader`，在替换和 `dispose` 时释放。

- [ ] **Step 2: 用四层 Stack 替换当前主底栏与胶囊材质**

`_LiquidGlassSurface` 必须将 `BackdropFilter` 裁剪在 `ClipRRect` 内，并在其 child 上依序绘制：

```dart
DecoratedBox(color: scheme.surface.withValues(alpha: isDark ? .12 : .16))
DecoratedBox(border: Border.all(color: scheme.onSurface.withValues(alpha: .22), width: .75))
Align(alignment: Alignment.topCenter, child: SizedBox(height: 1, child: ...))
Align(alignment: Alignment.bottomCenter, child: SizedBox(height: 1, child: ...))
```

顶部颜色使用 `scheme.onSurface` 的低 alpha，底部使用 `scheme.shadow` 的低 alpha。主栏传入 `refractionStrength: 12`，选中胶囊传入 `refractionStrength: 16`。

- [ ] **Step 3: 改为五槽 Row 和四个胶囊目标中心**

将 `_centerSlotWidth` 删除，中心坐标改为：

```dart
final slotWidth = width / 5;
final centers = <double>[
  slotWidth * .5,
  slotWidth * 1.5,
  slotWidth * 3.5,
  slotWidth * 4.5,
];
```

Tab Row 改为：

```dart
Row(children: [
  Expanded(child: tabBuilder(0, currentIndex == 0)),
  Expanded(child: tabBuilder(1, currentIndex == 1)),
  Expanded(key: const Key('center-create-slot'), child: Center(child: centerAction)),
  Expanded(child: tabBuilder(2, currentIndex == 2)),
  Expanded(child: tabBuilder(3, currentIndex == 3)),
])
```

删除 `_buildCreateAction`、`ClipOval`、圆形 BackdropFilter、上浮 `Transform.translate`、`_createPressed` 和其 `Listener`。保留 `selected-glass-capsule`、可打断动画、`RepaintBoundary`、SafeArea 和高度。

- [ ] **Step 4: 暴露并验证降级路径**

当 `ImageFilter.isShaderFilterSupported` 为 false 时，在 `_LiquidGlassSurface` 的降级 `BackdropFilter` 上设置 `key: const Key('glass-refraction-fallback')`；shader 可用时使用 `key: const Key('glass-refraction-shader')`。测试环境默认走前者，保证测试不依赖 GPU 后端。

- [ ] **Step 5: 运行组件测试**

Run: `flutter --suppress-analytics test test/liquid_glass_bottom_nav_bar_test.dart`

Expected: PASS；包含五槽、无 `ClipOval`、胶囊位移、深色窄屏、快速切换与降级断言。

### Task 4: 改造中心创建入口并保留菜单

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/home_create_action_test.dart`

**Interfaces:**
- Consumes: 五槽布局中传入的 `MobileCreateAction`。
- Produces: 56dp 透明点击区域、32dp `Icons.add_rounded`、现有 `OverlayPortal` 菜单和回调。

- [ ] **Step 1: 删除圆形命中形状并让加号与 Tab 同行**

替换 `MobileCreateAction.build` 中的 Material/InkWell 片段：

```dart
Material(
  type: MaterialType.transparency,
  child: InkWell(
    key: const Key('home-create-button'),
    borderRadius: BorderRadius.circular(18),
    overlayColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: .10)),
    onTap: _toggleMenu,
    child: const SizedBox(
      width: 56,
      height: 56,
      child: Center(child: Icon(Icons.add_rounded, size: 32)),
    ),
  ),
)
```

图标颜色从 `scheme.onSurface` 设置，不能增加背景装饰、形状或阴影。

- [ ] **Step 2: 运行创建菜单回归测试**

Run: `flutter --suppress-analytics test test/home_create_action_test.dart`

Expected: PASS；点击加号显示菜单，选择创建智能体回调继续触发，且无 `ClipOval`。

### Task 5: 格式化、静态分析、回归和视觉验证

**Files:**
- Modify: `docs/superpowers/plans/2026-08-25-mobile-liquid-glass-bottom-nav.md`

- [ ] **Step 1: 格式化并扫描不允许的颜色 API**

Run: `dart format lib/screens/liquid_glass_bottom_nav_bar.dart lib/screens/home_screen.dart test/liquid_glass_bottom_nav_bar_test.dart test/home_create_action_test.dart`

Run: `rg -n "Colors\\.(white|black)|withOpacity|ClipOval|_centerSlotWidth" lib/screens/liquid_glass_bottom_nav_bar.dart lib/screens/home_screen.dart`

Expected: formatter 退出码 0；扫描不应匹配本次液态玻璃或创建入口的禁止项。

- [ ] **Step 2: 运行定向检查与测试**

Run: `dart --suppress-analytics analyze lib/screens/liquid_glass_bottom_nav_bar.dart lib/screens/home_screen.dart test/liquid_glass_bottom_nav_bar_test.dart test/home_create_action_test.dart`

Run: `flutter --suppress-analytics test test/liquid_glass_bottom_nav_bar_test.dart test/home_create_action_test.dart test/home_page_mapping_test.dart test/ui_cleanup_regression_test.dart`

Expected: 所有定向分析和测试退出码 0。

- [ ] **Step 3: 以移动端运行并检查浅深色页面**

Run: `flutter --suppress-analytics run -d <available-mobile-or-windows-device>`

Expected: 人工检查 375dp 等效窄屏的浅色与深色主题：玻璃边缘可见局部折射；中心加号无圆形容器且与 Tab 图标同一行；文字和分段控件不重叠；创建菜单继续从中心加号上方展开。

- [ ] **Step 4: 更新验证记录而不自动提交**

在本计划末尾记录实际执行的命令、结果和任何既有全量测试失败。执行 `git diff --check`，不执行 `git add`、`git commit`、重置或清理命令。
