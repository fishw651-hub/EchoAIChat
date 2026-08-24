import 'package:aichat/models/agent.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud merge keeps the local id for an existing agent', () {
    final local = Agent(
      id: 'local-agent-id',
      name: '角色',
      persona: '旧人设',
      openingLine: '旧开场',
      maxResponseLength: 120,
      createdAt: 100,
      updatedAt: 100,
    );

    final merged = mergeCloudAgent(
      {
        'name': '角色',
        'persona': '云端人设',
        'opening_line': '云端开场',
        'max_response_length': 650,
      },
      local,
    );

    expect(merged.id, local.id);
    expect(merged.persona, '云端人设');
    expect(merged.openingLine, '云端开场');
    expect(merged.maxResponseLength, 650);
    expect(merged.createdAt, local.createdAt);
  });
}
