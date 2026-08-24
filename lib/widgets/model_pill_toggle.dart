import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 模型切换胶囊按钮组
///
/// 用 [AnimatedPositioned] 在 Stack 中绝对定位滑块，确保切换时位置精准。
/// 文字颜色用 [TweenAnimationBuilder] 平滑过渡，与滑块动画同步。
///
/// 使用方式：
/// ```dart
/// ModelPillToggle(
///   modelIds: ['deepseek-v4-flash', 'deepseek-v4-pro'],
///   selected: currentModel,
///   onChanged: (v) => ...,
/// )
/// ```
class ModelPillToggle extends StatelessWidget {
  final List<String> modelIds;
  final String selected;
  final ValueChanged<String> onChanged;

  const ModelPillToggle({
    super.key,
    required this.modelIds,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 单模型：直接显示胶囊
    if (modelIds.length < 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          AppTheme.friendlyModelName(modelIds.first),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onPrimaryContainer,
          ),
        ),
      );
    }

    final selectedIndex = modelIds.indexOf(selected);
    // 防御：如果 selected 不在列表中，回退到 0
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return RepaintBoundary(
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / modelIds.length;
            return SizedBox(
              height: constraints.maxHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 滑块：用 AnimatedPositioned 绝对定位，位置精准无歧义
                  AnimatedPositioned(
                    left: safeIndex * itemWidth,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    duration: AppTheme.durBase,
                    curve: Curves.easeInOutCubic,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 文字层：每个文字颜色独立平滑过渡
                  Row(
                    children: modelIds.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final id = entry.value;
                      final isSelected = idx == safeIndex;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(id),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: constraints.maxHeight,
                            alignment: Alignment.center,
                            child: _AnimatedColorText(
                              text: AppTheme.friendlyModelName(id),
                              isSelected: isSelected,
                              selectedColor: scheme.onPrimary,
                              unselectedColor: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 文字颜色平滑过渡的 Text
class _AnimatedColorText extends StatelessWidget {
  final String text;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;

  const _AnimatedColorText({
    required this.text,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      duration: AppTheme.durBase,
      curve: Curves.easeInOut,
      tween: ColorTween(
        begin: isSelected ? unselectedColor : selectedColor,
        end: isSelected ? selectedColor : unselectedColor,
      ),
      builder: (ctx, color, child) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
