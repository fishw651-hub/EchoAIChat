import 'package:aichat/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('center create action exposes agent and group choices', (
    tester,
  ) async {
    var createdAgent = false;
    var createdGroup = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MobileCreateAction(
              onCreateAgent: () => createdAgent = true,
              onCreateGroup: () => createdGroup = true,
            ),
          ),
        ),
      ),
    );

    final addIcon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
    expect(addIcon.size, 32);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Material && widget.shape is CircleBorder,
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('home-create-button')));
    await tester.pump();

    expect(
      find.byKey(const Key('create-menu-enter-animation')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const Key('create-menu-enter-animation'))),
      isA<SlideTransition>(),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create-agent-action')), findsOneWidget);
    expect(find.byKey(const Key('create-group-action')), findsOneWidget);
    expect(find.text('从零开始打造专属角色'), findsOneWidget);
    expect(find.text('邀请多个智能体一起交流'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-agent-action')));
    await tester.pumpAndSettle();
    expect(createdAgent, isTrue);
    expect(createdGroup, isFalse);
  });
}
