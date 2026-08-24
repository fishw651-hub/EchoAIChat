import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aichat/utils/screenshot_import_intro.dart';
import 'package:aichat/l10n/app_localizations.dart';

Widget _host({required void Function(BuildContext) onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => onTap(ctx),
          child: const Text('tap'),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次点击弹引导窗，确认后标记已展示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? result;
    await tester.pumpWidget(_host(onTap: (ctx) async {
      result = await ScreenshotImportIntro.ensureShown(ctx);
    }));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();

    // 引导文案与两个按钮出现
    expect(find.text('选择你的微信聊天截图，快速根据聊天内容复制出你所想之人'), findsOneWidget);
    expect(find.text('选择截图'), findsOneWidget);

    await tester.tap(find.text('选择截图'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('screenshot_import_intro_shown'), isTrue);
  });

  testWidgets('取消不标记，下次仍弹窗', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? result;
    await tester.pumpWidget(_host(onTap: (ctx) async {
      result = await ScreenshotImportIntro.ensureShown(ctx);
    }));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppLocalizations.currentLocale.languageCode == 'zh' ? '取消' : 'cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('screenshot_import_intro_shown'), isNot(true));
  });

  testWidgets('已展示过直接放行不弹窗', (tester) async {
    SharedPreferences.setMockInitialValues({'screenshot_import_intro_shown': true});
    bool? result;
    await tester.pumpWidget(_host(onTap: (ctx) async {
      result = await ScreenshotImportIntro.ensureShown(ctx);
    }));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('选择截图'), findsNothing);
  });
}
