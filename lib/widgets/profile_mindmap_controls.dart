import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'echo_visual_surface.dart';

String profileSourceLabel(String source) {
  return switch (source) {
    'manual' => '手动记录',
    'category_supplement' => '问卷补充',
    'profile_init_wizard' => '初始画像',
    _ => 'AI 观察',
  };
}

class ProfileMindMapViewport {
  const ProfileMindMapViewport._();

  static double initialScale(Size viewport) {
    final shortestSide = math.min(viewport.width, viewport.height);
    return (shortestSide / 760).clamp(0.55, 1.0).toDouble();
  }
}

class ProfileMindMapControls extends StatelessWidget {
  const ProfileMindMapControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EchoFloatingSurface(
      padding: const EdgeInsets.all(AppTheme.space1),
      borderRadius: AppTheme.brMd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            tooltip: '放大画像',
            icon: Icons.add_rounded,
            onPressed: onZoomIn,
          ),
          Container(
            width: 0.5,
            height: 24,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          _ControlButton(
            tooltip: '缩小画像',
            icon: Icons.remove_rounded,
            onPressed: onZoomOut,
          ),
          Container(
            width: 0.5,
            height: 24,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          _ControlButton(
            tooltip: '复位画像',
            icon: Icons.center_focus_strong_rounded,
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    );
  }
}
