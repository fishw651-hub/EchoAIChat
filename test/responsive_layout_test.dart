import 'package:aichat/utils/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('平板宽度不启用固定左侧栏的桌面布局', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1080, 1920)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Text(
              ResponsiveLayout.isDesktop(context) ? 'desktop' : 'full-width',
            ),
          ),
        ),
      ),
    );

    expect(find.text('full-width'), findsOneWidget);
  });

  testWidgets('足够宽的桌面窗口仍启用桌面布局', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Text(
              ResponsiveLayout.isDesktop(context) ? 'desktop' : 'full-width',
            ),
          ),
        ),
      ),
    );

    expect(find.text('desktop'), findsOneWidget);
  });
}
