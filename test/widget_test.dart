import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'package:aichat/main.dart';

void main() {
  testWidgets('App loads the first-run shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AIApp()),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding')), findsOneWidget);
  });
}
