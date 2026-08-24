import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aichat/widgets/sticker_panel.dart';

void main() {
  testWidgets('shows add and manage actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickerPanel(
            stickers: const [],
            onSelected: (_) {},
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.text('我的表情'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('uses a large square icon-only local image picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickerPanel(
            stickers: const [],
            onSelected: (_) {},
            onChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pump();

    final picker = find.byKey(const ValueKey('stickerImagePicker'));
    expect(picker, findsOneWidget);
    expect(tester.getSize(picker), const Size.square(128));
    expect(find.text('选择本地图片'), findsNothing);
  });
}
