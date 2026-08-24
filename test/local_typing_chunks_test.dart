import 'package:aichat/services/local_typing_chunks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localTypingChunks', () {
    test('拼接后与原文完全一致', () {
      const text = '你好，Echo!\n第二行。';
      expect(localTypingChunks(text).join(), text);
    });

    test('不拆分组合 emoji 字素簇', () {
      const family = '👨‍👩‍👧‍👦';
      final text = ['A', family, '好'].join();
      final chunks = localTypingChunks(text);

      expect(chunks.join(), text);
      expect(chunks, contains(family));
    });

    test('长文本自适应限制动画步骤', () {
      final text = List.filled(1000, '字').join();
      final chunks = localTypingChunks(text, maxSteps: 120);

      expect(chunks, hasLength(lessThanOrEqualTo(120)));
      expect(chunks.join(), text);
    });

    test('空文本不产生动画步骤', () {
      expect(localTypingChunks(''), isEmpty);
    });
  });
}
