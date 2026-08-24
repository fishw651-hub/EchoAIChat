import 'package:aichat/services/chat_send_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatSendPolicy.canSend', () {
    test('有文字可发送', () {
      expect(
        ChatSendPolicy.canSend(
          hasText: true,
          hasPendingImages: false,
          isSending: false,
        ),
        isTrue,
      );
    });

    test('仅暂存图（无文字）也可发送', () {
      expect(
        ChatSendPolicy.canSend(
          hasText: false,
          hasPendingImages: true,
          isSending: false,
        ),
        isTrue,
      );
    });

    test('无文字且无暂存图不可发送', () {
      expect(
        ChatSendPolicy.canSend(
          hasText: false,
          hasPendingImages: false,
          isSending: false,
        ),
        isFalse,
      );
    });

    test('AI 回复中（isSending）一律不可发送', () {
      expect(
        ChatSendPolicy.canSend(
          hasText: true,
          hasPendingImages: true,
          isSending: true,
        ),
        isFalse,
      );
    });
  });
}
