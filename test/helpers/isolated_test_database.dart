import 'dart:io';

import 'package:aichat/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 为单个测试文件分配独立的 SQLite 目录，防止并行 suite 争用 WAL 锁。
class IsolatedTestDatabase {
  IsolatedTestDatabase._(this._directory);

  final Directory _directory;

  static Future<IsolatedTestDatabase> open(String suiteName) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final safeName = suiteName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    final directory = await Directory.systemTemp.createTemp(
      'aichat-$safeName-',
    );
    await databaseFactory.setDatabasesPath(directory.path);
    await DatabaseService.database;
    return IsolatedTestDatabase._(directory);
  }

  Future<void> close() async {
    await DatabaseService.closeForTesting();
    if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  }
}
