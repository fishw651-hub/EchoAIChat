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
      'CREATE TABLE chat_messages ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT)',
    );
    await database.execute(
      'CREATE TABLE planned_messages ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT)',
    );
  });

  tearDown(() => database.close());

  test('numeric client ids receive a stable device table namespace', () async {
    await database.insert('chat_messages', {'id': 12, 'client_id': '12'});
    await database.insert('chat_messages', {
      'id': 13,
      'client_id': 'already:scoped:13',
    });
    await database.insert('planned_messages', {'id': 7, 'client_id': '7'});

    await DatabaseService.migrateLegacySyncClientIds(
      database,
      deviceId: 'device-a',
      tables: const ['chat_messages', 'planned_messages'],
    );

    final chats = await database.query('chat_messages', orderBy: 'id');
    final plans = await database.query('planned_messages');
    expect(chats[0]['client_id'], 'device-a:chat_messages:12');
    expect(chats[1]['client_id'], 'already:scoped:13');
    expect(plans.single['client_id'], 'device-a:planned_messages:7');
  });
}
