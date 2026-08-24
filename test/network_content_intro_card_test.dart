import 'package:aichat/models/agent.dart';
import 'package:aichat/models/group_chat.dart';
import 'package:aichat/services/network_copy_policy.dart';
import 'package:aichat/widgets/network_content_intro_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('downloaded agent intro shows its description and worldview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkContentIntroCard.agent(
            agent: Agent(
              name: '林舟',
              persona: 'P',
              description: '夜行列车的引路人',
              worldview: '蒸汽与魔法共存的大陆',
              networkSource: NetworkCopySource.downloaded,
            ),
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('内容简介'), findsOneWidget);
    expect(find.byKey(const Key('network-content-archive')), findsOneWidget);
    expect(find.text('网络作品档案'), findsOneWidget);
    expect(find.text('夜行列车的引路人'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
    expect(
      find.byKey(const Key('network-content-section-worldview')),
      findsOneWidget,
    );
    expect(find.text('蒸汽与魔法共存的大陆'), findsOneWidget);
  });

  testWidgets('downloaded group intro summarizes setting and members', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkContentIntroCard.group(
            group: GroupChat(
              name: '月港茶会',
              description: '在月港相识',
              groupPersona: '慢节奏角色扮演',
              worldSetting: '海雾笼罩的港口',
              networkSource: NetworkCopySource.downloaded,
            ),
            memberNames: const ['黎明', '苏岚'],
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('群聊设定'), findsOneWidget);
    expect(find.text('慢节奏角色扮演'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('黎明、苏岚'), findsOneWidget);
  });
}
