import 'package:aichat/services/database_service.dart';
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
      'id TEXT PRIMARY KEY, name TEXT NOT NULL, persona TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE group_chats ('
      'id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await database.insert('agents', {'id': 'a1', 'name': 'A', 'persona': 'P'});
    await database.insert('group_chats', {'id': 'g1', 'name': 'G'});
  });

  tearDown(() => database.close());

  test('network migration adds provenance and opening speaker columns without losing rows', () async {
    await DatabaseService.migrateNetworkSourceColumns(database);

    final agentColumns = await database.rawQuery('PRAGMA table_info(agents)');
    final groupColumns = await database.rawQuery(
      'PRAGMA table_info(group_chats)',
    );
    final agentNames = agentColumns.map((row) => row['name']).toSet();
    final groupNames = groupColumns.map((row) => row['name']).toSet();

    expect(
      agentNames,
      containsAll(<String>{
        'network_id',
        'network_uploader_id',
        'network_source',
        'network_version',
      }),
    );
    expect(
      groupNames,
      containsAll(<String>{
        'opening_line',
        'opening_speaker_agent_id',
        'network_id',
        'network_uploader_id',
        'network_source',
        'network_version',
      }),
    );

    final agent = (await database.query('agents')).single;
    final group = (await database.query('group_chats')).single;
    expect(agent['name'], 'A');
    expect(agent['network_source'], 'none');
    expect(group['name'], 'G');
    expect(group['network_source'], 'none');
  });
}
