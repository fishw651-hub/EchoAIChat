import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/liquid_glass_surface.dart';

class LiquidGlassBottomNavBar extends StatefulWidget {
  const LiquidGlassBottomNavBar({
    super.key,
    required this.scheme,
    required this.currentIndex,
    required this.tabBuilder,
    required this.centerAction,
  });

  final ColorScheme scheme;
  final int currentIndex;
  final Widget Function(int index, bool selected) tabBuilder;
  final Widget centerAction;

  @override
  State<LiquidGlassBottomNavBar> createState() =>
      _LiquidGlassBottomNavBarState();
}

class _LiquidGlassBottomNavBarState extends State<LiquidGlassBottomNavBar>
    with SingleTickerProviderStateMixin {
  static const _barHeight = 76.0;
  static const _capsuleHeight = 60.0;
  static const _animationDuration = Duration(milliseconds: 320);

  late final AnimationController _capsuleController = AnimationController(
    vsync: this,
    duration: _animationDuration,
  );

  double _fromPosition = 0;
  double _toPosition = 0;
  double _lastWidth = 0;
  bool _hasMeasured = false;

  @override
  void dispose() {
    _capsuleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex || !_hasMeasured) {
      return;
    }

    _fromPosition = _capsulePosition;
    _toPosition = _positionForIndex(widget.currentIndex, _lastWidth);
    if (MediaQuery.disableAnimationsOf(context)) {
      _capsuleController.value = 1;
    } else {
      _capsuleController.forward(from: 0);
    }
  }

  double get _capsulePosition {
    final progress = Curves.easeOutBack.transform(_capsuleController.value);
    return _fromPosition + (_toPosition - _fromPosition) * progress;
  }

  double _positionForIndex(int index, double width) {
    final clampedIndex = index.clamp(0, 3);
    final slotWidth = width / 5;
    final centers = <double>[
      slotWidth * 0.5,
      slotWidth * 1.5,
      slotWidth * 3.5,
      slotWidth * 4.5,
    ];
    return centers[clampedIndex];
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);

    return SafeArea(
      top: false,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _updateMeasurement(constraints.maxWidth);
              return SizedBox(
                height: _barHeight,
                child: LiquidGlassSurface(
                  scheme: widget.scheme,
                  radius: radius,
                  magnification: 1.12,
                  edgeWidth: 12,
                  filterKey: const Key('glass-refraction-fallback'),
                  blurKey: const Key('glass-main-blur'),
                  surfaceKey: const Key('glass-clear-main-surface'),
                  child: Stack(
                    children: [
                      _buildSelectedCapsule(constraints.maxWidth),
                      _buildSlots(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateMeasurement(double width) {
    if (width <= 0) return;
    if (_hasMeasured && (width - _lastWidth).abs() > 0.5) {
      _lastWidth = width;
      final target = _positionForIndex(widget.currentIndex, width);
      _fromPosition = target;
      _toPosition = target;
      return;
    }
    _lastWidth = width;
    if (_hasMeasured) return;
    _hasMeasured = true;
    _fromPosition = _positionForIndex(widget.currentIndex, width);
    _toPosition = _fromPosition;
  }

  Widget _buildSelectedCapsule(double width) {
    final slotWidth = width / 5;
    final capsuleWidth = math.max(48.0, math.min(slotWidth - 8, 84.0));
    final radius = BorderRadius.circular(24);

    return AnimatedBuilder(
      animation: _capsuleController,
      builder: (context, child) {
        final position = _capsulePosition;
        final isMoving =
            _capsuleController.value > 0 && _capsuleController.value < 1;
        final stretch = isMoving
            ? 1 + 0.08 * math.sin(math.pi * _capsuleController.value)
            : 1.0;
        return Positioned(
          key: const Key('selected-glass-capsule'),
          left: position - capsuleWidth / 2,
          top: (_barHeight - _capsuleHeight) / 2,
          width: capsuleWidth,
          height: _capsuleHeight,
          child: IgnorePointer(
            child: Transform.scale(
              alignment: Alignment.center,
              scaleX: stretch,
              child: child,
            ),
          ),
        );
      },
      child: LiquidGlassSurface(
        scheme: widget.scheme,
        radius: radius,
        magnification: 1.18,
        edgeWidth: 10,
        surfaceKey: const Key('glass-clear-selection-surface'),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildSlots() {
    return SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          Expanded(child: widget.tabBuilder(0, widget.currentIndex == 0)),
          Expanded(child: widget.tabBuilder(1, widget.currentIndex == 1)),
          Expanded(
            key: const Key('center-create-slot'),
            child: Center(child: widget.centerAction),
          ),
          Expanded(child: widget.tabBuilder(2, widget.currentIndex == 2)),
          Expanded(child: widget.tabBuilder(3, widget.currentIndex == 3)),
        ],
      ),
    );
  }
}
