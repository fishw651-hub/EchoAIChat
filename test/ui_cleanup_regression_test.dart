import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync policy failure offers recovery instead of an endless spinner', () {
    final source = File(
      'lib/screens/sync_devices_screen.dart',
    ).readAsStringSync();

    expect(source, contains("key: const ValueKey('syncPolicyError')"));
    expect(source, contains("key: const ValueKey('syncPolicyRetry')"));
  });

  test('theme color preference is completely removed', () {
    final settingsSource = File(
      'lib/screens/settings_screen.dart',
    ).readAsStringSync();
    final providerSource = File(
      'lib/providers/settings_provider.dart',
    ).readAsStringSync();

    expect(settingsSource, isNot(contains("l10n.get('themeColor')")));
    expect(settingsSource, isNot(contains('updatePrimaryColor')));
    expect(providerSource, isNot(contains('primaryColor')));
  });

  test('home header no longer renders a time-based greeting', () {
    final source = File('lib/screens/home_tab_screen.dart').readAsStringSync();

    expect(source, isNot(contains('_greeting()')));
    expect(source, isNot(contains('String _greeting')));
  });

  test('account and settings use the calm echo page structure', () {
    final accountSource = File(
      'lib/screens/account_screen.dart',
    ).readAsStringSync();
    final settingsSource = File(
      'lib/screens/settings_screen.dart',
    ).readAsStringSync();

    expect(
      accountSource,
      contains("key: const ValueKey('accountProfileHero')"),
    );
    expect(settingsSource, contains("key: const ValueKey('settingsOverview')"));
  });

  test(
    'settings keeps the initial render lazy and touch effects lightweight',
    () {
      final settingsSource = File(
        'lib/screens/settings_screen.dart',
      ).readAsStringSync();
      final themeSource = File('lib/theme/app_theme.dart').readAsStringSync();

      expect(settingsSource, contains('ListView.builder'));
      expect(themeSource, contains('splashFactory: InkRipple.splashFactory'));
      expect(themeSource, isNot(contains('InkSparkle.splashFactory')));
    },
  );

  test('home defers heavy tabs until they are visited', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(source, contains('_LazyIndexedStack'));
    expect(source, isNot(contains('body: IndexedStack(')));
    expect(source, isNot(contains('child: IndexedStack(')));
  });

  test('app shell only rebuilds for settings that affect the shell', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('settingsProvider.select'));
    expect(source, isNot(contains('ref.watch(settingsProvider);')));
  });

  test('settings does not persist every memory-round keystroke', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();

    expect(source, contains('_roundsSaveTimer'));
    expect(source, contains('onEditingComplete'));
  });
}
