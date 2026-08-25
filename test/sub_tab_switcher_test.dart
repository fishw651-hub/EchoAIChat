import 'package:aichat/widgets/liquid_glass_surface.dart';
import 'package:aichat/widgets/sub_tab_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({bool secondSelected = false}) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF557C95)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: SubTabSwitcher(
            firstLabel: '智能体',
            secondLabel: '群聊',
            firstIcon: Icons.person_outline_rounded,
            secondIcon: Icons.groups_outlined,
            secondSelected: secondSelected,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('uses the shared glass surface for the sub tab switcher', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byType(LiquidGlassSurface), findsNWidgets(2));
    expect(find.byKey(const Key('sub-tab-glass-surface')), findsOneWidget);
    expect(
      find.byKey(const Key('sub-tab-selected-glass-surface')),
      findsOneWidget,
    );
    final blur = tester.widget<BackdropFilter>(
      find.byKey(const Key('sub-tab-glass-blur')),
    );
    expect(blur.filter.toString(), startsWith('ImageFilter.blur('));
  });

  testWidgets('keeps switching behavior while moving the glass thumb', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF557C95)),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: SubTabSwitcher(
            firstLabel: '智能体',
            secondLabel: '群聊',
            firstIcon: Icons.person_outline_rounded,
            secondIcon: Icons.groups_outlined,
            secondSelected: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('群聊'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });
}
