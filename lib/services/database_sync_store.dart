// DatabaseService 的墓碑 / client_id（local_tombstones 内联实现）实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── 墓碑（原 SyncService.recordTombstone 内联实现）───

/// 在批量删除前收集 client_id 并记录墓碑（用于多端同步删除传播）
/// [table] 表名，[where] 条件，[whereArgs] 条件参数
Future<void> _recordTombstonesBeforeDelete(
  String table,
  String where,
  List<Object?> whereArgs,
) async {
  try {
    if (!kSyncTables.contains(table)) return;
    final db = await DatabaseService.database;
    final columns = <String>['client_id', 'id'];
    if (_hasAgentIdColumn(table)) columns.add('agent_id');
    final rows = await db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
    );
    final entries = <({String table, String clientId, String agentId})>[];
    for (final row in rows) {
      final cid = row['client_id']?.toString() ?? '';
      if (cid.isNotEmpty) {
        entries.add((
          table: table,
          clientId: cid,
          agentId: _tombstoneAgentId(table, row),
        ));
      }
    }
    // 单次事务批量写入，替代逐条串行小事务
    await _insertTombstones(db, entries);
  } catch (e) {
    debugPrint('[Tombstone] record for $table failed: $e');
  }
}

/// 记录单条墓碑（用于 UUID 表单条删除，主键即 client_id）
Future<void> _recordTombstoneSingle(String table, String clientId) async {
  if (clientId.isEmpty) return;
  try {
    final db = await DatabaseService.database;
    final columns = <String>['client_id', 'id'];
    if (_hasAgentIdColumn(table)) columns.add('agent_id');
    final rows = await db.query(
      table,
      columns: columns,
      where: 'client_id = ? OR id = ?',
      whereArgs: [clientId, clientId],
      limit: 1,
    );
    final agentId = rows.isEmpty
        ? (table == 'agents' ? clientId : '')
        : _tombstoneAgentId(table, rows.first);
    await _insertTombstone(db, table, clientId, agentId: agentId);
  } catch (e) {
    debugPrint('[Tombstone] record for $table failed: $e');
  }
}

/// 写入单条墓碑到 local_tombstones（原 SyncService.recordTombstone，
/// 内联至此以破除 database_service ↔ sync_service 循环 import）
Future<void> _insertTombstone(
  Database db,
  String table,
  String clientId, {
  String agentId = '',
}) async {
  if (!kSyncTables.contains(table)) return;
  if (clientId.isEmpty) return;
  await db.insert('local_tombstones', {
    'table_name': table,
    'client_id': clientId,
    'agent_id': agentId,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
}

/// 批量写入墓碑：单次事务 batch 写入。批量删除（如清空会话）时替代
/// 逐条 _insertTombstone——数千条串行小事务会让删除长时间转圈。
/// （原 SyncService.recordTombstones，内联原因同上）
Future<void> _insertTombstones(
  Database db,
  List<({String table, String clientId, String agentId})> entries,
) async {
  final valid = entries
      .where((e) => kSyncTables.contains(e.table) && e.clientId.isNotEmpty)
      .toList();
  if (valid.isEmpty) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction((txn) async {
    final batch = txn.batch();
    for (final e in valid) {
      batch.insert('local_tombstones', {
        'table_name': e.table,
        'client_id': e.clientId,
        'agent_id': e.agentId,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  });
}

/// 事务内批量记录墓碑（与删除操作在同一事务中，避免孤儿墓碑）
Future<void> _recordTombstonesInTxn(
  DatabaseExecutor txn,
  String table,
  String where,
  List<Object?> whereArgs,
) async {
  try {
    if (!kSyncTables.contains(table)) return;
    final columns = <String>['client_id', 'id'];
    if (_hasAgentIdColumn(table)) columns.add('agent_id');
    final rows = await txn.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      final cid = row['client_id']?.toString() ?? '';
      if (cid.isNotEmpty) {
        await txn.insert('local_tombstones', {
          'table_name': table,
          'client_id': cid,
          'agent_id': _tombstoneAgentId(table, row),
          'created_at': now,
        });
      }
    }
  } catch (e) {
    debugPrint('[Tombstone] record for $table failed: $e');
  }
}

/// 事务内记录单条墓碑
Future<void> _recordTombstoneSingleInTxn(
  DatabaseExecutor txn,
  String table,
  String clientId,
) async {
  if (clientId.isEmpty) return;
  try {
    if (!kSyncTables.contains(table)) return;
    final columns = <String>['client_id', 'id'];
    if (_hasAgentIdColumn(table)) columns.add('agent_id');
    final rows = await txn.query(
      table,
      columns: columns,
      where: 'client_id = ? OR id = ?',
      whereArgs: [clientId, clientId],
      limit: 1,
    );
    await txn.insert('local_tombstones', {
      'table_name': table,
      'client_id': clientId,
      'agent_id': rows.isEmpty
          ? (table == 'agents' ? clientId : '')
          : _tombstoneAgentId(table, rows.first),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (e) {
    debugPrint('[Tombstone] record for $table failed: $e');
  }
}

String _tombstoneAgentId(String table, Map<String, Object?> row) {
  if (table == 'agents') {
    return (row['client_id'] ?? row['id'])?.toString() ?? '';
  }
  return row['agent_id']?.toString() ?? '';
}

bool _hasAgentIdColumn(String table) => const {
  'chat_messages',
  'short_term_messages',
  'long_term_memories',
  'base_memories',
  'planned_messages',
  'group_members',
}.contains(table);
