// DatabaseService 的long_term / base / short_term / group_short_term / group_shared 记忆实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── 长期记忆 ───

Future<List<LongTermMemory>> _getLongTermMemories({
  String? agentId,
  String? groupId,
  bool privateOnly = true,
}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    if (groupId != null) {
      final maps = await db.query(
        'long_term_memories',
        where: 'agent_id = ? AND group_id = ?',
        whereArgs: [agentId, groupId],
        orderBy: 'id ASC',
      );
      return maps.map(LongTermMemory.fromMap).toList();
    }
    if (privateOnly) {
      final maps = await db.query(
        'long_term_memories',
        where: 'agent_id = ? AND group_id IS NULL',
        whereArgs: [agentId],
        orderBy: 'id ASC',
      );
      return maps.map(LongTermMemory.fromMap).toList();
    }
    final maps = await db.query(
      'long_term_memories',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'id ASC',
    );
    return maps.map(LongTermMemory.fromMap).toList();
  }
  debugPrint(
    '[DB] WARNING: getLongTermMemories called without agentId — returning empty',
  );
  return [];
}

Future<void> _insertLongTermMemory(LongTermMemory memory) async {
  final db = await DatabaseService.database;
  // 纯创建路径：id 即 client_id（同为 UUID）；abort 让主键碰撞暴露而非静默覆盖
  final map = memory.toMap()..['client_id'] = memory.id;
  await db.insert(
    'long_term_memories',
    map,
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}

Future<void> _updateLongTermMemory(
  LongTermMemory memory, {
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await db.update(
      'long_term_memories',
      {
        'field': memory.field,
        'content': memory.content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND agent_id = ?',
      whereArgs: [memory.id, agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: updateLongTermMemory called without agentId — skipping',
    );
  }
}

Future<void> _deleteLongTermMemory(String id, {String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstoneSingle('long_term_memories', id);
    await db.delete(
      'long_term_memories',
      where: 'id = ? AND agent_id = ?',
      whereArgs: [id, agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: deleteLongTermMemory called without agentId — skipping',
    );
  }
}

Future<void> _clearLongTermMemories({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstonesBeforeDelete('long_term_memories', 'agent_id = ?', [
      agentId,
    ]);
    await db.delete(
      'long_term_memories',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: clearLongTermMemories called without agentId — skipping',
    );
  }
}

// ─── 基础记忆 ───

Future<List<BaseMemory>> _getBaseMemories({
  String? agentId,
  String? groupId,
  bool privateOnly = true,
}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    if (groupId != null) {
      final maps = await db.query(
        'base_memories',
        where: 'agent_id = ? AND group_id = ?',
        whereArgs: [agentId, groupId],
        orderBy: 'id ASC',
      );
      return maps.map(BaseMemory.fromMap).toList();
    }
    if (privateOnly) {
      final maps = await db.query(
        'base_memories',
        where: 'agent_id = ? AND group_id IS NULL',
        whereArgs: [agentId],
        orderBy: 'id ASC',
      );
      return maps.map(BaseMemory.fromMap).toList();
    }
    final maps = await db.query(
      'base_memories',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'id ASC',
    );
    return maps.map(BaseMemory.fromMap).toList();
  }
  debugPrint(
    '[DB] WARNING: getBaseMemories called without agentId — returning empty',
  );
  return [];
}

Future<void> _insertBaseMemory(BaseMemory memory) async {
  final db = await DatabaseService.database;
  // 纯创建路径：id 即 client_id（同为 UUID）；abort 让主键碰撞暴露而非静默覆盖
  final map = memory.toMap()..['client_id'] = memory.id;
  await db.insert(
    'base_memories',
    map,
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}

Future<void> _updateBaseMemory(BaseMemory memory, {String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await db.update(
      'base_memories',
      {
        'type': memory.type,
        'content': memory.content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND agent_id = ?',
      whereArgs: [memory.id, agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: updateBaseMemory called without agentId — skipping',
    );
  }
}

Future<void> _deleteBaseMemory(String id, {String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstoneSingle('base_memories', id);
    await db.delete(
      'base_memories',
      where: 'id = ? AND agent_id = ?',
      whereArgs: [id, agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: deleteBaseMemory called without agentId — skipping',
    );
  }
}

Future<void> _clearBaseMemories({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstonesBeforeDelete('base_memories', 'agent_id = ?', [
      agentId,
    ]);
    await db.delete(
      'base_memories',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: clearBaseMemories called without agentId — skipping',
    );
  }
}

// ─── 短期记忆 ───

Future<List<ShortTermMessage>> _getShortTermMessages({
  int? limit,
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    final maps = await db.query(
      'short_term_messages',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return maps.map(ShortTermMessage.fromMap).toList();
  }
  debugPrint(
    '[DB] WARNING: getShortTermMessages called without agentId — returning empty',
  );
  return [];
}

Future<int> _getShortTermCount({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM short_term_messages WHERE agent_id = ?',
      [agentId],
    );
    return result.first['cnt'] as int;
  }
  final result = await db.rawQuery(
    'SELECT COUNT(*) as cnt FROM short_term_messages',
  );
  return result.first['cnt'] as int;
}

Future<int> _getMaxShortTermSeq({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    final result = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM short_term_messages WHERE agent_id = ?",
      [agentId],
    );
    return result.first['max_id'] as int? ?? 0;
  }
  final result = await db.rawQuery(
    "SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM short_term_messages",
  );
  return result.first['max_id'] as int? ?? 0;
}

Future<void> _insertShortTermMessage(ShortTermMessage msg) async {
  final db = await DatabaseService.database;
  await db.insert(
    'short_term_messages',
    msg.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _deleteShortTermMessage(String id, {String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstoneSingle('short_term_messages', id);
    await db.delete(
      'short_term_messages',
      where: 'id = ? AND agent_id = ?',
      whereArgs: [id, agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: deleteShortTermMessage called without agentId — skipping',
    );
  }
}

Future<void> _clearShortTermMessages({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstonesBeforeDelete('short_term_messages', 'agent_id = ?', [
      agentId,
    ]);
    await db.delete(
      'short_term_messages',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: clearShortTermMessages called without agentId — skipping',
    );
  }
}

/// 获取未处理（memory_ai_processed = 0）的短期记忆消息，用于 Memory AI 去重分析
Future<List<Map<String, dynamic>>> _getUnprocessedShortTermMessages(
  String agentId,
) async {
  final db = await DatabaseService.database;
  final rows = await db.query(
    'short_term_messages',
    where:
        'agent_id = ? AND (memory_ai_processed = 0 OR memory_ai_processed IS NULL)',
    whereArgs: [agentId],
    orderBy: 'timestamp ASC',
  );
  return rows
      .map(
        (r) => {
          'id': r['id'] as String,
          'role': r['role'] as String,
          'content': r['content'] as String,
          'image_path': r['image_path'] as String?,
          // 解码为 List<String>，供记忆 AI 挂图（attachImagesToMessages 消费）
          'image_paths': ImagePathsCodec.resolve(
            imagePathsRaw: r['image_paths'] as String?,
            imagePath: r['image_path'] as String?,
          ),
        },
      )
      .toList();
}

/// 更新短期记忆消息内容（按 agent_id 过滤，禁止跨智能体写入）
Future<void> _updateShortTermMessageContent(
  String id,
  String content, {
  String? agentId,
}) async {
  if (agentId == null) {
    debugPrint(
      '[DB] WARNING: updateShortTermMessageContent called without agentId — skipping',
    );
    return;
  }
  final db = await DatabaseService.database;
  await db.update(
    'short_term_messages',
    {'content': content},
    where: 'id = ? AND agent_id = ?',
    whereArgs: [id, agentId],
  );
}

/// 标记短期记忆消息为已由 Memory AI 处理
Future<void> _markShortTermMessagesProcessed(List<String> ids) async {
  if (ids.isEmpty) return;
  final db = await DatabaseService.database;
  final placeholders = List.filled(ids.length, '?').join(',');
  await db.update(
    'short_term_messages',
    {'memory_ai_processed': 1},
    where: 'id IN ($placeholders)',
    whereArgs: ids,
  );
}

// ─── 人设迁移 ───

Future<void> _migrateDefaultPersona(String newPersona) async {
  final db = await DatabaseService.database;
  final oldKeywords = ['你是用户的AI智能助手', '你是用户的私人AI管家'];
  final existing = await db.query(
    'base_memories',
    where: 'type = ?',
    whereArgs: ['setting'],
  );
  for (final row in existing) {
    final content = row['content'] as String;
    for (final kw in oldKeywords) {
      if (content.contains(kw)) {
        await db.update(
          'base_memories',
          {
            'content': newPersona,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        break;
      }
    }
  }
}

// ─── 群短记忆 ───

Future<void> _insertGroupShortTerm({
  required String groupId,
  required String role,
  String? senderName,
  required String content,
  required int timestamp,
}) async {
  final db = await DatabaseService.database;
  await db.insert('group_short_term', {
    'group_id': groupId,
    'role': role,
    'sender_name': senderName,
    'content': content,
    'timestamp': timestamp,
  });
}

Future<List<Map<String, dynamic>>> _getGroupShortTerm(String groupId) async {
  final db = await DatabaseService.database;
  return await db.query(
    'group_short_term',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'timestamp ASC',
  );
}

Future<int> _getGroupShortTermCount(String groupId) async {
  final db = await DatabaseService.database;
  final result = await db.rawQuery(
    'SELECT COUNT(*) as cnt FROM group_short_term WHERE group_id = ?',
    [groupId],
  );
  return result.first['cnt'] as int;
}

Future<void> _deleteOldestGroupShortTerm(String groupId, int keep) async {
  final db = await DatabaseService.database;
  final countResult = await db.rawQuery(
    'SELECT COUNT(*) as cnt FROM group_short_term WHERE group_id = ?',
    [groupId],
  );
  final total = countResult.first['cnt'] as int;
  if (total > keep) {
    final toDelete = total - keep;
    // 先收集要删除的 client_id 用于墓碑
    try {
      final rows = await db.rawQuery(
        'SELECT client_id FROM group_short_term WHERE group_id = ? AND id IN (SELECT id FROM group_short_term WHERE group_id = ? ORDER BY timestamp ASC LIMIT ?)',
        [groupId, groupId, toDelete],
      );
      for (final row in rows) {
        final cid = row['client_id']?.toString() ?? '';
        if (cid.isNotEmpty) {
          await _insertTombstone(db, 'group_short_term', cid);
        }
      }
    } catch (e) {
      debugPrint('[Tombstone] record for group_short_term failed: $e');
    }
    await db.rawDelete(
      'DELETE FROM group_short_term WHERE group_id = ? AND id IN (SELECT id FROM group_short_term WHERE group_id = ? ORDER BY timestamp ASC LIMIT ?)',
      [groupId, groupId, toDelete],
    );
  }
}

Future<void> _clearGroupShortTerm(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_short_term', 'group_id = ?', [
    groupId,
  ]);
  await db.delete(
    'group_short_term',
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}

/// 获取未处理的群聊短期记忆，用于 Memory AI 去重分析
Future<List<Map<String, dynamic>>> _getUnprocessedGroupShortTerm(
  String groupId,
) async {
  final db = await DatabaseService.database;
  final rows = await db.query(
    'group_short_term',
    where:
        'group_id = ? AND (memory_ai_processed = 0 OR memory_ai_processed IS NULL)',
    whereArgs: [groupId],
    orderBy: 'timestamp ASC',
  );
  return rows
      .map(
        (r) => {
          'id': r['id'] as int,
          'role': r['role'] as String,
          'content': r['content'] as String? ?? '',
        },
      )
      .toList();
}

/// 标记群聊短期记忆为已由 Memory AI 处理
Future<void> _markGroupShortTermProcessed(List<int> ids) async {
  if (ids.isEmpty) return;
  final db = await DatabaseService.database;
  final placeholders = List.filled(ids.length, '?').join(',');
  await db.update(
    'group_short_term',
    {'memory_ai_processed': 1},
    where: 'id IN ($placeholders)',
    whereArgs: ids,
  );
}

// ─── 群共享记忆 ───

Future<List<GroupSharedMemory>> _getGroupSharedMemories(String groupId) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'group_shared_memories',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'id ASC',
  );
  return maps.map(GroupSharedMemory.fromMap).toList();
}

Future<void> _insertGroupSharedMemory(GroupSharedMemory m) async {
  final db = await DatabaseService.database;
  // 纯创建路径：id 即 client_id（同为 UUID）；abort 让主键碰撞暴露而非静默覆盖
  final map = m.toMap()..['client_id'] = m.id;
  await db.insert(
    'group_shared_memories',
    map,
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}

Future<void> _updateGroupSharedMemory(GroupSharedMemory m) async {
  final db = await DatabaseService.database;
  await db.update(
    'group_shared_memories',
    {
      'field': m.field,
      'content': m.content,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [m.id],
  );
}

Future<void> _deleteGroupSharedMemory(String id) async {
  final db = await DatabaseService.database;
  await _recordTombstoneSingle('group_shared_memories', id);
  await db.delete('group_shared_memories', where: 'id = ?', whereArgs: [id]);
}

// ─── 支持 group_id 的长期/基础记忆查询 ───

Future<List<LongTermMemory>> _getLongTermMemoriesForGroup(
  String agentId,
  String groupId,
) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'long_term_memories',
    where: 'agent_id = ? AND group_id = ?',
    whereArgs: [agentId, groupId],
    orderBy: 'id ASC',
  );
  return maps.map(LongTermMemory.fromMap).toList();
}

Future<List<BaseMemory>> _getBaseMemoriesForGroup(
  String agentId,
  String groupId,
) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'base_memories',
    where: 'agent_id = ? AND group_id = ?',
    whereArgs: [agentId, groupId],
    orderBy: 'id ASC',
  );
  return maps.map(BaseMemory.fromMap).toList();
}

// ─── 私聊短期记忆裁剪（linked 群镜像写入后调用）───

/// 私聊短期记忆裁剪：仅保留最近 [keep] 条（linked 群镜像写入后调用）
Future<void> _trimShortTermMessages({
  required String agentId,
  required int keep,
}) async {
  final db = await DatabaseService.database;
  final rows = await db.query(
    'short_term_messages',
    columns: ['id'],
    where: 'agent_id = ?',
    whereArgs: [agentId],
    orderBy: 'timestamp ASC',
  );
  final excess = rows.length - keep;
  if (excess <= 0) return;
  for (final row in rows.take(excess)) {
    await DatabaseService.deleteShortTermMessage(
      row['id'] as String,
      agentId: agentId,
    );
  }
}
