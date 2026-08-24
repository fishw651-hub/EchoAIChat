import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('贴纸发送在聊天锁确认失败时提示并保留输入', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();
    final methodStart = source.indexOf('Future<void> _sendSticker');
    final methodEnd = source.indexOf('/// 选图', methodStart);

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final stickerSendMethod = source.substring(methodStart, methodEnd);
    expect(stickerSendMethod, contains("get('syncChatConflict')"));
    expect(
      stickerSendMethod.indexOf('if (!acquired)'),
      lessThan(stickerSendMethod.indexOf('_controller.clear()')),
      reason: '必须在清空输入框之前处理聊天锁确认失败',
    );
  });
}
