import 'dart:io';

import 'package:aichat/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directory = await Directory.systemTemp.createTemp('aichat-account-db-');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.onAccountSwitched = null;
    await DatabaseService.closeForTesting();
  });

  tearDown(() async {
    await DatabaseService.closeForTesting();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('账号切换隔离 SQLite 数据且切回后数据仍存在', () async {
    await DatabaseService.switchAccount(101);
    final firstDatabase = await DatabaseService.database;
    await firstDatabase.insert('agents', {
      'id': 'account-a-agent',
      'name': 'A',
      'persona': 'A persona',
      'created_at': 1,
      'updated_at': 1,
    });

    await DatabaseService.switchAccount(202);
    final secondDatabase = await DatabaseService.database;
    expect(
      await secondDatabase.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['account-a-agent'],
      ),
      isEmpty,
    );
    expect(DatabaseService.currentUserId, 202);

    await DatabaseService.switchAccount(101);
    final reopenedFirstDatabase = await DatabaseService.database;
    expect(
      await reopenedFirstDatabase.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['account-a-agent'],
      ),
      hasLength(1),
    );
  });
}
