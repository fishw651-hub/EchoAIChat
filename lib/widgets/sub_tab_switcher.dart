import 'package:flutter/material.dart';

import 'liquid_glass_surface.dart';

/// 两选项胶囊分段控件（等宽）。
///
/// 选中项为透明液态玻璃滑块（[secondSelected] 变化时滑块 250ms 平移），
/// 未选中项保持透明；文字/图标颜色随选中态渐变。
/// 移动端浮于底部悬浮导航栏上方、桌面端位于内容区顶部，
/// 供"智能体·群聊"合并 tab 与"发现"tab 切换子页（智能体/群聊）使用。
class SubTabSwitcher extends StatelessWidget {
  const SubTabSwitcher({
    super.key,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstIcon,
    required this.secondIcon,
    required this.secondSelected,
    required this.onChanged,
  });

  /// 左选项（[secondSelected] 为 false 时选中）的文字与图标
  final String firstLabel;
  final IconData firstIcon;

  /// 右选项（[secondSelected] 为 true 时选中）的文字与图标
  final String secondLabel;
  final IconData secondIcon;

  /// 是否选中右选项
  final bool secondSelected;

  /// 点击选项回调：false=选中左选项 true=选中右选项
  final ValueChanged<bool> onChanged;

  static const double _width = 240;
  static const double _height = 40;
  static const Duration _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return SizedBox(
      width: _width,
      height: _height,
      child: LiquidGlassSurface(
        key: const Key('sub-tab-glass-surface'),
        scheme: scheme,
        radius: BorderRadius.circular(20),
        magnification: 1.08,
        edgeWidth: 6,
        blurSigma: isDark ? 2.6 : 2.2,
        debugLabel: 'sub-tab',
        surfaceKey: const Key('sub-tab-glass-surface-layer'),
        blurKey: const Key('sub-tab-glass-blur'),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: secondSelected
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: _duration,
                curve: Curves.easeOutCubic,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: LiquidGlassSurface(
                    key: const Key('sub-tab-selected-glass-surface'),
                    scheme: scheme,
                    radius: BorderRadius.circular(17),
                    magnification: 1.12,
                    edgeWidth: 5,
                    blurSigma: isDark ? 2.4 : 2.0,
                    debugLabel: 'sub-tab-selected',
                    surfaceKey: const Key(
                      'sub-tab-selected-glass-surface-layer',
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _option(
                      scheme: scheme,
                      icon: firstIcon,
                      label: firstLabel,
                      selected: !secondSelected,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _option(
                      scheme: scheme,
                      icon: secondIcon,
                      label: secondLabel,
                      selected: secondSelected,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          duration: _duration,
          builder: (context, color, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
