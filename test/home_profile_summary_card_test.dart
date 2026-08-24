import 'package:aichat/l10n/app_localizations.dart';
import 'package:aichat/models/profile_entry.dart';
import 'package:aichat/theme/app_theme.dart';
import 'package:aichat/widgets/home_profile_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 组件未提供 Localizations 代理时回退到 currentLocale，断言为中文文案
  AppLocalizations.currentLocale = const Locale('zh');
  testWidgets('profile hero shows a clear relationship summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: HomeProfileSummaryCard(
            entries: [
              ProfileEntry(
                id: '1',
                category: 'personality',
                key: '理性',
                value: '偏好先给结论',
                confidence: 90,
              ),
            ],
            totalCount: 1,
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('我眼中的你'), findsOneWidget);
    expect(find.text('由 1 条观察构成'), findsOneWidget);
    expect(find.textContaining('理性'), findsOneWidget);
    expect(find.text('查看完整画像'), findsOneWidget);
  });

  testWidgets('empty profile hero explains how the portrait grows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: HomeProfileSummaryCard(
            entries: const [],
            totalCount: 0,
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('对话会慢慢沉淀成你独有的画像'), findsOneWidget);
    expect(find.text('和智能体聊得越久，它越能理解你。'), findsOneWidget);
  });

  testWidgets('profile hero uses compact animated echo decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: HomeProfileSummaryCard(
            entries: [
              ProfileEntry(id: '1', category: 'health', key: '健康', value: '规律'),
            ],
            totalCount: 1,
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('homeProfileVoiceWave')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeProfileOrbitRings')), findsOneWidget);
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('homeProfileCardSurface')),
    );
    expect(surface.constraints?.minHeight, lessThanOrEqualTo(168));
  });

  testWidgets('remembered profile copy rotates every four seconds', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 19, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: HomeProfileSummaryCard(
            entries: [
              ProfileEntry(
                id: '1',
                category: 'health',
                key: '健康',
                value: '规律',
                updatedAt: now,
              ),
              ProfileEntry(
                id: '2',
                category: 'social',
                key: '社交',
                value: '和睦',
                updatedAt: now.subtract(const Duration(minutes: 1)),
              ),
              ProfileEntry(
                id: '3',
                category: 'interests',
                key: '兴趣',
                value: '画画',
                updatedAt: now.subtract(const Duration(minutes: 2)),
              ),
            ],
            totalCount: 3,
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('社交'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.textContaining('兴趣'), findsOneWidget);
  });

  testWidgets('remembered profile copy stays still when motion is reduced', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 19, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: HomeProfileSummaryCard(
              entries: [
                ProfileEntry(
                  id: '1',
                  category: 'health',
                  key: '健康',
                  value: '规律',
                  updatedAt: now,
                ),
                ProfileEntry(
                  id: '2',
                  category: 'social',
                  key: '社交',
                  value: '和睦',
                  updatedAt: now.subtract(const Duration(minutes: 1)),
                ),
                ProfileEntry(
                  id: '3',
                  category: 'interests',
                  key: '兴趣',
                  value: '画画',
                  updatedAt: now.subtract(const Duration(minutes: 2)),
                ),
              ],
              totalCount: 3,
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 8));
    expect(find.textContaining('社交'), findsOneWidget);
    expect(find.textContaining('兴趣'), findsNothing);
  });
}
