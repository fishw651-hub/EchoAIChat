import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sync_policy.dart';
import 'sync_scope.dart';

/// 同步上传前把智能体头像文件编码为 base64（avatar_data 列随行携带）。
/// 头像被移除或文件丢失时返回空串，使对端同步删除头像。
/// Web 端无本地文件，直接返回空串。
Future<String> _encodeAvatarForSync(Map<String, dynamic> row) async {
  if (kIsWeb) return '';
  final path = row['avatar_path']?.toString() ?? '';
  if (path.isEmpty) return '';
  try {
    final file = File(path);
    if (!file.existsSync()) return '';
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return '';
    return base64Encode(bytes);
  } catch (_) {
    return '';
  }
}

class SyncTablePayload {
  const SyncTablePayload({required this.items, required this.tombstones});

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> tombstones;

  Map<String, dynamic> toJson() => {'items': items, 'tombstones': tombstones};
}

class ScopedSyncPayload {
  const ScopedSyncPayload({required this.tables, required this.tombstoneIds});

  final Map<String, SyncTablePayload> tables;
  final Set<int> tombstoneIds;

  Map<String, dynamic> toJson() => {
    for (final entry in tables.entries) entry.key: entry.value.toJson(),
  };
}

class SyncPayloadBuilder {
  SyncPayloadBuilder({required this.database, required this.deviceId});

  final DatabaseExecutor database;
  final String deviceId;

  static const _uuidTables = {
    'agents',
    'short_term_messages',
    'group_chats',
    'group_shared_memories',
    'long_term_memories',
    'base_memories',
    'user_profiles',
  };

  Future<ScopedSyncPayload> build(SyncScope scope) async {
    final tables = <String, SyncTablePayload>{};
    final includedTombstoneIds = <int>{};
    for (final table in scope.tables) {
      final rows = await _queryRows(table, scope);
      final items = <Map<String, dynamic>>[];
      for (final row in rows) {
        final item = Map<String, dynamic>.from(row);
        var clientId = item['client_id']?.toString() ?? '';
        final localId = item['id']?.toString() ?? '';
        if (clientId.isEmpty && localId.isNotEmpty) {
          clientId = _uuidTables.contains(table)
              ? localId
              : '$deviceId:$table:$localId';
          await database.update(
            table,
            {'client_id': clientId},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        item['client_id'] = clientId;
        if (table == 'agents') {
          item['avatar_data'] = await _encodeAvatarForSync(item);
        }
        items.add(item);
      }

      final rawTombstones = await database.query(
        'local_tombstones',
        where: 'table_name = ?',
        whereArgs: [table],
      );
      final tombstones = scope.filterTombstones(
        rawTombstones.map(Map<String, dynamic>.from),
      );
      for (final tombstone in tombstones) {
        final id = (tombstone['id'] as num?)?.toInt();
        if (id != null) includedTombstoneIds.add(id);
        tombstone.remove('id');
      }
      tables[table] = SyncTablePayload(items: items, tombstones: tombstones);
    }
    return ScopedSyncPayload(
      tables: tables,
      tombstoneIds: includedTombstoneIds,
    );
  }

  Future<List<Map<String, Object?>>> _queryRows(String table, SyncScope scope) {
    if (scope.mode == SyncScopeMode.all) {
      return database.query(table);
    }
    if (scope.agentIds.isEmpty) return Future.value(const []);

    final agentIds = scope.agentIds.toList()..sort();
    final placeholders = List.filled(agentIds.length, '?').join(',');
    if (table == 'agents') {
      return database.query(
        table,
        where: '(client_id IN ($placeholders) OR id IN ($placeholders))',
        whereArgs: [...agentIds, ...agentIds],
      );
    }

    var where = 'agent_id IN ($placeholders)';
    if (table == 'long_term_memories' ||
        table == 'base_memories' ||
        table == 'planned_messages') {
      where += " AND (group_id IS NULL OR group_id = '')";
    }
    return database.query(table, where: where, whereArgs: agentIds);
  }
}
