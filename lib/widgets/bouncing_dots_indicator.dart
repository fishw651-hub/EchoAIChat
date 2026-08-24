import 'package:flutter/material.dart';

/// Bouncing dots loading indicator
class BouncingDotsIndicator extends StatefulWidget {
  const BouncingDotsIndicator({super.key});

  @override
  State<BouncingDotsIndicator> createState() => _BouncingDotsIndicatorState();
}

class _BouncingDotsIndicatorState extends State<BouncingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _dot(0),
          const SizedBox(width: 6),
          _dot(1),
          const SizedBox(width: 6),
          _dot(2),
        ],
      ),
    );
  }

  Widget _dot(int index) {
    final delay = index * 0.2;
    final anim =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 0.5),
          TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 0.5),
        ]).animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: Interval(delay, delay + 0.4, curve: Curves.easeInOut),
          ),
        );

    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Transform.scale(
        scale: anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
