import 'dart:math' as math;

import 'package:aichat/widgets/echo_profile_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('echo rings expand from one fixed center and stay inside canvas', () {
    const size = Size.square(150);
    final early = EchoRippleGeometry.sample(size, 0.10);
    final later = EchoRippleGeometry.sample(size, 0.20);

    expect(early.center, later.center);
    expect(later.rings.first.radius, greaterThan(early.rings.first.radius));

    // 所有环任意相位下的半径都不超出画布半边，不会被裁切。
    for (var progress = 0.0; progress < 1.0; progress += 0.05) {
      final frame = EchoRippleGeometry.sample(size, progress);
      final maxRadius = frame.rings
          .map((ring) => ring.radius)
          .reduce(math.max);
      final minEdgeDistance = [
        frame.center.dx,
        size.width - frame.center.dx,
        frame.center.dy,
        size.height - frame.center.dy,
      ].reduce(math.min);
      expect(maxRadius, lessThanOrEqualTo(minEdgeDistance));
    }
  });

  test('ripple opacity fades in at birth and reaches zero at loop wrap', () {
    const size = Size.square(150);

    // phase = 0：环出生，透明度从 0 开始。
    final born = EchoRippleGeometry.sample(size, 0.0);
    expect(born.rings.first.opacity, 0);

    // phase 接近 1：环消亡，透明度严格趋近 0，循环无缝衔接。
    final dying = EchoRippleGeometry.sample(size, 0.999);
    expect(dying.rings.first.opacity, lessThan(0.01));

    // 中段透明度为正。
    final mid = EchoRippleGeometry.sample(size, 0.5);
    expect(mid.rings.first.opacity, greaterThan(0.3));
  });

  test('all ripple phases share the same fixed center', () {
    const size = Size(180, 120);
    final centers = [0.0, 0.25, 0.5, 0.75]
        .map((progress) => EchoRippleGeometry.sample(size, progress).center)
        .toSet();

    expect(centers, hasLength(1));
  });
}
