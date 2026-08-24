import 'package:aichat/models/short_term_message.dart';
import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open(
      'memory-service-agent-isolation',
    );
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('short_term_messages');
  });

  test('两个智能体的首条短期消息不会互相覆盖', () async {
    final memoryService = MemoryService();

    memoryService.setAgentId('agent-a');
    await memoryService.addShortTermMessage(role: 'user', content: 'A 的消息');

    memoryService.setAgentId('agent-b');
    await memoryService.addShortTermMessage(role: 'user', content: 'B 的消息');

    final agentAMessages = await DatabaseService.getShortTermMessages(
      agentId: 'agent-a',
    );
    final agentBMessages = await DatabaseService.getShortTermMessages(
      agentId: 'agent-b',
    );

    expect(agentAMessages.map((message) => message.content), ['A 的消息']);
    expect(agentBMessages.map((message) => message.content), ['B 的消息']);
  });

  test('旧智能体的迟到加载不会覆盖当前智能体内存', () async {
    await DatabaseService.insertShortTermMessage(
      ShortTermMessage(
        id: 'agent-a-message',
        role: 'user',
        content: 'A 的历史消息',
        agentId: 'agent-a',
      ),
    );
    final memoryService = MemoryService()..setAgentId('agent-a');

    final staleLoad = memoryService.loadShortTermFromDb(20);
    memoryService.setAgentId('agent-b');
    await staleLoad;

    expect(memoryService.agentId, 'agent-b');
    expect(memoryService.shortTermMessages, isEmpty);
  });
}
