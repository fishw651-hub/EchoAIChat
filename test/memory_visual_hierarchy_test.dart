import 'package:aichat/theme/app_theme.dart';
import 'package:aichat/widgets/echo_visual_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile header communicates count and editability', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(body: EchoProfileHeader(totalCount: 6, onEdit: () {})),
      ),
    );

    expect(find.text('我眼中的你'), findsOneWidget);
    expect(find.text('已沉淀 6 条可信观察'), findsOneWidget);
    expect(find.text('管理画像'), findsOneWidget);
    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
  });
}
