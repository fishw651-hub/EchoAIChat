import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aichat/services/proactive_care_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late ProactiveCareStore store;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await database.execute(
      'CREATE TABLE chat_messages ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, '
      'short_mem_id TEXT, agent_id TEXT, group_id TEXT, '
      'image_path TEXT, image_paths TEXT)',
    );
    await database.execute(
      'CREATE TABLE short_term_messages ('
      'id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, '
      'timestamp INTEGER NOT NULL, agent_id TEXT, group_id TEXT, '
      'memory_ai_processed INTEGER DEFAULT 0, image_path TEXT, image_paths TEXT)',
    );
    await ProactiveCareStore.createTable(database);
    store = ProactiveCareStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertChat({
    required String role,
    required DateTime at,
    String content = 'message',
  }) async {
    await database.insert('chat_messages', {
      'role': role,
      'content': content,
      'timestamp': at.millisecondsSinceEpoch,
      'agent_id': 'a1',
    });
  }

  test('有效 claim 不可重复领取，过期后可以恢复', () async {
    final first = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12),
      dailyLimit: 2,
      minIntervalHours: 3,
      claimTtl: const Duration(minutes: 10),
    );
    expect(first, isNotNull);

    final duplicate = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12, 5),
      dailyLimit: 2,
      minIntervalHours: 3,
      claimTtl: const Duration(minutes: 10),
    );
    expect(duplicate, isNull);

    final recovered = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12, 11),
      dailyLimit: 2,
      minIntervalHours: 3,
      claimTtl: const Duration(minutes: 10),
    );
    expect(recovered, isNotNull);
    expect(recovered!.token, isNot(first!.token));
  });

  test('pending 后用户已回复时允许未来再次领取', () async {
    final first = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 9),
      dailyLimit: 2,
      minIntervalHours: 3,
    );
    expect(first, isNotNull);
    expect(
      await store.commit(
        first!,
        content: '主动关心',
        sentAt: DateTime(2026, 8, 12, 9),
      ),
      isTrue,
    );

    await insertChat(role: 'user', at: DateTime(2026, 8, 12, 9, 5));
    await insertChat(role: 'assistant', at: DateTime(2026, 8, 12, 9, 6));

    final next = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 13),
      dailyLimit: 2,
      minIntervalHours: 3,
    );
    expect(next, isNotNull);
  });

  test('没有用户回复时 pending 会阻止再次领取', () async {
    final first = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 9),
      dailyLimit: 2,
      minIntervalHours: 3,
    );
    await store.commit(
      first!,
      content: '主动关心',
      sentAt: DateTime(2026, 8, 12, 9),
    );

    expect(
      await store.claim(
        agentId: 'a1',
        now: DateTime(2026, 8, 12, 13),
        dailyLimit: 2,
        minIntervalHours: 3,
      ),
      isNull,
    );
  });

  test('claim 后聊天变化时拒绝提交主动消息并释放 claim', () async {
    final claim = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12),
      dailyLimit: 2,
      minIntervalHours: 3,
    );
    expect(claim, isNotNull);

    await insertChat(role: 'user', at: DateTime(2026, 8, 12, 12, 1));
    expect(
      await store.commit(
        claim!,
        content: '不应落库',
        sentAt: DateTime(2026, 8, 12, 12, 2),
      ),
      isFalse,
    );

    final rows = await database.query(
      'chat_messages',
      where: 'agent_id = ? AND content = ?',
      whereArgs: ['a1', '不应落库'],
    );
    expect(rows, isEmpty);

    final state = await database.query(
      'proactive_care_state',
      where: 'agent_id = ?',
      whereArgs: ['a1'],
      limit: 1,
    );
    expect(state.single['claim_token'], isNull);
  });

  test('状态行提交失败时不写入任何主动消息', () async {
    final claim = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12),
      dailyLimit: 2,
      minIntervalHours: 3,
    );
    expect(claim, isNotNull);

    await database.execute('''
      CREATE TRIGGER ignore_proactive_state_update
      BEFORE UPDATE ON proactive_care_state
      BEGIN
        SELECT RAISE(IGNORE);
      END
    ''');

    expect(
      await store.commit(
        claim!,
        content: '不应落库',
        sentAt: DateTime(2026, 8, 12, 12, 1),
      ),
      isFalse,
    );
    final messages = await database.query(
      'chat_messages',
      where: 'agent_id = ?',
      whereArgs: ['a1'],
    );
    expect(messages, isEmpty);
  });

  test('过期 claim 不能再提交主动消息', () async {
    final claim = await store.claim(
      agentId: 'a1',
      now: DateTime(2026, 8, 12, 12),
      dailyLimit: 2,
      minIntervalHours: 3,
      claimTtl: const Duration(minutes: 10),
    );
    expect(claim, isNotNull);

    expect(
      await store.commit(
        claim!,
        content: '过期消息',
        sentAt: DateTime(2026, 8, 12, 12, 10),
      ),
      isFalse,
    );
    final messages = await database.query(
      'chat_messages',
      where: 'agent_id = ?',
      whereArgs: ['a1'],
    );
    expect(messages, isEmpty);
  });
}
