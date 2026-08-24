import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EchoPanel extends StatelessWidget {
  const EchoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space4),
    this.margin,
    this.onTap,
    this.emphasized = false,
    this.semanticLabel = '回响内容面板',
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool emphasized;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: emphasized
          ? scheme.primaryContainer.withValues(alpha: 0.48)
          : scheme.surfaceContainerLow,
      borderRadius: AppTheme.brXl,
      border: Border.all(
        color: emphasized
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.outlineVariant.withValues(alpha: 0.48),
        width: 0.5,
      ),
      boxShadow: emphasized ? AppTheme.primaryShadowSm(scheme) : null,
    );
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    return Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      child: onTap == null
          ? content
          : Material(
              color: const Color(0x00000000),
              child: InkWell(
                onTap: onTap,
                borderRadius: AppTheme.brXl,
                child: content,
              ),
            ),
    );
  }
}

class EchoSectionHeader extends StatelessWidget {
  const EchoSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppTheme.space1),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class EchoProfileHeader extends StatelessWidget {
  const EchoProfileHeader({
    super.key,
    required this.totalCount,
    required this.onEdit,
  });

  final int totalCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EchoPanel(
      emphasized: true,
      semanticLabel: '我眼中的你人格画像概览',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: AppTheme.brMd,
            ),
            child: Icon(Icons.psychology_alt_outlined, color: scheme.onPrimary),
          ),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我眼中的你',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTheme.space1),
                Text(
                  totalCount == 0 ? '还没有形成可信观察' : '已沉淀 $totalCount 条可信观察',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('管理画像')),
        ],
      ),
    );
  }
}

class EchoBubbleSurface extends StatelessWidget {
  const EchoBubbleSurface({
    super.key,
    required this.isUser,
    required this.child,
    this.isHovered = false,
    this.isSelected = false,
    this.maxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final bool isUser;
  final Widget child;
  final bool isHovered;
  final bool isSelected;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(AppTheme.radiusLg),
      topRight: const Radius.circular(AppTheme.radiusLg),
      bottomLeft: Radius.circular(isUser ? AppTheme.radiusLg : 6),
      bottomRight: Radius.circular(isUser ? 6 : AppTheme.radiusLg),
    );
    final borderColor = isSelected
        ? scheme.primary
        : isUser
        ? scheme.primary.withValues(alpha: 0.16)
        : scheme.outlineVariant.withValues(alpha: 0.48);

    return Semantics(
      container: true,
      label: isUser ? '用户消息气泡' : '智能体消息气泡',
      child: AnimatedContainer(
        key: ValueKey(isUser ? 'echo-user-bubble' : 'echo-agent-bubble'),
        duration: AppTheme.durFast,
        constraints: maxWidth == null
            ? null
            : BoxConstraints(maxWidth: maxWidth!),
        padding: padding,
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primary
              : isHovered
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLow,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 0.5),
          boxShadow: isUser
              ? AppTheme.primaryShadowSm(scheme)
              : AppTheme.shadowSm,
        ),
        child: child,
      ),
    );
  }
}

class EchoFloatingSurface extends StatelessWidget {
  const EchoFloatingSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space2),
    this.borderRadius = AppTheme.brXl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: borderRadius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
          width: 0.5,
        ),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 统一的图标徽标：40×40、`brMd` 圆角、primaryContainer→primary 微渐变底。
///
/// 账户页功能入口、设置页各分区列表项共用，取代各处 32/36/38/40px
/// 混用的自定义图标容器。
class EchoIconBadge extends StatelessWidget {
  const EchoIconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.color,
  });

  final IconData icon;

  /// 容器边长（默认 40）
  final double size;

  /// 图标尺寸（默认 20）
  final double iconSize;

  /// 图标与渐变的主色，默认 scheme.primary
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: 0.16),
            tint.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: AppTheme.brMd,
        border: Border.all(
          color: tint.withValues(alpha: 0.14),
          width: 0.5,
        ),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// 页面头部渐隐光晕：primary 低透明度从顶部渐隐到透明。
///
/// 放在 Stack 底层、内容之后，为首页/账户/设置的头部提供统一的
/// Echo 氛围锚点，不遮挡交互（自身 IgnorePointer）。
class EchoHeaderGlow extends StatelessWidget {
  const EchoHeaderGlow({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.10),
              scheme.primary.withValues(alpha: 0.04),
              scheme.primary.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
