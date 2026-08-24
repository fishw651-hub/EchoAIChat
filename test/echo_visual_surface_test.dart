import 'package:aichat/theme/app_theme.dart';
import 'package:aichat/widgets/echo_visual_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calm echo theme uses the muted mist-blue seed', () {
    expect(AppTheme.echoSeed, const Color(0xFF557C95));
    expect(AppTheme.oceanLight().colorScheme.primary, isNotNull);
  });

  testWidgets('echo panel exposes a calm rounded surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: const Scaffold(body: EchoPanel(child: Text('内容'))),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '回响内容面板',
      ),
      findsOneWidget,
    );
  });

  testWidgets('bubble corners identify user and agent messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: const Scaffold(
          body: Column(
            children: [
              EchoBubbleSurface(isUser: false, child: Text('智能体消息')),
              EchoBubbleSurface(isUser: true, child: Text('用户消息')),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '智能体消息气泡',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '用户消息气泡',
      ),
      findsOneWidget,
    );

    final agent = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('echo-agent-bubble')),
    );
    final user = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('echo-user-bubble')),
    );
    final agentDecoration = agent.decoration! as BoxDecoration;
    final userDecoration = user.decoration! as BoxDecoration;
    final agentRadius = agentDecoration.borderRadius! as BorderRadius;
    final userRadius = userDecoration.borderRadius! as BorderRadius;

    expect(agentRadius.bottomLeft.x, 6);
    expect(userRadius.bottomRight.x, 6);
  });
}
