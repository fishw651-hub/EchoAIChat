import 'package:aichat/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthState sync entitlement', () {
    test(
      'does not allow sync when subscription exists but allow_sync is false',
      () {
        const state = AuthState(
          isLoggedIn: true,
          subscription: {'plan_name': 'Basic', 'allow_sync': false},
        );

        expect(state.hasActiveSubscription, isTrue);
        expect(state.canUseSync, isFalse);
      },
    );

    test(
      'allows sync only for logged-in subscriptions with allow_sync true',
      () {
        const loggedOut = AuthState(
          isLoggedIn: false,
          subscription: {'plan_name': 'Pro', 'allow_sync': true},
        );
        const loggedIn = AuthState(
          isLoggedIn: true,
          subscription: {'plan_name': 'Pro', 'allow_sync': true},
        );

        expect(loggedOut.canUseSync, isFalse);
        expect(loggedIn.canUseSync, isTrue);
      },
    );

    test('allows sync from a fresh local subscription cache', () {
      final now = DateTime(2026, 8, 16, 12);
      final state = AuthState(
        isLoggedIn: true,
        subscription: const {
          'plan_name': 'Pro',
          'allow_sync': true,
          'expires_at': '2026-08-20',
        },
        subscriptionCachedAt: now.subtract(
          AuthState.subscriptionCacheTtl - const Duration(minutes: 1),
        ),
      );

      expect(state.canUseSyncAt(now), isTrue);
    });

    test('does not allow sync when the local subscription cache is stale', () {
      final now = DateTime(2026, 8, 16, 12);
      final state = AuthState(
        isLoggedIn: true,
        subscription: const {
          'plan_name': 'Pro',
          'allow_sync': true,
          'expires_at': '2026-08-20',
        },
        subscriptionCachedAt: now.subtract(
          AuthState.subscriptionCacheTtl + const Duration(minutes: 1),
        ),
      );

      expect(state.canUseSyncAt(now), isFalse);
    });

    test('does not allow sync after the cached subscription expires', () {
      final now = DateTime(2026, 8, 21, 12);
      final state = AuthState(
        isLoggedIn: true,
        subscription: const {
          'plan_name': 'Pro',
          'allow_sync': true,
          'expires_at': '2026-08-20',
        },
        subscriptionCachedAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(state.canUseSyncAt(now), isFalse);
    });
  });
}
