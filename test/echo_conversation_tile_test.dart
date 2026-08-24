import 'package:aichat/l10n/app_localizations.dart';
import 'package:aichat/theme/app_theme.dart';
import 'package:aichat/widgets/echo_conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 组件未提供 Localizations 代理时回退到 currentLocale，断言为中文文案
  AppLocalizations.currentLocale = const Locale('zh');
  testWidgets('renders a flat wechat-style conversation row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: EchoConversationTile(
            avatar: const SizedBox(key: Key('avatar'), width: 48, height: 48),
            title: '林夏',
            preview: '今天过得怎么样？',
            timestamp: DateTime.now(),
            unreadCount: 2,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('avatar')), findsOneWidget);
    expect(find.text('林夏'), findsOneWidget);
    expect(find.text('今天过得怎么样？'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const Key('conversation-divider')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '与林夏的会话',
      ),
      findsOneWidget,
    );
  });
}
