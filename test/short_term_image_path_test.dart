import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('short-term-image-path');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('short_term_messages');
  });

  test('addShortTermMessage 写入 imagePath 并可读回', () async {
    final memoryService = MemoryService()..setAgentId('agent-img');
    await memoryService.addShortTermMessage(
      role: 'user',
      content: '看这张\n[图片]',
      imagePath: '/tmp/pic.jpg',
    );

    final rows = await DatabaseService.getShortTermMessages(
      agentId: 'agent-img',
    );
    expect(rows, hasLength(1));
    expect(rows.single.imagePath, '/tmp/pic.jpg');
    expect(rows.single.content, '看这张\n[图片]');
  });

  test('无图消息 imagePath 为 null', () async {
    final memoryService = MemoryService()..setAgentId('agent-img');
    await memoryService.addShortTermMessage(role: 'user', content: '纯文本');

    final rows = await DatabaseService.getShortTermMessages(
      agentId: 'agent-img',
    );
    expect(rows.single.imagePath, isNull);
  });

  test('getShortTermAsMessages 携带 image_path 键供视觉上下文构建', () async {
    final memoryService = MemoryService()..setAgentId('agent-img');
    await memoryService.addShortTermMessage(
      role: 'user',
      content: '[图片]',
      imagePath: '/tmp/pic.jpg',
    );
    await memoryService.addShortTermMessage(role: 'assistant', content: '看到了');

    final maps = memoryService.getShortTermAsMessages();
    expect(maps[0]['image_path'], '/tmp/pic.jpg');
    expect(maps[1]['image_path'], isNull);
  });

  test('getUnprocessedShortTermMessages 返回 image_path', () async {
    final memoryService = MemoryService()..setAgentId('agent-img');
    await memoryService.addShortTermMessage(
      role: 'user',
      content: '[图片]',
      imagePath: '/tmp/pic.jpg',
    );

    final unprocessed = await DatabaseService.getUnprocessedShortTermMessages(
      'agent-img',
    );
    expect(unprocessed, hasLength(1));
    expect(unprocessed.single['image_path'], '/tmp/pic.jpg');
  });

  test('updateShortTermContent 替换文本时保留 imagePath', () async {
    final memoryService = MemoryService()..setAgentId('agent-img');
    final msg = await memoryService.addShortTermMessage(
      role: 'user',
      content: '[图片]',
      imagePath: '/tmp/pic.jpg',
    );

    await memoryService.updateShortTermContent(msg.id, '描述文本');

    final inMemory = memoryService.shortTermMessages.single;
    expect(inMemory.content, '描述文本');
    expect(inMemory.imagePath, '/tmp/pic.jpg');
    final rows = await DatabaseService.getShortTermMessages(
      agentId: 'agent-img',
    );
    expect(rows.single.imagePath, '/tmp/pic.jpg');
  });
}
