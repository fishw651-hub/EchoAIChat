// DatabaseService 的chat_messages / planned_messages / group_chats / group_members / group_messages实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── 聊天消息 ───

Future<int> _insertChatMessage({
  required String role,
  required String content,
  required int timestampMs,
  String? shortMemId,
  String? agentId,
  String? imagePath,
  List<String>? imagePaths,
}) async {
  final db = await DatabaseService.database;
  return await db.insert('chat_messages', {
    'role': role,
    'content': content,
    'timestamp': timestampMs,
    'short_mem_id': shortMemId,
    'agent_id': agentId,
    // image_path 保留写入首图兼容旧版读取；完整列表存 image_paths（JSON 数组）
    'image_path':
        imagePath ??
        ((imagePaths != null && imagePaths.isNotEmpty)
            ? imagePaths.first
            : null),
    'image_paths': ImagePathsCodec.encode(imagePaths),
  });
}

/// 分页读取聊天消息。默认（limit=null）保持原全量行为；
/// 指定 limit 时按 id 倒序取最新 limit 条，beforeId 用于向上翻页
/// （只取 id < beforeId 的更早消息）。返回值恒为时间正序。
Future<List<Map<String, dynamic>>> _getChatMessages({
  String? agentId,
  int? limit,
  int? beforeId,
}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    if (limit == null) {
      return await db.query(
        'chat_messages',
        where: 'agent_id = ?',
        whereArgs: [agentId],
        orderBy: 'timestamp ASC',
      );
    }
    final where = beforeId != null ? 'agent_id = ? AND id < ?' : 'agent_id = ?';
    final whereArgs = beforeId != null ? [agentId, beforeId] : [agentId];
    final rows = await db.query(
      'chat_messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.toList();
  }
  debugPrint(
    '[DB] WARNING: getChatMessages called without agentId — returning empty',
  );
  return [];
}

/// 该智能体聊天消息总数（配合分页判断 hasMore）
Future<int> _getChatMessageCount(String agentId) async {
  final db = await DatabaseService.database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM chat_messages WHERE agent_id = ?',
    [agentId],
  );
  return (rows.first['c'] as int?) ?? 0;
}

Future<void> _deleteChatMessage(int id) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('chat_messages', 'id = ?', [id]);
  await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
}

/// 更新聊天消息内容（用户重写 AI 消息等场景）。
/// 同步侧说明：内容更新不落墓碑，依赖下次全量/按表同步覆盖云端。
Future<void> _updateChatMessageContent(int id, String content) async {
  final db = await DatabaseService.database;
  await db.update(
    'chat_messages',
    {'content': content},
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<void> _clearChatMessages({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    await _recordTombstonesBeforeDelete('chat_messages', 'agent_id = ?', [
      agentId,
    ]);
    await db.delete(
      'chat_messages',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
  } else {
    debugPrint(
      '[DB] WARNING: clearChatMessages called without agentId — skipping',
    );
  }
}

Future<Map<String, dynamic>?> _getLastChatMessage(String agentId) async {
  final db = await DatabaseService.database;
  final result = await db.query(
    'chat_messages',
    where: 'agent_id = ?',
    whereArgs: [agentId],
    orderBy: 'timestamp DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}

/// 一次性取所有智能体的最新消息（聚合查询）。会话列表用它替代
/// 逐智能体 getLastChatMessage 的 2N 次往返。key = agent_id。
Future<Map<String, Map<String, dynamic>>> _getLastChatMessagesByAgent() async {
  final db = await DatabaseService.database;
  final rows = await db.rawQuery(
    'SELECT cm.* FROM chat_messages cm '
    'INNER JOIN (SELECT agent_id, MAX(id) AS mid FROM chat_messages GROUP BY agent_id) t '
    'ON cm.id = t.mid',
  );
  return {for (final row in rows) row['agent_id'] as String: row};
}

/// 一次性取所有群的最新消息（聚合查询）。key = group_id。
Future<Map<String, Map<String, dynamic>>> _getLastGroupMessagesByGroup() async {
  final db = await DatabaseService.database;
  final rows = await db.rawQuery(
    'SELECT gm.* FROM group_messages gm '
    'INNER JOIN (SELECT group_id, MAX(id) AS mid FROM group_messages GROUP BY group_id) t '
    'ON gm.id = t.mid',
  );
  return {for (final row in rows) row['group_id'] as String: row};
}

Future<Map<String, dynamic>?> _getLastGroupMessage(String groupId) async {
  final db = await DatabaseService.database;
  final result = await db.query(
    'group_messages',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'timestamp DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}

// ─── 计划消息 ───

Future<List<PlannedMessage>> _getPlannedMessages({String? agentId}) async {
  final db = await DatabaseService.database;
  if (agentId != null) {
    final maps = await db.query(
      'planned_messages',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'scheduled_time ASC',
    );
    return maps.map(PlannedMessage.fromMap).toList();
  }
  final maps = await db.query(
    'planned_messages',
    orderBy: 'scheduled_time ASC',
  );
  return maps.map(PlannedMessage.fromMap).toList();
}

Future<int> _insertPlannedMessage(PlannedMessage msg) async {
  final db = await DatabaseService.database;
  return await db.insert('planned_messages', msg.toMap());
}

Future<void> _updatePlannedMessage(PlannedMessage msg) async {
  final db = await DatabaseService.database;
  await db.update(
    'planned_messages',
    msg.toMap(),
    where: 'id = ?',
    whereArgs: [msg.id],
  );
}

Future<void> _deletePlannedMessage(int id) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('planned_messages', 'id = ?', [id]);
  await db.delete('planned_messages', where: 'id = ?', whereArgs: [id]);
}

Future<void> _markDelivered(int id) async {
  final db = await DatabaseService.database;
  await db.update(
    'planned_messages',
    {'delivered': 1},
    where: 'id = ?',
    whereArgs: [id],
  );
}

// ─── 群聊 ───

Future<List<GroupChat>> _getGroupChats() async {
  final db = await DatabaseService.database;
  final maps = await db.query('group_chats', orderBy: 'updated_at DESC');
  return maps.map(GroupChat.fromMap).toList();
}

Future<GroupChat?> _getGroupChat(String id) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'group_chats',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return maps.isNotEmpty ? GroupChat.fromMap(maps.first) : null;
}

Future<void> _insertGroupChat(GroupChat g) async {
  final db = await DatabaseService.database;
  await db.insert(
    'group_chats',
    g.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _updateGroupChat(GroupChat g) async {
  final db = await DatabaseService.database;
  await db.update('group_chats', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
}

Future<void> _deleteGroupChat(String id) async {
  final db = await DatabaseService.database;
  await _recordTombstoneSingle('group_chats', id);
  await db.rawQuery('PRAGMA foreign_keys = ON');
  await db.delete('group_chats', where: 'id = ?', whereArgs: [id]);
}

Future<void> _deleteGroupChatCascade(String groupId) async {
  final db = await DatabaseService.database;
  // 事务前批量收集所有相关表的 client_id 用于墓碑
  await _recordTombstoneSingle('group_chats', groupId);
  await _recordTombstonesBeforeDelete('group_short_term', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete('group_shared_memories', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete('group_messages', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete('group_members', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete('long_term_memories', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete('base_memories', 'group_id = ?', [
    groupId,
  ]);
  await _recordTombstonesBeforeDelete(
    'agents',
    'source_group_id = ? AND is_sim_character = 1',
    [groupId],
  );
  await db.transaction((txn) async {
    await txn.rawQuery('PRAGMA foreign_keys = ON');
    await txn.delete(
      'group_short_term',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete(
      'group_shared_memories',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete(
      'long_term_memories',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete(
      'base_memories',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await txn.delete('group_chats', where: 'id = ?', whereArgs: [groupId]);
    await txn.delete(
      'agents',
      where: 'source_group_id = ? AND is_sim_character = 1',
      whereArgs: [groupId],
    );
  });
  debugPrint('[DB] Cascade deleted group $groupId');
}

Future<void> _deleteGroupMembersForGroup(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_members', 'group_id = ?', [
    groupId,
  ]);
  await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
}

Future<void> _deleteGroupMessagesForGroup(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_messages', 'group_id = ?', [
    groupId,
  ]);
  await db.delete(
    'group_messages',
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}

Future<void> _deleteGroupSharedMemoriesForGroup(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_shared_memories', 'group_id = ?', [
    groupId,
  ]);
  await db.delete(
    'group_shared_memories',
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}

// ─── 群成员 ───

Future<List<GroupMember>> _getGroupMembers(String groupId) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'group_members',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'joined_at ASC',
  );
  return maps.map(GroupMember.fromMap).toList();
}

Future<void> _insertGroupMember(GroupMember m) async {
  final db = await DatabaseService.database;
  await db.insert('group_members', m.toMap());
}

Future<void> _updateGroupMember(GroupMember m) async {
  final db = await DatabaseService.database;
  await db.update(
    'group_members',
    m.toMap(),
    where: 'id = ?',
    whereArgs: [m.id],
  );
}

Future<void> _deleteGroupMember(int id) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_members', 'id = ?', [id]);
  await db.delete('group_members', where: 'id = ?', whereArgs: [id]);
}

Future<void> _deleteAllGroupMembers(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_members', 'group_id = ?', [
    groupId,
  ]);
  await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
}

// ─── 群聊消息 ───

Future<List<GroupMessage>> _getGroupMessages(
  String groupId, {
  int? limit,
  int? beforeId,
}) async {
  final db = await DatabaseService.database;
  if (limit == null) {
    final maps = await db.query(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp ASC',
    );
    return maps.map(GroupMessage.fromMap).toList();
  }
  final maps = await db.query(
    'group_messages',
    where: beforeId != null ? 'group_id = ? AND id < ?' : 'group_id = ?',
    whereArgs: beforeId != null ? [groupId, beforeId] : [groupId],
    orderBy: 'id DESC',
    limit: limit,
  );
  return maps.reversed.map(GroupMessage.fromMap).toList();
}

/// 群消息总数（配合分页判断 hasMore）
Future<int> _getGroupMessageCount(String groupId) async {
  final db = await DatabaseService.database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM group_messages WHERE group_id = ?',
    [groupId],
  );
  return (rows.first['c'] as int?) ?? 0;
}

Future<int> _insertGroupMessage(GroupMessage msg) async {
  final db = await DatabaseService.database;
  return await db.insert('group_messages', msg.toMap());
}

Future<void> _deleteGroupMessage(int id) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_messages', 'id = ?', [id]);
  await db.delete('group_messages', where: 'id = ?', whereArgs: [id]);
}

Future<void> _clearGroupMessages(String groupId) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('group_messages', 'group_id = ?', [
    groupId,
  ]);
  await db.delete(
    'group_messages',
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}
