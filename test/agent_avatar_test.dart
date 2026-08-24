import 'package:aichat/widgets/agent_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AgentAvatar shows uppercase initial', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentAvatar(
            name: 'echo',
            avatarColor: 0xFF42A5F5,
          ),
        ),
      ),
    );

    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('AgentAvatar falls back to question mark when name is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentAvatar(
            name: '',
            avatarColor: 0xFF42A5F5,
          ),
        ),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });
}
