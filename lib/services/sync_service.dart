import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../config/server_config.dart';
import '../models/sync_policy.dart';
import 'client_protocol.dart';
import 'database_service.dart';
import 'device_id_service.dart';
import 'sync_tables.dart';
import 'sync_payload_builder.dart';
import 'sync_response_applier.dart';
import 'sync_avatar_restore.dart';
import 'sync_scope.dart';
import 'sync_status_probe.dart';

class SyncResult {
  final bool success;
  final int itemsProcessed;
  final String? error;
  const SyncResult({
    required this.success,
    required this.itemsProcessed,
    this.error,
  });
}

class SyncPreview {
  const SyncPreview({
    required this.token,
    required this.expiresAt,
    required this.uploadCount,
    required this.downloadCount,
    required this.overwriteLocalCount,
    required this.overwriteCloudCount,
    required this.deleteCount,
    required this.conflictCount,
    required this.scope,
    required this.policy,
    required this.mode,
    required this.payload,
  });

  final String token;
  final DateTime expiresAt;
  final int uploadCount;
  final int downloadCount;
  final int overwriteLocalCount;
  final int overwriteCloudCount;
  final int deleteCount;
  final int conflictCount;
  final SyncScope scope;
  final SyncPolicy policy;
  final String mode;
  final ScopedSyncPayload payload;
}

class SyncException implements Exception {
  const SyncException(this.message, {this.isConflict = false});

  final String message;
  final bool isConflict;

  @override
  String toString() => message;
}

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  final SyncStatusProbe _statusProbe = SyncStatusProbe();
  final http.Client _client = http.Client();

  /// 13 张需同步表（常量在 sync_tables.dart，与 database_service 共用）
  static const syncTables = kSyncTables;

  /// UUID 主键表集合（这些表的 id 字段是 UUID，ClientID 直接用 id）
  static const _uuidTables = {
    'agents',
    'short_term_messages',
    'group_chats',
    'group_shared_memories',
    'long_term_memories',
    'base_memories',
    'user_profiles',
  };

  /// 拥有 agent_id 列的表（与 DatabaseService._hasAgentIdColumn 一致）
  static const _agentIdTables = {
    'chat_messages',
    'short_term_messages',
    'long_term_memories',
    'base_memories',
    'planned_messages',
    'group_members',
  };

  String _url(String path) => '${ServerConfig.baseUrl}$path';

  Map<String, String> _headers(String? token, {String? deviceId}) => {
    'Content-Type': 'application/json',
    ...ClientProtocol.currentHeaders,
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    if (deviceId != null && deviceId.isNotEmpty) 'X-Device-ID': deviceId,
  };

  Future<SyncPolicy> getPolicy(String? token) async {
    final deviceId = await DeviceIdService.id;
    final response = await _client
        .get(
          Uri.parse(_url('/api/v1/sync/policy')),
          headers: _headers(token, deviceId: deviceId),
        )
        .timeout(const Duration(seconds: 15));
    final data = _responseData(response);
    return SyncPolicy.fromJson(data);
  }

  Future<SyncPolicy> updatePolicy(String? token, SyncPolicy desired) async {
    final deviceId = await DeviceIdService.id;
    final response = await _client
        .put(
          Uri.parse(_url('/api/v1/sync/policy')),
          headers: _headers(token, deviceId: deviceId),
          body: jsonEncode(desired.toUpdateJson()),
        )
        .timeout(const Duration(seconds: 15));
    final data = _responseData(response);
    return SyncPolicy.fromJson(data);
  }

  Future<SyncPreview> preview({
    required String? token,
    required SyncPolicy policy,
    required SyncScope scope,
    required String mode,
  }) async {
    if (token == null || token.isEmpty) throw const SyncException('未登录');
    final deviceId = await DeviceIdService.id;
    final db = await DatabaseService.database;
    final payload = await SyncPayloadBuilder(
      database: db,
      deviceId: deviceId,
    ).build(scope);
    final request = _v2Request(
      policy: policy,
      scope: scope,
      mode: mode,
      payload: payload,
    );
    final response = await _client
        .post(
          Uri.parse(_url('/api/v1/sync/v2/preview')),
          headers: _headers(token, deviceId: deviceId),
          body: jsonEncode(request),
        )
        .timeout(const Duration(seconds: 30));
    final data = _responseData(response);
    return SyncPreview(
      token: data['preview_token']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(data['expires_at']?.toString() ?? '') ??
          DateTime.now().add(const Duration(minutes: 5)),
      uploadCount: (data['upload_count'] as num?)?.toInt() ?? 0,
      downloadCount: (data['download_count'] as num?)?.toInt() ?? 0,
      overwriteLocalCount:
          (data['overwrite_local_count'] as num?)?.toInt() ?? 0,
      overwriteCloudCount:
          (data['overwrite_cloud_count'] as num?)?.toInt() ?? 0,
      deleteCount: (data['delete_count'] as num?)?.toInt() ?? 0,
      conflictCount: (data['conflict_count'] as num?)?.toInt() ?? 0,
      scope: scope,
      policy: policy,
      mode: mode,
      payload: payload,
    );
  }

  Future<SyncResult> run(String? token, SyncPreview preview) async {
    if (token == null || token.isEmpty) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    try {
      await DatabaseService.createSyncSafetySnapshot();
      final deviceId = await DeviceIdService.id;
      final request = _v2Request(
        policy: preview.policy,
        scope: preview.scope,
        mode: preview.mode,
        payload: preview.payload,
      )..['preview_token'] = preview.token;
      final response = await _client
          .post(
            Uri.parse(_url('/api/v1/sync/v2/run')),
            headers: _headers(token, deviceId: deviceId),
            body: jsonEncode(request),
          )
          .timeout(const Duration(seconds: 60));
      final data = _responseData(response);
      final rawTables = (data['tables'] as Map?) ?? const {};
      final tables = <String, List<Map<String, dynamic>>>{};
      for (final entry in rawTables.entries) {
        tables[entry.key.toString()] = ((entry.value as List?) ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      final tombstones = ((data['tombstones'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final db = await DatabaseService.database;
      final processed = await SyncResponseApplier(db).apply(
        scope: preview.scope,
        tables: tables,
        tombstones: tombstones,
        acknowledgedTombstoneIds: preview.payload.tombstoneIds,
      );
      // 同步落库后还原智能体头像（avatar_data base64 → 本地文件）
      await restoreSyncedAgentAvatars(db);
      // 应用成功：删除安全快照（整库副本含全部聊天，常驻等于隐私泄漏面）
      await DatabaseService.deleteSyncSafetySnapshot();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_sync_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      return SyncResult(success: true, itemsProcessed: processed);
    } catch (error) {
      return SyncResult(
        success: false,
        itemsProcessed: 0,
        error: error.toString(),
      );
    }
  }

  Map<String, dynamic> _v2Request({
    required SyncPolicy policy,
    required SyncScope scope,
    required String mode,
    required ScopedSyncPayload payload,
  }) => {
    'mode': mode,
    'policy_version': policy.version,
    if (mode == 'one_shot') 'agent_ids': scope.agentIds.toList()..sort(),
    'tables': payload.toJson(),
  };

  Map<String, dynamic> _responseData(http.Response response) {
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw SyncException('服务器响应无效 (${response.statusCode})');
    }
    if (response.statusCode == 409) {
      throw SyncException(
        envelope['message']?.toString() ?? '同步策略已变化',
        isConflict: true,
      );
    }
    if (response.statusCode != 200 || envelope['code'] != 0) {
      throw SyncException(
        envelope['message']?.toString() ?? '同步请求失败 (${response.statusCode})',
      );
    }
    return Map<String, dynamic>.from((envelope['data'] as Map?) ?? const {});
  }

  /// 上传所有表数据
  Future<SyncResult> uploadAll(String? token) async {
    if (token == null || token.isEmpty) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    final deviceId = await DeviceIdService.id;
    final db = await DatabaseService.database;
    final payload = <String, dynamic>{};

    int totalItems = 0;
    for (final table in syncTables) {
      final rows = await db.query(table);
      final items = <Map<String, dynamic>>[];
      for (final row in rows) {
        // 确保 client_id 存在
        String clientId = row['client_id']?.toString() ?? '';
        if (clientId.isEmpty) {
          final idVal = row['id']?.toString() ?? '';
          clientId = _uuidTables.contains(table) ? idVal : '${deviceId}_$idVal';
          if (idVal.isNotEmpty) {
            await db.update(
              table,
              {'client_id': clientId},
              where: 'id = ?',
              whereArgs: [idVal],
            );
          }
        }
        final item = Map<String, dynamic>.from(row);
        item['client_id'] = clientId;
        items.add(item);
        totalItems++;
      }
      // 读取本地墓碑
      final tombstones = await db.query(
        'local_tombstones',
        where: 'table_name = ?',
        whereArgs: [table],
      );
      final tombList = tombstones
          .map(
            (t) => {'table_name': t['table_name'], 'client_id': t['client_id']},
          )
          .toList();
      payload[table] = {'items': items, 'tombstones': tombList};
    }

    try {
      // 大 payload 弱网可能长时间挂起，必须限时（其余同步方法均已有超时）
      final resp = await _client
          .post(
            Uri.parse(_url('/api/v1/sync/all')),
            headers: _headers(token, deviceId: deviceId),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        return SyncResult(
          success: false,
          itemsProcessed: 0,
          error: '上传失败: ${resp.statusCode}',
        );
      }
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) {
        return SyncResult(
          success: false,
          itemsProcessed: 0,
          error: body['msg'] ?? '上传失败',
        );
      }
      // 清空本地墓碑
      final db2 = await DatabaseService.database;
      await db2.delete('local_tombstones');
      // 更新本地 sync_updated_at
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final table in syncTables) {
        try {
          await db2.update(table, {'sync_updated_at': now});
        } catch (_) {}
      }
      return SyncResult(success: true, itemsProcessed: totalItems);
    } catch (e) {
      return SyncResult(success: false, itemsProcessed: 0, error: e.toString());
    }
  }

  /// 下载所有表数据
  Future<SyncResult> downloadAll(String? token) async {
    if (token == null || token.isEmpty) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    final db = await DatabaseService.database;
    final deviceId = await DeviceIdService.id;

    try {
      final resp = await _client
          .get(
            Uri.parse(_url('/api/v1/sync/all')),
            headers: _headers(token, deviceId: deviceId),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        return SyncResult(
          success: false,
          itemsProcessed: 0,
          error: '下载失败: ${resp.statusCode}',
        );
      }
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) {
        return SyncResult(
          success: false,
          itemsProcessed: 0,
          error: body['msg'] ?? '下载失败',
        );
      }
      final data = body['data'] as Map<String, dynamic>;
      int totalProcessed = 0;

      // 墓碑应用 + 各表 upsert 必须在同一事务内：中途失败不留半同步状态
      await db.transaction((txn) async {
        // 先应用墓碑
        final tombstones = (data['tombstones'] as List?) ?? [];
        for (final t in tombstones) {
          final tableName =
              t['TableName'] as String? ?? t['table_name'] as String?;
          final clientId =
              t['ClientID'] as String? ?? t['client_id'] as String?;
          if (tableName != null &&
              clientId != null &&
              syncTables.contains(tableName)) {
            // 墓碑携带 agent_id 且目标表有该列时附加过滤，兜底防御跨智能体误删
            final agentId =
                t['AgentID'] as String? ?? t['agent_id'] as String? ?? '';
            if (agentId.isNotEmpty && _agentIdTables.contains(tableName)) {
              await txn.delete(
                tableName,
                where: 'client_id = ? AND agent_id = ?',
                whereArgs: [clientId, agentId],
              );
            } else {
              await txn.delete(
                tableName,
                where: 'client_id = ?',
                whereArgs: [clientId],
              );
            }
            totalProcessed++;
          }
        }

        // 再 upsert 各表数据
        for (final table in syncTables) {
          final items = (data[table] as List?) ?? [];
          for (final item in items) {
            final m = Map<String, dynamic>.from(item as Map);
            // 移除服务端字段
            m.remove('ID');
            m.remove('id');
            m.remove('user_id');
            m.remove('UserID');
            m.remove('CreatedAt');
            m.remove('created_at');
            final clientId = m.remove('ClientID') ?? m.remove('client_id');
            if (clientId != null) {
              m['client_id'] = clientId;
            }
            // upsert
            final existing = await txn.query(
              table,
              where: 'client_id = ?',
              whereArgs: [clientId],
            );
            if (existing.isNotEmpty) {
              await txn.update(
                table,
                m,
                where: 'client_id = ?',
                whereArgs: [clientId],
              );
            } else {
              // UUID 表：用 ClientID 作为 id
              if (_uuidTables.contains(table)) {
                m['id'] = clientId;
              } else {
                m.remove('id');
              }
              try {
                await txn.insert(
                  table,
                  m,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              } catch (e) {
                debugPrint('[Sync] insert $table failed: $e');
              }
            }
            totalProcessed++;
          }
        }

        // 更新本地 sync_updated_at
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final table in syncTables) {
          try {
            await txn.update(table, {'sync_updated_at': now});
          } catch (_) {}
        }
      });
      return SyncResult(success: true, itemsProcessed: totalProcessed);
    } catch (e) {
      return SyncResult(success: false, itemsProcessed: 0, error: e.toString());
    }
  }

  /// 检查云端是否有更新
  /// 删除当前账号的云端同步副本，不修改本地数据库。
  Future<SyncResult> deleteCloudCopy(
    String? token, {
    required SyncScope scope,
  }) async {
    if (token == null || token.isEmpty) {
      return const SyncResult(success: false, itemsProcessed: 0, error: '未登录');
    }
    try {
      final deviceId = await DeviceIdService.id;
      final response = await _client
          .delete(
            Uri.parse(_url('/api/v1/sync/cloud')),
            headers: _headers(token, deviceId: deviceId),
            body: jsonEncode({
              'scope_mode': scope.mode.name,
              'selected_agent_ids': scope.agentIds.toList()..sort(),
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = _responseData(response);
      final deleted = (data['deleted'] as num?)?.toInt() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_sync_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      return SyncResult(success: true, itemsProcessed: deleted);
    } catch (error) {
      return SyncResult(
        success: false,
        itemsProcessed: 0,
        error: error.toString(),
      );
    }
  }

  Future<bool> checkCloudUpdate(String? token) async {
    if (token == null || token.isEmpty) return false;
    try {
      final deviceId = await DeviceIdService.id;
      final resp = await _statusProbe.fetch(
        Uri.parse(_url('/api/v1/sync/status')),
        headers: _headers(token, deviceId: deviceId),
      );
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body);
      if (body['code'] != 0) return false;
      // 对比云端最后更新时间与本地最后同步时间
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      final cloudUpdatedAt = (data['last_updated'] as num?)?.toInt();
      if (cloudUpdatedAt == null) return false;
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt('last_sync_time') ?? 0;
      return cloudUpdatedAt > lastSync;
    } catch (e) {
      debugPrint('[Sync] checkCloudUpdate failed: $e');
      return false;
    }
  }
}
