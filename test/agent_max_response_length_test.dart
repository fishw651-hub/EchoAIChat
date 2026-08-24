import 'package:aichat/models/agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('回复字数默认值和导入值会被持久化', () {
    final agent = Agent(name: '角色', persona: '人设');

    expect(agent.toMap()['max_response_length'], 300);

    final restored = Agent.fromMap({
      ...agent.toMap(),
      'max_response_length': 800,
    });
    expect(restored.toMap()['max_response_length'], 800);
  });
}
