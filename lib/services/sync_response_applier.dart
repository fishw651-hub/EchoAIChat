import 'package:sqflite/sqflite.dart';

import 'sync_scope.dart';

class SyncResponseApplier {
  const SyncResponseApplier(this.database);

  final Database database;

  static const _uuidTables = {
    'agents',
    'short_term_messages',
    'group_chats',
    'group_shared_memories',
    'long_term_memories',
    'base_memories',
    'user_profiles',
  };

  /// 拥有 agent_id 列的表（与 DatabaseService._hasAgentIdColumn 一致）。
  /// 墓碑携带 agent_id 时删除附加该过滤，兜底防御跨智能体误删。
  static const _agentIdTables = {
    'chat_messages',
    'short_term_messages',
    'long_term_memories',
    'base_memories',
    'planned_messages',
    'group_members',
  };

  Future<int> apply({
    required SyncScope scope,
    required Map<String, List<Map<String, dynamic>>> tables,
    required List<Map<String, dynamic>> tombstones,
    required Set<int> acknowledgedTombstoneIds,
  }) {
    return database.transaction((transaction) async {
      var processed = 0;
      for (final tombstone in scope.filterTombstones(tombstones)) {
        final table = _readString(tombstone, 'table_name', 'TableName');
        final clientId = _readString(tombstone, 'client_id', 'ClientID');
        if (!scope.allowsTable(table) || clientId.isEmpty) continue;
        final agentId = _readString(tombstone, 'agent_id', 'AgentID');
        if (agentId.isNotEmpty && _agentIdTables.contains(table)) {
          processed += await transaction.delete(
            table,
            where: 'client_id = ? AND agent_id = ?',
            whereArgs: [clientId, agentId],
          );
        } else {
          processed += await transaction.delete(
            table,
            where: 'client_id = ?',
            whereArgs: [clientId],
          );
        }
      }

      for (final table in scope.tables) {
        final localColumns = await _readTableColumns(transaction, table);
        final rawItems = tables[table] ?? const [];
        for (final rawItem in scope.filterRows(table, rawItems)) {
          final item = _normalizeServerItem(rawItem, localColumns);
          final clientId = item['client_id']?.toString() ?? '';
          if (clientId.isEmpty) continue;
          final existing = await transaction.query(
            table,
            columns: ['client_id'],
            where: 'client_id = ?',
            whereArgs: [clientId],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            item.remove('id');
            await transaction.update(
              table,
              item,
              where: 'client_id = ?',
              whereArgs: [clientId],
            );
          } else {
            if (_uuidTables.contains(table)) {
              item['id'] = clientId;
            } else {
              item.remove('id');
            }
            await transaction.insert(
              table,
              item,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          processed++;
        }
      }

      if (acknowledgedTombstoneIds.isNotEmpty) {
        final ids = acknowledgedTombstoneIds.toList()..sort();
        final placeholders = List.filled(ids.length, '?').join(',');
        await transaction.delete(
          'local_tombstones',
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
      }
      return processed;
    });
  }

  Future<Set<String>> _readTableColumns(
    Transaction transaction,
    String table,
  ) async {
    final rows = await transaction.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name']?.toString() ?? '').toSet();
  }

  Map<String, dynamic> _normalizeServerItem(
    Map<String, dynamic> source,
    Set<String> localColumns,
  ) {
    final normalized = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key == 'ID' ||
          entry.key == 'UserID' ||
          entry.key == 'user_id') {
        continue;
      }
      if (entry.key == 'CreatedAt' && source.containsKey('created_at')) {
        continue;
      }
      if (entry.key == 'UpdatedAt' && source.containsKey('updated_at')) {
        continue;
      }
      final localKey = _snakeCase(entry.key);
      if (!localColumns.contains(localKey)) continue;
      normalized[localKey] = entry.value;
    }
    return normalized;
  }

  String _snakeCase(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .toLowerCase();
  }

  String _readString(Map<String, dynamic> item, String first, String second) {
    return (item[first] ?? item[second])?.toString() ?? '';
  }
}
