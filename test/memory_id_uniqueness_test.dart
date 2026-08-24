import 'package:aichat/repositories/memory_repository.dart';
import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/group_service.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

/// 记忆 ID 全局唯一性测试：复现「跨智能体同号 + REPLACE 静默覆盖」的旧 bug，
/// 验证 UUID 化后两个智能体/两个群的首条记忆互不覆盖、各自可读回。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('memory-id-uniqueness');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('long_term_memories');
    await db.delete('base_memories');
    await db.delete('group_shared_memories');
    await db.delete('local_tombstones');
  });

  test('两个智能体的首条长期记忆互不覆盖（MemoryService）', () async {
    final memoryService = MemoryService();

    memoryService.setAgentId('agent-a');
    final idA = await memoryService.createLongTermMemory(
      field: 'status',
      content: 'A 的长期记忆',
    );

    memoryService.setAgentId('agent-b');
    final idB = await memoryService.createLongTermMemory(
      field: 'status',
      content: 'B 的长期记忆',
    );

    expect(idA, isNot(idB));
    expect(idA, startsWith('L-'));
    expect(idB, startsWith('L-'));

    final aMemories = await DatabaseService.getLongTermMemories(
      agentId: 'agent-a',
    );
    final bMemories = await DatabaseService.getLongTermMemories(
      agentId: 'agent-b',
    );
    expect(aMemories.map((m) => m.content), ['A 的长期记忆']);
    expect(bMemories.map((m) => m.content), ['B 的长期记忆']);
    expect(aMemories.single.id, idA);
    expect(bMemories.single.id, idB);

    // 新行 id 与 client_id 一致
    final db = await DatabaseService.database;
    final rows = await db.query('long_term_memories');
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['client_id'], row['id']);
    }
  });

  test('两个智能体的首条基础记忆互不覆盖（MemoryRepository）', () async {
    const repo = MemoryRepository();

    final idA = await repo.createBaseMemory(
      agentId: 'agent-a',
      type: 'event',
      content: 'A 的基础记忆',
    );
    final idB = await repo.createBaseMemory(
      agentId: 'agent-b',
      type: 'event',
      content: 'B 的基础记忆',
    );

    expect(idA, isNot(idB));
    expect(idA, startsWith('B-'));
    expect(idB, startsWith('B-'));

    final aMemories = await repo.getBaseMemories(agentId: 'agent-a');
    final bMemories = await repo.getBaseMemories(agentId: 'agent-b');
    expect(aMemories.map((m) => m.content), ['A 的基础记忆']);
    expect(bMemories.map((m) => m.content), ['B 的基础记忆']);

    final db = await DatabaseService.database;
    final rows = await db.query('base_memories');
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['client_id'], row['id']);
    }
  });

  test('两个群的首条共享记忆互不覆盖（GroupService）', () async {
    final groupService = GroupService();

    final idG1 = await groupService.createSharedMemory(
      groupId: 'group-1',
      field: 'status',
      content: '群1 的共享记忆',
    );
    final idG2 = await groupService.createSharedMemory(
      groupId: 'group-2',
      field: 'status',
      content: '群2 的共享记忆',
    );

    expect(idG1, isNot(idG2));
    expect(idG1, startsWith('GS-'));
    expect(idG2, startsWith('GS-'));

    final g1Memories = await groupService.getSharedMemories('group-1');
    final g2Memories = await groupService.getSharedMemories('group-2');
    expect(g1Memories.map((m) => m.content), ['群1 的共享记忆']);
    expect(g2Memories.map((m) => m.content), ['群2 的共享记忆']);

    final db = await DatabaseService.database;
    final rows = await db.query('group_shared_memories');
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['client_id'], row['id']);
    }
  });

  test('同一智能体连续创建多条记忆 id 均唯一', () async {
    final memoryService = MemoryService()..setAgentId('agent-a');

    final ids = <String>{};
    for (var i = 0; i < 5; i++) {
      ids.add(
        await memoryService.createLongTermMemory(
          field: 'status',
          content: '记忆 $i',
        ),
      );
      ids.add(
        await memoryService.createBaseMemory(type: 'event', content: '事件 $i'),
      );
    }
    expect(ids, hasLength(10));

    final memories = await memoryService.getLongTermMemories();
    expect(memories, hasLength(5));
  });
}
