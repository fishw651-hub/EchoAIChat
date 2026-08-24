import 'package:aichat/l10n/app_localizations.dart';
import 'package:aichat/widgets/time_divider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowTimeDivider', () {
    final base = DateTime(2026, 7, 23, 10, 0);

    test('首条消息（previous 为 null）总是显示', () {
      expect(shouldShowTimeDivider(base, null), isTrue);
    });

    test('间隔小于 5 分钟不显示', () {
      expect(
        shouldShowTimeDivider(
          base.add(const Duration(minutes: 3)),
          base,
        ),
        isFalse,
      );
    });

    test('间隔恰好 5 分钟不显示', () {
      expect(
        shouldShowTimeDivider(
          base.add(const Duration(minutes: 5)),
          base,
        ),
        isFalse,
      );
    });

    test('间隔超过 5 分钟显示', () {
      expect(
        shouldShowTimeDivider(
          base.add(const Duration(minutes: 5, seconds: 1)),
          base,
        ),
        isTrue,
      );
    });

    test('跨天长时间间隔显示', () {
      expect(
        shouldShowTimeDivider(base.add(const Duration(days: 2)), base),
        isTrue,
      );
    });
  });

  group('formatTimeDivider', () {
    final now = DateTime(2026, 7, 23, 15, 30);
    final zh = AppLocalizations(const Locale('zh'));

    test('今天的消息只显示 HH:mm', () {
      final t = DateTime(2026, 7, 23, 9, 5);
      expect(formatTimeDivider(t, zh, now: now), '09:05');
    });

    test('昨天的消息带"昨天"前缀', () {
      final t = DateTime(2026, 7, 22, 22, 10);
      expect(formatTimeDivider(t, zh, now: now), '昨天 22:10');
    });

    test('今年更早的日期显示月日和时间', () {
      final t = DateTime(2026, 3, 8, 8, 0);
      expect(formatTimeDivider(t, zh, now: now), '3月8日 08:00');
    });

    test('更早的年份显示完整日期', () {
      final t = DateTime(2024, 12, 31, 23, 59);
      expect(formatTimeDivider(t, zh, now: now), '2024年12月31日 23:59');
    });
  });
}
