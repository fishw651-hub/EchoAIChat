import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 两选项胶囊分段控件（等宽）。
///
/// 选中项为 primary 色圆角滑块（[secondSelected] 变化时滑块 250ms 平移），
/// 未选中项透明；文字/图标颜色随选中态渐变。
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
    return Container(
      width: _width,
      height: _height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // 与底部悬浮导航栏呼应的半透明浮层底色
        color: scheme.surface.withValues(alpha: isDark ? 0.92 : 0.94),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(
          color: isDark
              ? scheme.outlineVariant.withValues(alpha: 0.65)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.3 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 选中态 primary 滑块：左右两槽位间平移
          AnimatedAlign(
            alignment: secondSelected
                ? Alignment.centerRight
                : Alignment.centerLeft,
            duration: _duration,
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
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
            end: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
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
