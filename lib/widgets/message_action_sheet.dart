import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 消息长按操作项数据模型
class MessageActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const MessageActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// 微信样式的消息长按操作浮层
///
/// 在长按位置弹出紧凑的操作菜单，使用 [showMessageActionMenu] 触发。
///
/// 特性：
/// - 跟随手指位置弹出，紧凑圆角容器
/// - 顶部 + 四周阴影区分层级
/// - Wrap 自适应换行，去除冗余 padding
/// - 点击遮罩或选项后关闭
class MessageActionSheet extends StatelessWidget {
  final List<MessageActionItem> actions;

  const MessageActionSheet({super.key, required this.actions});

  /// 在指定屏幕位置弹出微信样式操作菜单
  ///
  /// 返回的 Future 在浮层关闭（点遮罩或点选项）时完成，
  /// 调用方可据此判断菜单是否仍处于打开状态。
  static Future<void> showAt(
    BuildContext context,
    Offset position,
    List<MessageActionItem> actions,
  ) {
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();

    final overlay = Overlay.of(context, rootOverlay: true);
    final dismissed = Completer<void>();
    late OverlayEntry entry;
    void dismiss() {
      if (dismissed.isCompleted) return;
      dismissed.complete();
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (ctx) => _ActionOverlay(
        position: position,
        actions: actions,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(entry);
    return dismissed.future;
  }

  @override
  Widget build(BuildContext context) {
    return _ActionGrid(actions: actions, onDismiss: () {});
  }
}

/// 全屏遮罩 + 跟随位置的浮层（带淡入+缩放动画）
class _ActionOverlay extends StatefulWidget {
  final Offset position;
  final List<MessageActionItem> actions;
  final VoidCallback onDismiss;

  const _ActionOverlay({
    required this.position,
    required this.actions,
    required this.onDismiss,
  });

  @override
  State<_ActionOverlay> createState() => _ActionOverlayState();
}

class _ActionOverlayState extends State<_ActionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;

    // 浮层预估尺寸：每个按钮 56 宽，行高 76，横向 spacing 4
    const itemWidth = 56.0;
    const itemHeight = 76.0;
    const spacing = 4.0;
    const horizPadding = 8.0;
    const vertPadding = 8.0;

    // 估算每行能放几个按钮，最多 5 个一行
    final screenWidth = mq.size.width;
    final maxPerRow = ((screenWidth - 32) / (itemWidth + spacing)).floor().clamp(1, 5);
    final perRow = widget.actions.length <= maxPerRow ? widget.actions.length : maxPerRow;
    final rows = (widget.actions.length / perRow).ceil();
    final gridWidth = perRow * itemWidth + (perRow - 1) * spacing + horizPadding * 2;
    final gridHeight = rows * itemHeight + (rows - 1) * 6 + vertPadding * 2;

    // 计算浮层位置，确保不超出屏幕边界
    double left = widget.position.dx - gridWidth / 2;
    double top = widget.position.dy - gridHeight - 12; // 默认在长按点上方
    if (top < mq.padding.top + 8) {
      top = widget.position.dy + 24; // 上方空间不足则放下方
    }
    left = left.clamp(8.0, screenWidth - gridWidth - 8);
    if (top + gridHeight > mq.size.height - mq.padding.bottom - 8) {
      top = mq.size.height - mq.padding.bottom - gridHeight - 8;
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Stack(
          children: [
            // 半透明遮罩，点击关闭（淡入）
            GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withValues(alpha: 0.15 * _opacity.value)),
            ),
            // 浮层菜单（缩放+淡入）
            Positioned(
              left: left,
              top: top,
              child: Transform.scale(
                scale: _scale.value,
                alignment: Alignment.bottomCenter,
                child: Opacity(
                  opacity: _opacity.value,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: gridWidth,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _ActionGrid(
                        actions: widget.actions,
                        onDismiss: widget.onDismiss,
                        itemWidth: itemWidth,
                        itemHeight: itemHeight,
                        spacing: spacing,
                        horizPadding: horizPadding,
                        vertPadding: vertPadding,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 按钮网格
class _ActionGrid extends StatelessWidget {
  final List<MessageActionItem> actions;
  final VoidCallback onDismiss;
  final double itemWidth;
  final double itemHeight;
  final double spacing;
  final double horizPadding;
  final double vertPadding;

  const _ActionGrid({
    required this.actions,
    required this.onDismiss,
    this.itemWidth = 56,
    this.itemHeight = 76,
    this.spacing = 4,
    this.horizPadding = 8,
    this.vertPadding = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizPadding,
        vertical: vertPadding,
      ),
      child: Wrap(
        spacing: spacing,
        runSpacing: 6,
        children: actions
            .map((item) => _ActionButton(
                  item: item,
                  width: itemWidth,
                  height: itemHeight,
                  onDismiss: onDismiss,
                ))
            .toList(),
      ),
    );
  }
}

/// 单个操作按钮（微信样式：纯图标 + 小字）
class _ActionButton extends StatelessWidget {
  final MessageActionItem item;
  final double width;
  final double height;
  final VoidCallback onDismiss;

  const _ActionButton({
    required this.item,
    required this.width,
    required this.height,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        onDismiss();
        item.onTap();
      },
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 22, color: item.color),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
