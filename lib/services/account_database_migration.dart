part of 'database_service.dart';

abstract final class AccountDatabaseMigration {
  static const legacyDatabaseName = 'aichat.db';
  static const _claimOwnerKey = 'account_database_legacy_claim_owner_v1';
  static const _minimumSupportedVersion = 35;
  static const _maximumSupportedVersion = 37;

  static Future<void> claimLegacyIfNeeded({
    required int? userId,
    required String targetDatabaseName,
  }) async {
    if (userId == null) return;

    final legacyPath = await _databasePathForName(legacyDatabaseName);
    if (!await databaseExists(legacyPath)) return;

    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getString(_claimOwnerKey);
    if (owner != null && owner != targetDatabaseName) return;
    if (owner == null) {
      final reserved = await preferences.setString(
        _claimOwnerKey,
        targetDatabaseName,
      );
      if (!reserved) {
        throw StateError('无法持久化旧数据库认领标记');
      }
    }

    if (kIsWeb) {
      await _copyWebDatabase(legacyPath, targetDatabaseName);
      return;
    }

    final legacy = await openDatabase(legacyPath);
    try {
      final version = await legacy.getVersion();
      if (version < _minimumSupportedVersion ||
          version > _maximumSupportedVersion) {
        throw StateError('不支持的旧数据库版本: $version');
      }
      await legacy.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } on StateError {
      rethrow;
    } catch (_) {
      // 非 WAL 数据库或不支持 checkpoint 时，关闭连接仍会完成常规刷盘。
    } finally {
      await legacy.close();
    }

    final sourceFingerprint = sha256
        .convert(await File(legacyPath).readAsBytes())
        .toString();
    final stagingPath = '$legacyPath.migration-$targetDatabaseName';
    await _deleteDatabaseFiles(stagingPath);
    await File(legacyPath).copy(stagingPath);
    Database? staging;
    Database? target;
    try {
      staging = await openDatabase(
        stagingPath,
        version: _currentDatabaseVersion,
        onUpgrade: _onUpgrade,
      );
      await _ensureGroupTablesExist(staging);
      await _validateStagingDatabase(staging);
      target = await _initDatabase(databaseName: targetDatabaseName);
      final existingMigration = await target.query(
        'local_database_migrations',
        where: 'source_fingerprint = ? AND owner_database_name = ?',
        whereArgs: [sourceFingerprint, targetDatabaseName],
        limit: 1,
      );
      if (existingMigration.isEmpty) {
        await _mergeBusinessData(
          staging,
          target,
          sourceFingerprint: sourceFingerprint,
          ownerDatabaseName: targetDatabaseName,
        );
      }
      await staging.close();
      staging = null;
      await _deleteDatabaseFiles(legacyPath, mainFileLast: true);
      await target.update(
        'local_database_migrations',
        {
          'state': 'cleaned',
          'cleaned_at': DateTime.now().millisecondsSinceEpoch,
          'error': null,
        },
        where: 'source_fingerprint = ? AND owner_database_name = ?',
        whereArgs: [sourceFingerprint, targetDatabaseName],
      );
    } finally {
      await staging?.close();
      await target?.close();
      await _deleteDatabaseFiles(stagingPath);
    }
  }

  static Future<void> _deleteDatabaseFiles(
    String databasePath, {
    bool mainFileLast = false,
  }) async {
    final suffixes = mainFileLast
        ? const ['-wal', '-shm', '']
        : const ['', '-wal', '-shm'];
    for (final suffix in suffixes) {
      final file = File('$databasePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _copyWebDatabase(
    String legacyPath,
    String targetDatabaseName,
  ) async {
    final source = await openDatabase(legacyPath, readOnly: true);
    final version = await source.getVersion();
    if (version < _minimumSupportedVersion ||
        version > _maximumSupportedVersion) {
      await source.close();
      throw StateError('不支持的旧数据库版本: $version');
    }
    await _validateStagingDatabase(source);
    final sourceSnapshot = await _readMigrationSnapshot(source);
    final sourceFingerprint = _snapshotFingerprint(version, sourceSnapshot);
    final stagingName = '$legacyDatabaseName.migration-$targetDatabaseName';
    if (await databaseExists(stagingName)) await deleteDatabase(stagingName);

    final staging = await _initDatabase(databaseName: stagingName);
    Database? target;
    try {
      for (final table in _migrationTables) {
        final columns = await _tableColumns(staging, table);
        await staging.transaction((transaction) async {
          for (final sourceRow in sourceSnapshot[table]!) {
            final row = _filterMigrationRow(sourceRow, columns);
            await transaction.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      }
      if (version < 36) await _migrateMemoryIdsToUuid(staging);
      await _validateStagingDatabase(staging);

      target = await _initDatabase(databaseName: targetDatabaseName);
      final existingMigration = await target.query(
        'local_database_migrations',
        where: 'source_fingerprint = ? AND owner_database_name = ?',
        whereArgs: [sourceFingerprint, targetDatabaseName],
        limit: 1,
      );
      if (existingMigration.isEmpty) {
        await _mergeBusinessData(
          staging,
          target,
          sourceFingerprint: sourceFingerprint,
          ownerDatabaseName: targetDatabaseName,
        );
      }
      await source.close();
      await staging.close();
      await deleteDatabase(legacyPath);
      await target.update(
        'local_database_migrations',
        {
          'state': 'cleaned',
          'cleaned_at': DateTime.now().millisecondsSinceEpoch,
          'error': null,
        },
        where: 'source_fingerprint = ? AND owner_database_name = ?',
        whereArgs: [sourceFingerprint, targetDatabaseName],
      );
    } finally {
      if (source.isOpen) await source.close();
      if (staging.isOpen) await staging.close();
      await target?.close();
      if (await databaseExists(stagingName)) await deleteDatabase(stagingName);
    }
  }
}

String _snapshotFingerprint(
  int version,
  Map<String, List<Map<String, Object?>>> snapshot,
) {
  final parts = <String>['version:$version'];
  final tables = snapshot.keys.toList()..sort();
  for (final table in tables) {
    final rows = snapshot[table]!.map((row) {
      final keys = row.keys.toList()..sort();
      return jsonEncode({for (final key in keys) key: row[key]});
    }).toList()..sort();
    parts
      ..add('table:$table')
      ..addAll(rows);
  }
  return sha256.convert(utf8.encode(parts.join('\n'))).toString();
}

const _stableMigrationTables = <String, List<String>>{
  'agents': ['id'],
  'group_chats': ['id'],
  'long_term_memories': ['id'],
  'base_memories': ['id'],
  'group_shared_memories': ['id'],
  'short_term_messages': ['id'],
  'stickers': ['id'],
  'agent_folders': ['id'],
  'draft_uploads': ['id'],
};

const _integerMigrationTables = <String>[
  'group_short_term',
  'chat_messages',
  'group_messages',
  'group_members',
  'planned_messages',
  'providers',
  'token_usage',
  'token_cost',
  'novel_generations',
];

const _migrationTables = <String>[
  'agents',
  'group_chats',
  'long_term_memories',
  'base_memories',
  'group_shared_memories',
  'short_term_messages',
  'stickers',
  'agent_folders',
  'draft_uploads',
  ..._integerMigrationTables,
  'user_profiles',
  'local_sticker_messages',
  'agent_folder_members',
];

Future<void> _mergeBusinessData(
  Database source,
  Database target, {
  required String sourceFingerprint,
  required String ownerDatabaseName,
}) async {
  final snapshot = await _readMigrationSnapshot(source);
  final targetColumns = <String, Set<String>>{};
  for (final table in _migrationTables) {
    targetColumns[table] = await _tableColumns(target, table);
  }

  await target.transaction((transaction) async {
    for (final table in const ['agents', 'group_chats']) {
      await _mergeStableTable(
        transaction,
        table,
        _stableMigrationTables[table]!,
        snapshot[table]!,
        targetColumns[table]!,
      );
    }
    for (final table in const [
      'long_term_memories',
      'base_memories',
      'group_shared_memories',
      'short_term_messages',
    ]) {
      await _mergeStableTable(
        transaction,
        table,
        _stableMigrationTables[table]!,
        snapshot[table]!,
        targetColumns[table]!,
      );
    }

    await _mergeIntegerTable(
      transaction,
      'group_short_term',
      snapshot['group_short_term']!,
      targetColumns['group_short_term']!,
      sourceFingerprint: sourceFingerprint,
    );
    final chatMessageIds = await _mergeIntegerTable(
      transaction,
      'chat_messages',
      snapshot['chat_messages']!,
      targetColumns['chat_messages']!,
      sourceFingerprint: sourceFingerprint,
    );
    await _mergeIntegerTable(
      transaction,
      'group_messages',
      snapshot['group_messages']!,
      targetColumns['group_messages']!,
      sourceFingerprint: sourceFingerprint,
    );
    await _mergeIntegerTable(
      transaction,
      'group_members',
      snapshot['group_members']!,
      targetColumns['group_members']!,
      sourceFingerprint: sourceFingerprint,
    );
    await _mergeIntegerTable(
      transaction,
      'planned_messages',
      snapshot['planned_messages']!,
      targetColumns['planned_messages']!,
      sourceFingerprint: sourceFingerprint,
    );

    await _mergeProfiles(
      transaction,
      snapshot['user_profiles']!,
      targetColumns['user_profiles']!,
    );
    await _mergeStableTable(
      transaction,
      'stickers',
      _stableMigrationTables['stickers']!,
      snapshot['stickers']!,
      targetColumns['stickers']!,
    );
    await _mergeStickerSnapshots(
      transaction,
      snapshot['local_sticker_messages']!,
      targetColumns['local_sticker_messages']!,
      chatMessageIds,
    );
    await _mergeStableTable(
      transaction,
      'agent_folders',
      _stableMigrationTables['agent_folders']!,
      snapshot['agent_folders']!,
      targetColumns['agent_folders']!,
    );
    await _mergeCompositeTable(
      transaction,
      'agent_folder_members',
      const ['folder_id', 'agent_id'],
      snapshot['agent_folder_members']!,
      targetColumns['agent_folder_members']!,
    );
    await _mergeStableTable(
      transaction,
      'draft_uploads',
      _stableMigrationTables['draft_uploads']!,
      snapshot['draft_uploads']!,
      targetColumns['draft_uploads']!,
    );
    for (final table in const [
      'providers',
      'token_usage',
      'token_cost',
      'novel_generations',
    ]) {
      await _mergeIntegerTable(
        transaction,
        table,
        snapshot[table]!,
        targetColumns[table]!,
        sourceFingerprint: sourceFingerprint,
      );
    }
    await _validateMergedData(transaction, snapshot, chatMessageIds);
    await transaction.insert('local_database_migrations', {
      'source_fingerprint': sourceFingerprint,
      'owner_database_name': ownerDatabaseName,
      'state': 'committed',
      'committed_at': DateTime.now().millisecondsSinceEpoch,
    });
  });
}

Future<void> _validateStagingDatabase(Database database) async {
  final integrity = await database.rawQuery('PRAGMA integrity_check');
  if (!_integrityCheckPassed(integrity)) {
    throw StateError('旧数据库暂存副本完整性检查失败');
  }
  const requiredTables = {
    'agents',
    'chat_messages',
    'short_term_messages',
    'long_term_memories',
    'base_memories',
    'group_chats',
    'group_messages',
    'user_profiles',
  };
  final actualTables = (await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  )).map((row) => row['name']?.toString()).whereType<String>().toSet();
  final missing = requiredTables.difference(actualTables);
  if (missing.isNotEmpty) {
    throw StateError('旧数据库缺少核心表: ${missing.join(', ')}');
  }
}

Future<void> _validateMergedData(
  DatabaseExecutor target,
  Map<String, List<Map<String, Object?>>> snapshot,
  Map<int, int> chatMessageIds,
) async {
  final integrity = await target.rawQuery('PRAGMA integrity_check');
  if (!_integrityCheckPassed(integrity)) {
    throw StateError('目标数据库完整性检查失败');
  }

  final targetAgentIds = (await target.query(
    'agents',
    columns: ['id'],
  )).map((row) => row['id']?.toString()).whereType<String>().toSet();
  final targetGroupIds = (await target.query(
    'group_chats',
    columns: ['id'],
  )).map((row) => row['id']?.toString()).whereType<String>().toSet();
  for (final row in snapshot['agents']!) {
    final id = row['id']?.toString();
    if (id == null || !targetAgentIds.contains(id)) {
      throw StateError('智能体迁移校验失败: $id');
    }
  }

  for (final table in const [
    'chat_messages',
    'short_term_messages',
    'long_term_memories',
    'base_memories',
  ]) {
    for (final row in snapshot[table]!) {
      final agentId = row['agent_id']?.toString();
      if (agentId != null &&
          agentId.isNotEmpty &&
          !targetAgentIds.contains(agentId)) {
        throw StateError('$table 存在悬空智能体引用: $agentId');
      }
      final groupId = row['group_id']?.toString();
      if (groupId != null &&
          groupId.isNotEmpty &&
          !targetGroupIds.contains(groupId)) {
        throw StateError('$table 存在悬空群聊引用: $groupId');
      }
    }
  }
  for (final row in snapshot['group_members']!) {
    final agentId = row['agent_id']?.toString();
    final groupId = row['group_id']?.toString();
    if (agentId == null || !targetAgentIds.contains(agentId)) {
      throw StateError('group_members 存在悬空智能体引用: $agentId');
    }
    if (groupId == null || !targetGroupIds.contains(groupId)) {
      throw StateError('group_members 存在悬空群聊引用: $groupId');
    }
  }
  for (final table in const [
    'group_messages',
    'group_short_term',
    'group_shared_memories',
  ]) {
    for (final row in snapshot[table]!) {
      final groupId = row['group_id']?.toString();
      if (groupId == null || !targetGroupIds.contains(groupId)) {
        throw StateError('$table 存在悬空群聊引用: $groupId');
      }
    }
  }
  for (final row in snapshot['agent_folder_members']!) {
    final agentId = row['agent_id']?.toString();
    if (agentId == null || !targetAgentIds.contains(agentId)) {
      throw StateError('agent_folder_members 存在悬空智能体引用: $agentId');
    }
  }

  if (chatMessageIds.length != snapshot['chat_messages']!.length) {
    throw StateError('私聊消息迁移解析数量不一致');
  }
  for (final row in snapshot['local_sticker_messages']!) {
    final oldChatId = (row['chat_message_id'] as num?)?.toInt();
    final newChatId = oldChatId == null ? null : chatMessageIds[oldChatId];
    final targetRows = newChatId == null
        ? const <Map<String, Object?>>[]
        : await target.query(
            'chat_messages',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [newChatId],
            limit: 1,
          );
    if (targetRows.isEmpty) {
      throw StateError('表情消息快照存在悬空聊天引用: $oldChatId');
    }
  }

  for (final sourceProfile in snapshot['user_profiles']!) {
    final category = sourceProfile['category']?.toString();
    final key = sourceProfile['key']?.toString();
    final targetProfiles = await target.query(
      'user_profiles',
      where: 'category = ? AND key = ?',
      whereArgs: [category, key],
      limit: 1,
    );
    if (targetProfiles.isEmpty ||
        _migrationTimestamp(targetProfiles.single) <
            _migrationTimestamp(sourceProfile)) {
      throw StateError('人格画像迁移校验失败: $category/$key');
    }
  }
}

bool _integrityCheckPassed(List<Map<String, Object?>> rows) =>
    rows.length == 1 &&
    rows.single.values.single.toString().toLowerCase() == 'ok';

Future<Map<String, List<Map<String, Object?>>>> _readMigrationSnapshot(
  Database source,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  final availableTables = (await source.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  )).map((row) => row['name']?.toString()).whereType<String>().toSet();
  for (final table in _migrationTables) {
    result[table] = availableTables.contains(table)
        ? await source.query(table)
        : const [];
  }
  return result;
}

Future<Set<String>> _tableColumns(
  DatabaseExecutor database,
  String table,
) async {
  final info = await database.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name']?.toString()).whereType<String>().toSet();
}

Future<void> _mergeStableTable(
  DatabaseExecutor target,
  String table,
  List<String> keys,
  List<Map<String, Object?>> sourceRows,
  Set<String> targetColumns,
) async {
  for (final sourceRow in sourceRows) {
    final row = _filterMigrationRow(sourceRow, targetColumns);
    if (keys.any((key) => row[key] == null)) {
      throw StateError('$table 存在缺少主键的旧数据');
    }
    final existingRows = await target.query(
      table,
      where: _keyWhere(keys),
      whereArgs: keys.map((key) => row[key]).toList(),
      limit: 1,
    );
    if (existingRows.isEmpty) {
      await target.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      continue;
    }
    if (_migrationTimestamp(row) <= _migrationTimestamp(existingRows.single)) {
      continue;
    }
    final updates = Map<String, Object?>.from(row)
      ..removeWhere((key, _) => keys.contains(key));
    if (updates.isNotEmpty) {
      await target.update(
        table,
        updates,
        where: _keyWhere(keys),
        whereArgs: keys.map((key) => row[key]).toList(),
      );
    }
  }
}

Future<void> _mergeCompositeTable(
  DatabaseExecutor target,
  String table,
  List<String> keys,
  List<Map<String, Object?>> sourceRows,
  Set<String> targetColumns,
) async {
  for (final sourceRow in sourceRows) {
    final row = _filterMigrationRow(sourceRow, targetColumns);
    if (keys.any((key) => row[key] == null)) {
      throw StateError('$table 存在缺少复合主键的旧数据');
    }
    await target.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<Map<int, int>> _mergeIntegerTable(
  DatabaseExecutor target,
  String table,
  List<Map<String, Object?>> sourceRows,
  Set<String> targetColumns, {
  required String sourceFingerprint,
}) async {
  final idMap = <int, int>{};
  for (final sourceRow in sourceRows) {
    final sourceId = (sourceRow['id'] as num?)?.toInt();
    if (sourceId == null) throw StateError('$table 存在无效的整数主键');
    final row = _filterMigrationRow(sourceRow, targetColumns)..remove('id');

    final supportsClientId = targetColumns.contains('client_id');
    if (supportsClientId) {
      final clientId = row['client_id']?.toString() ?? '';
      row['client_id'] = clientId.isEmpty
          ? 'legacy-migration:$sourceFingerprint:$table:$sourceId'
          : clientId;
      final existingRows = await target.query(
        table,
        columns: [
          'id',
          'updated_at',
          'sync_updated_at',
        ].where(targetColumns.contains).toList(),
        where: 'client_id = ?',
        whereArgs: [row['client_id']],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = existingRows.single;
        final targetId = (existing['id'] as num).toInt();
        idMap[sourceId] = targetId;
        if (_migrationTimestamp(row) > _migrationTimestamp(existing)) {
          await target.update(
            table,
            row,
            where: 'id = ?',
            whereArgs: [targetId],
          );
        }
        continue;
      }
    }

    idMap[sourceId] = await target.insert(table, row);
  }
  return idMap;
}

Future<void> _mergeProfiles(
  DatabaseExecutor target,
  List<Map<String, Object?>> sourceRows,
  Set<String> targetColumns,
) async {
  for (final sourceRow in sourceRows) {
    final row = _filterMigrationRow(sourceRow, targetColumns);
    final category = row['category']?.toString();
    final key = row['key']?.toString();
    if (category == null || key == null) {
      throw StateError('user_profiles 存在缺少 category 或 key 的旧数据');
    }
    final existingRows = await target.query(
      'user_profiles',
      where: 'category = ? AND key = ?',
      whereArgs: [category, key],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      await target.insert('user_profiles', row);
      continue;
    }
    final existing = existingRows.single;
    if (_migrationTimestamp(row) <= _migrationTimestamp(existing)) continue;
    final existingId = existing['id'];
    final updates = Map<String, Object?>.from(row)..remove('id');
    await target.update(
      'user_profiles',
      updates,
      where: 'id = ?',
      whereArgs: [existingId],
    );
  }
}

Future<void> _mergeStickerSnapshots(
  DatabaseExecutor target,
  List<Map<String, Object?>> sourceRows,
  Set<String> targetColumns,
  Map<int, int> chatMessageIds,
) async {
  for (final sourceRow in sourceRows) {
    final oldChatId = (sourceRow['chat_message_id'] as num?)?.toInt();
    final newChatId = oldChatId == null ? null : chatMessageIds[oldChatId];
    if (newChatId == null) {
      throw StateError('表情消息快照无法解析聊天引用: $oldChatId');
    }
    final row = _filterMigrationRow(sourceRow, targetColumns)
      ..['chat_message_id'] = newChatId;
    await target.insert(
      'local_sticker_messages',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Map<String, Object?> _filterMigrationRow(
  Map<String, Object?> row,
  Set<String> targetColumns,
) => Map<String, Object?>.fromEntries(
  row.entries.where((entry) => targetColumns.contains(entry.key)),
);

String _keyWhere(List<String> keys) =>
    keys.map((key) => '$key = ?').join(' AND ');

int _migrationTimestamp(Map<String, Object?> row) {
  var result = 0;
  for (final key in const ['updated_at', 'sync_updated_at']) {
    final value = (row[key] as num?)?.toInt() ?? 0;
    if (value > result) result = value;
  }
  return result;
}
