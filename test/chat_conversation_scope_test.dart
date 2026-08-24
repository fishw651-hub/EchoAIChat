import 'package:aichat/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps an in-flight reply scoped to its original agent', () {
    const scope = ChatConversationScope('agent-a');

    expect(scope.isCurrent('agent-a'), isTrue);
    expect(scope.isCurrent('agent-b'), isFalse);
  });
}
