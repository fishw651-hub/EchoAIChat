import 'package:aichat/widgets/network_reject_reason.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('手机宽度下拒绝理由完整换行且不溢出', (tester) async {
    const reason = '人设描述包含不适合公开发布的内容，请删除相关段落后重新提交审核。';
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(12),
            child: NetworkRejectReason(label: '拒绝理由', reason: reason),
          ),
        ),
      ),
    );

    expect(find.text('拒绝理由'), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    final reasonText = tester.widget<Text>(find.text(reason));
    expect(reasonText.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });
}
