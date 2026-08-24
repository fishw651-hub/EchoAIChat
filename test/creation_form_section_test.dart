import 'package:aichat/widgets/creation_form_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creation form sections expose quick and submit actions', (
    tester,
  ) async {
    var aiTapped = false;
    var importTapped = false;
    var createTapped = false;
    var uploadTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const CreationFormSection(
                  title: '基础信息',
                  description: '先完成最重要的内容',
                  child: Text('表单内容'),
                ),
                CreationQuickActions(
                  primaryLabel: 'AI 帮我创建',
                  primaryIcon: Icons.auto_fix_high,
                  onPrimaryPressed: () => aiTapped = true,
                  secondaryLabel: '从聊天导入',
                  secondaryIcon: Icons.document_scanner_outlined,
                  onSecondaryPressed: () => importTapped = true,
                ),
                CreationSubmitActions(
                  primaryLabel: '创建并开始聊天',
                  uploadLabel: '创建并上传到网络市场',
                  onPrimaryPressed: () => createTapped = true,
                  onUploadPressed: () => uploadTapped = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('基础信息'), findsOneWidget);
    expect(find.text('先完成最重要的内容'), findsOneWidget);
    expect(find.text('表单内容'), findsOneWidget);

    await tester.tap(find.text('AI 帮我创建'));
    await tester.tap(find.text('从聊天导入'));
    await tester.tap(find.text('创建并开始聊天'));
    await tester.tap(find.text('创建并上传到网络市场'));

    expect(aiTapped, isTrue);
    expect(importTapped, isTrue);
    expect(createTapped, isTrue);
    expect(uploadTapped, isTrue);
  });

  testWidgets('creation submit actions disable both paths while saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreationSubmitActions(
            primaryLabel: '创建',
            uploadLabel: '创建并上传到网络市场',
            loading: true,
            onPrimaryPressed: () {},
            onUploadPressed: () {},
          ),
        ),
      ),
    );

    final filledButton = tester.widget<FilledButton>(
      find.byKey(const Key('creation-primary-submit')),
    );
    final uploadButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('creation-upload-submit')),
    );

    expect(filledButton.onPressed, isNull);
    expect(uploadButton.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
