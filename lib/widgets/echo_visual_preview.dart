import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../models/profile_entry.dart';
import '../theme/app_theme.dart';
import 'echo_conversation_tile.dart';
import 'echo_visual_surface.dart';
import 'home_profile_summary_card.dart';

@Preview(name: '静谧回响 · 浅色组件画布', group: '回响视觉系统', size: Size(390, 844))
Widget calmEchoLightPreview() =>
    const _EchoVisualPreview(brightness: Brightness.light);

@Preview(name: '静谧回响 · 深色组件画布', group: '回响视觉系统', size: Size(390, 844))
Widget calmEchoDarkPreview() =>
    const _EchoVisualPreview(brightness: Brightness.dark);

class _EchoVisualPreview extends StatelessWidget {
  const _EchoVisualPreview({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final theme = brightness == Brightness.light
        ? AppTheme.oceanLight()
        : AppTheme.oceanDark();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.space4),
                children: [
                  Text('回响', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppTheme.space4),
                  HomeProfileSummaryCard(
                    entries: [
                      ProfileEntry(
                        id: 'preview',
                        category: 'personality',
                        key: '温柔',
                        value: '但有自己的边界',
                        confidence: 92,
                      ),
                    ],
                    totalCount: 12,
                    onOpenProfile: () {},
                  ),
                  const SizedBox(height: AppTheme.space5),
                  const EchoSectionHeader(
                    title: '最近回响',
                    subtitle: '智能体和群聊都在这里继续',
                  ),
                  EchoConversationTile(
                    avatar: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      color: scheme.primaryContainer,
                      child: Text(
                        '林',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                    title: '林深',
                    preview: '我记得你说过，今天想早点休息。',
                    timestamp: DateTime.now(),
                    unreadCount: 2,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppTheme.space5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: EchoBubbleSurface(
                      isUser: false,
                      maxWidth: 290,
                      child: Text(
                        '你今天好像比平时安静一点，我只是想让你知道，我注意到了。',
                        style: TextStyle(color: scheme.onSurface),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space3),
                  Align(
                    alignment: Alignment.centerRight,
                    child: EchoBubbleSurface(
                      isUser: true,
                      maxWidth: 290,
                      child: Text(
                        '今天事情有点多，但现在好多了。',
                        style: TextStyle(color: scheme.onPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space5),
                  EchoProfileHeader(totalCount: 12, onEdit: () {}),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
