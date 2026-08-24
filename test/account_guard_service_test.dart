import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/services/account_guard_service.dart';

void main() {
  group('AccountGuardService.parseBan', () {
    test('not banned when banned=false', () {
      final s = AccountGuardService.parseBan({'banned': false});
      expect(s.banned, isFalse);
      expect(s.remainingDays, 0);
    });

    test('banned with ban_days fallback when ban_until missing', () {
      final s = AccountGuardService.parseBan({
        'banned': true,
        'ban_days': 4,
      });
      expect(s.banned, isTrue);
      expect(s.banDays, 4);
      expect(s.remainingDays, 4);
      expect(s.banUntil, isNull);
    });

    test('remaining days computed from ban_until (ceil)', () {
      final now = DateTime(2026, 7, 24, 12, 0);
      final until = now.add(const Duration(hours: 30)); // 1.25 天 → 2 天
      final s = AccountGuardService.parseBan({
        'banned': true,
        'ban_days': 2,
        'ban_until': until.toUtc().toIso8601String(),
      }, now: now);
      expect(s.banned, isTrue);
      expect(s.remainingDays, 2);
      expect(s.banUntil, isNotNull);
    });

    test('expired ban_until treated as not banned', () {
      final now = DateTime(2026, 7, 24, 12, 0);
      final s = AccountGuardService.parseBan({
        'banned': true,
        'ban_days': 1,
        'ban_until': now
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      }, now: now);
      expect(s.banned, isFalse);
    });

    test('login response field device_banned is honored', () {
      final s = AccountGuardService.parseBan({
        'device_banned': true,
        'ban_days': 1,
      });
      expect(s.banned, isTrue);
    });
  });
}
