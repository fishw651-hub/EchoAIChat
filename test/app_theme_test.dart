import 'package:aichat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'calm echo theme provides a translucent floating navigation surface',
    () {
    final theme = AppTheme.oceanLight();

    expect(AppTheme.echoSeed, const Color(0xFF557C95));
      expect(theme.navigationBarTheme.height, 68);
      expect(theme.navigationBarTheme.indicatorColor, isNotNull);
      expect(theme.navigationBarTheme.backgroundColor, isNotNull);
      expect(theme.dividerTheme.thickness, 0.5);
    },
  );

  test('dark calm echo theme remains a dark color scheme', () {
    expect(AppTheme.oceanDark().brightness, Brightness.dark);
  });
}
