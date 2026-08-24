import 'package:aichat/services/sync_response_applier.dart';
import 'package:aichat/services/sync_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await database.execute(
      'CREATE TABLE agents ('
      'id TEXT PRIMARY KEY, client_id TEXT UNIQUE, name TEXT NOT NULL, '
      'sync_updated_at INTEGER)',
    );
    await database.execute(
      'CREATE TABLE chat_messages ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT UNIQUE, '
      'agent_id TEXT, content TEXT NOT NULL, sync_updated_at INTEGER)',
    );
    for (final table in [
      'short_term_messages',
      'long_term_memories',
      'base_memories',
      'planned_messages',
    ]) {
      await database.execute(
        'CREATE TABLE $table ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT UNIQUE, '
        'agent_id TEXT, group_id TEXT, content TEXT)',
      );
    }
    await database.execute(
      'CREATE TABLE local_tombstones ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT, '
      'client_id TEXT, agent_id TEXT, created_at INTEGER)',
    );
  });

  tearDown(() => database.close());

  test('applies and acknowledges only rows inside selected scope', () async {
    await database.insert('agents', {
      'id': 'agent-a',
      'client_id': 'agent-a',
      'name': 'old-a',
    });
    await database.insert('agents', {
      'id': 'agent-b',
      'client_id': 'agent-b',
      'name': 'old-b',
    });
    final tombstoneA = await database.insert('local_tombstones', {
      'table_name': 'chat_messages',
      'client_id': 'deleted-a',
      'agent_id': 'agent-a',
      'created_at': 1,
    });
    final tombstoneB = await database.insert('local_tombstones', {
      'table_name': 'chat_messages',
      'client_id': 'deleted-b',
      'agent_id': 'agent-b',
      'created_at': 1,
    });

    await SyncResponseApplier(database).apply(
      scope: SyncScope.oneShot({'agent-a'}),
      tables: {
        'agents': [
          {'ClientID': 'agent-a', 'Name': 'new-a'},
          {'ClientID': 'agent-b', 'Name': 'must-not-apply'},
        ],
      },
      tombstones: [
        {'TableName': 'agents', 'ClientID': 'agent-b'},
      ],
      acknowledgedTombstoneIds: {tombstoneA},
    );

    final agentA = (await database.query(
      'agents',
      where: 'id = ?',
      whereArgs: ['agent-a'],
    )).single;
    final agentB = (await database.query(
      'agents',
      where: 'id = ?',
      whereArgs: ['agent-b'],
    )).single;
    expect(agentA['name'], 'new-a');
    expect(agentB['name'], 'old-b');
    expect(
      (await database.query(
        'local_tombstones',
      )).map((row) => row['id']).toSet(),
      {tombstoneB},
    );
  });

  test('failed table application keeps tombstones', () async {
    final tombstone = await database.insert('local_tombstones', {
      'table_name': 'chat_messages',
      'client_id': 'deleted-a',
      'agent_id': 'agent-a',
      'created_at': 1,
    });

    await expectLater(
      SyncResponseApplier(database).apply(
        scope: SyncScope.oneShot({'agent-a'}),
        tables: {
          'chat_messages': [
            {'ClientID': 'message-a', 'AgentID': 'agent-a'},
          ],
        },
        tombstones: const [],
        acknowledgedTombstoneIds: {tombstone},
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await database.query('local_tombstones'), hasLength(1));
  });

  test('ignores cloud metadata columns missing from the local table', () async {
    await SyncResponseApplier(database).apply(
      scope: SyncScope.oneShot({'agent-a'}),
      tables: {
        'chat_messages': [
          {
            'ClientID': 'message-a',
            'AgentID': 'agent-a',
            'Content': 'hello',
            'CreatedAt': '2026-07-08T22:53:54+08:00',
            'UpdatedAt': '2026-07-09T19:27:27+08:00',
          },
        ],
      },
      tombstones: const [],
      acknowledgedTombstoneIds: const {},
    );

    final message = (await database.query(
      'chat_messages',
      where: 'client_id = ?',
      whereArgs: ['message-a'],
    )).single;
    expect(message['agent_id'], 'agent-a');
    expect(message['content'], 'hello');
  });

  test('tombstone with agent_id does not delete another agent\'s row', () async {
    await database.insert('long_term_memories', {
      'client_id': 'legacy-collided-id',
      'agent_id': 'agent-a',
      'content': 'agent-a 的记忆',
    });

    // 墓碑指向同一 client_id 但属于 agent-b → 不得误删 agent-a 的行
    await SyncResponseApplier(database).apply(
      scope: SyncScope.all(),
      tables: const {},
      tombstones: [
        {
          'TableName': 'long_term_memories',
          'ClientID': 'legacy-collided-id',
          'AgentID': 'agent-b',
        },
      ],
      acknowledgedTombstoneIds: const {},
    );
    expect(await database.query('long_term_memories'), hasLength(1));

    // agent_id 匹配时正常删除
    await SyncResponseApplier(database).apply(
      scope: SyncScope.all(),
      tables: const {},
      tombstones: [
        {
          'TableName': 'long_term_memories',
          'ClientID': 'legacy-collided-id',
          'AgentID': 'agent-a',
        },
      ],
      acknowledgedTombstoneIds: const {},
    );
    expect(await database.query('long_term_memories'), isEmpty);
  });
}
