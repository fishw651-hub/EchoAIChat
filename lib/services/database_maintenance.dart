// DatabaseService 的例行清理 / 备份与恢复（WAL checkpoint）实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── 例行清理 ───

/// 启动时例行清理：删除过期的调试日志、token 用量、墓碑、旧小说生成记录
/// 策略：保留最近 7 天的数据，更老的删除
Future<void> _routineCleanup() async {
  try {
    final db = DatabaseService._database;
    if (db == null) return;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;

    // 清理 debug_logs（只写不删的日志表，长期使用会无限增长）
    final deleted1 = await db.delete(
      'debug_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
    // 清理 token_usage（每次请求一行，无上限）
    final deleted2 = await db.delete(
      'token_usage',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
    // 清理 local_tombstones（删除墓碑只增不减，7 天足够多端同步）
    final deleted3 = await db.delete(
      'local_tombstones',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    // 清理 novel_generations（生成结果可能很长，保留 7 天）
    final deleted4 = await db.delete(
      'novel_generations',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
    // 清理已送达的 planned_messages（delivered=1 的已无用途）
    final deleted5 = await db.delete(
      'planned_messages',
      where: 'delivered = ? AND scheduled_time < ?',
      whereArgs: [1, cutoff],
    );

    if (deleted1 + deleted2 + deleted3 + deleted4 + deleted5 > 0) {
      debugPrint(
        '[DB] routine cleanup: deleted $deleted1 debug_logs, $deleted2 token_usage, $deleted3 tombstones, $deleted4 novel_generations, $deleted5 delivered_plans',
      );
      // 清理后执行 VACUUM 回收磁盘空间（Web 端 ffi_web 不支持，跳过）
      if (!kIsWeb) {
        await db.execute('VACUUM');
        debugPrint('[DB] VACUUM completed');
      }
    }
  } catch (e) {
    debugPrint('[DB] routine cleanup failed: $e');
  }
}

// ─── 数据库备份与恢复 ───

Future<String?> _createSyncSafetySnapshot() async {
  final db = await DatabaseService.database;
  try {
    // 必须用 rawQuery：checkpoint 会返回结果行，execSQL 在 Android 上抛错
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
  } catch (_) {
    // Web SQLite 不支持 WAL checkpoint。
  }
  if (kIsWeb) return null;
  final dbPath = await _databasePathForName(DatabaseService._databaseName);
  final snapshotPath = '$dbPath.pre_sync_backup';
  await File(dbPath).copy(snapshotPath);
  return snapshotPath;
}

/// 删除同步安全快照（同步应用成功后调用；文件不存在的异常吞掉即可）
Future<void> _deleteSyncSafetySnapshot() async {
  if (kIsWeb) return;
  try {
    final dbPath = await _databasePathForName(DatabaseService._databaseName);
    final snapshot = File('$dbPath.pre_sync_backup');
    if (await snapshot.exists()) {
      await snapshot.delete();
    }
  } catch (_) {}
}

Future<File> _backupDatabase(String destPath) async {
  if (kIsWeb) {
    throw UnsupportedError('Web 端不支持文件备份，请使用多端同步功能');
  }
  final db = await DatabaseService.database;
  // 备份前强制 WAL 刷盘，确保所有已提交事务写入主 db 文件。
  // 必须用 rawQuery：checkpoint 会返回结果行，Android execSQL 会直接抛错。
  try {
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
  } catch (_) {}
  final dbPath = await _databasePathForName(DatabaseService._databaseName);
  final source = File(dbPath);
  final dest = File(destPath);
  await source.copy(destPath);
  return dest;
}

Future<void> _restoreDatabase(String sourcePath) async {
  if (kIsWeb) {
    throw UnsupportedError('Web 端不支持文件恢复，请使用多端同步功能');
  }
  final db = await DatabaseService.database;
  await db.close();
  DatabaseService._database = null;
  final dbPath = await _databasePathForName(DatabaseService._databaseName);
  final dest = File(dbPath);
  if (await dest.exists()) {
    await dest.delete();
  }
  await File(sourcePath).copy(dbPath);
}
