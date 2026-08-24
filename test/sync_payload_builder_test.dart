import 'package:aichat/services/sync_payload_builder.dart';
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
      'CREATE TABLE agents (id TEXT PRIMARY KEY, client_id TEXT, name TEXT)',
    );
    for (final table in [
      'chat_messages',
      'short_term_messages',
      'long_term_memories',
      'base_memories',
      'planned_messages',
    ]) {
      await database.execute(
        'CREATE TABLE $table ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT, '
        'agent_id TEXT, group_id TEXT, content TEXT)',
      );
    }
    await database.execute(
      'CREATE TABLE local_tombstones ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT, '
      'client_id TEXT, agent_id TEXT, created_at INTEGER)',
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'selected scope queries only one agent private six-table closure',
    () async {
      await database.insert('agents', {
        'id': 'agent-a',
        'client_id': 'agent-a',
        'name': 'A',
      });
      await database.insert('agents', {
        'id': 'agent-b',
        'client_id': 'agent-b',
        'name': 'B',
      });
      for (final table in agentSyncClosureTables.where(
        (name) => name != 'agents',
      )) {
        await database.insert(table, {
          'client_id': '$table-a',
          'agent_id': 'agent-a',
          'group_id': null,
          'content': 'A',
        });
        await database.insert(table, {
          'client_id': '$table-b',
          'agent_id': 'agent-b',
          'group_id': null,
          'content': 'B',
        });
      }
      await database.insert('long_term_memories', {
        'client_id': 'group-memory-a',
        'agent_id': 'agent-a',
        'group_id': 'group-1',
        'content': 'group',
      });
      await database.insert('local_tombstones', {
        'table_name': 'chat_messages',
        'client_id': 'deleted-a',
        'agent_id': 'agent-a',
        'created_at': 1,
      });
      await database.insert('local_tombstones', {
        'table_name': 'chat_messages',
        'client_id': 'deleted-b',
        'agent_id': 'agent-b',
        'created_at': 1,
      });

      final payload = await SyncPayloadBuilder(
        database: database,
        deviceId: 'device-1',
      ).build(SyncScope.oneShot({'agent-a'}));

      expect(payload.tables.keys, agentSyncClosureTables);
      expect(payload.tables['agents']!.items.single['client_id'], 'agent-a');
      for (final table in agentSyncClosureTables.where(
        (name) => name != 'agents',
      )) {
        expect(payload.tables[table]!.items, hasLength(1), reason: table);
        expect(payload.tables[table]!.items.single['agent_id'], 'agent-a');
      }
      expect(payload.tables['chat_messages']!.tombstones, hasLength(1));
      expect(
        payload.tables['chat_messages']!.tombstones.single['client_id'],
        'deleted-a',
      );
      expect(
        payload.tables['chat_messages']!.tombstones.single['created_at'],
        1,
      );
    },
  );
}
