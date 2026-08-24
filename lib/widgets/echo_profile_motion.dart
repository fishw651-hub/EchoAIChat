import 'dart:math' as math;

import 'package:flutter/material.dart';

class EchoRippleRing {
  const EchoRippleRing({required this.radius, required this.opacity});

  final double radius;
  final double opacity;
}

class EchoRippleFrame {
  const EchoRippleFrame({required this.center, required this.rings});

  final Offset center;
  final List<EchoRippleRing> rings;
}

class EchoRippleGeometry {
  const EchoRippleGeometry._();

  static EchoRippleFrame sample(Size size, double progress) {
    final normalized = progress.clamp(0.0, 1.0);
    final center = Offset(size.width * 0.52, size.height * 0.5);
    final rings = List<EchoRippleRing>.generate(3, (index) {
      final phase = (normalized + index / 3) % 1.0;
      // 出生阶段淡入，消亡阶段严格归零，phase 回绕时无缝衔接。
      final fadeIn = Curves.easeOut.transform((phase / 0.18).clamp(0.0, 1.0));
      final fadeOut = 1 - Curves.easeInCubic.transform(phase);
      return EchoRippleRing(
        radius: 16 + 40 * Curves.easeOutCubic.transform(phase),
        opacity: fadeIn * fadeOut,
      );
    }, growable: false);
    return EchoRippleFrame(center: center, rings: rings);
  }
}

class EchoVoiceWave extends StatefulWidget {
  const EchoVoiceWave({super.key, required this.color, this.animate = true});

  final Color color;
  final bool animate;

  @override
  State<EchoVoiceWave> createState() => _EchoVoiceWaveState();
}

class _EchoVoiceWaveState extends State<EchoVoiceWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant EchoVoiceWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.18;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(28, 24),
        painter: _VoiceWavePainter(animation: _controller, color: widget.color),
      ),
    );
  }
}

class EchoOrbitRings extends StatefulWidget {
  const EchoOrbitRings({super.key, required this.color, this.animate = true});

  final Color color;
  final bool animate;

  @override
  State<EchoOrbitRings> createState() => _EchoOrbitRingsState();
}

class _EchoOrbitRingsState extends State<EchoOrbitRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant EchoOrbitRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.24;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(150),
        painter: _OrbitRingsPainter(
          animation: _controller,
          color: widget.color,
        ),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  _VoiceWavePainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    const barCount = 4;
    const spacing = 6.2;
    final startX = (size.width - spacing * (barCount - 1)) / 2;
    for (var index = 0; index < barCount; index++) {
      final phase = animation.value * math.pi * 2 + index * 1.15;
      final height = 7 + (math.sin(phase) + 1) * 5;
      final x = startX + index * spacing;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.animation != animation;
  }
}

class _OrbitRingsPainter extends CustomPainter {
  _OrbitRingsPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = EchoRippleGeometry.sample(size, animation.value);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final ring in frame.rings) {
      paint.color = color.withValues(alpha: color.a * ring.opacity);
      canvas.drawCircle(frame.center, ring.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRingsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.animation != animation;
  }
}
