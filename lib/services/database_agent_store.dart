// DatabaseService 的agents / agent_folders / agent_folder_members实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── Agents ───

Future<List<Agent>> _getAgents() async {
  final db = await DatabaseService.database;
  final maps = await db.query('agents', orderBy: 'created_at ASC');
  return maps.map(Agent.fromMap).toList();
}

Future<Agent?> _getActiveAgent() async {
  final db = await DatabaseService.database;
  final maps = await db.query('agents', where: 'is_active = 1', limit: 1);
  return maps.isNotEmpty ? Agent.fromMap(maps.first) : null;
}

Future<Agent?> _getAgent(String id) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'agents',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return maps.isNotEmpty ? Agent.fromMap(maps.first) : null;
}

/// 按 name + persona 查询本地智能体（用于网络下载去重）
/// 返回第一条匹配记录，无匹配返回 null
Future<Agent?> _findAgentByNameAndPersona(String name, String persona) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'agents',
    where: 'name = ? AND persona = ?',
    whereArgs: [name, persona],
    limit: 1,
  );
  return maps.isNotEmpty ? Agent.fromMap(maps.first) : null;
}

Future<void> _insertAgent(Agent agent) async {
  final db = await DatabaseService.database;
  await db.insert(
    'agents',
    agent.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _updateAgent(Agent agent) async {
  final db = await DatabaseService.database;
  await db.update(
    'agents',
    agent.toMap(),
    where: 'id = ?',
    whereArgs: [agent.id],
  );
}

Future<void> _deleteAgent(String id) async {
  final db = await DatabaseService.database;
  // 墓碑记录与删除操作在同一事务中，避免产生孤儿墓碑
  await db.transaction((txn) async {
    // 先记录墓碑（查询 client_id 并写入 local_tombstones）
    await _recordTombstoneSingleInTxn(txn, 'agents', id);
    await _recordTombstonesInTxn(txn, 'group_members', 'agent_id = ?', [id]);
    await _recordTombstonesInTxn(txn, 'long_term_memories', 'agent_id = ?', [
      id,
    ]);
    await _recordTombstonesInTxn(txn, 'base_memories', 'agent_id = ?', [id]);
    await _recordTombstonesInTxn(txn, 'short_term_messages', 'agent_id = ?', [
      id,
    ]);
    await _recordTombstonesInTxn(txn, 'chat_messages', 'agent_id = ?', [id]);
    await _recordTombstonesInTxn(txn, 'planned_messages', 'agent_id = ?', [id]);
    // 执行删除
    await txn.delete('group_members', where: 'agent_id = ?', whereArgs: [id]);
    // 编组映射（本地数据，无墓碑）
    await txn.delete(
      'agent_folder_members',
      where: 'agent_id = ?',
      whereArgs: [id],
    );
    await txn.delete('agents', where: 'id = ?', whereArgs: [id]);
    for (final table in [
      'long_term_memories',
      'base_memories',
      'short_term_messages',
      'chat_messages',
      'planned_messages',
      'debug_logs',
      'token_usage',
    ]) {
      await txn.delete(table, where: 'agent_id = ?', whereArgs: [id]);
    }
  });
}

Future<void> _setActiveAgent(String id) async {
  final db = await DatabaseService.database;
  await db.transaction((txn) async {
    await txn.update('agents', {'is_active': 0});
    await txn.update(
      'agents',
      {'is_active': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  });
}

// ─── 智能体编组（本地数据，不参与多端同步）───

Future<String> _createAgentFolder(String name) async {
  final db = await DatabaseService.database;
  final id = 'folder_${const Uuid().v4()}';
  await db.insert('agent_folders', {
    'id': id,
    'name': name,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
  return id;
}

Future<void> _renameAgentFolder(String id, String name) async {
  final db = await DatabaseService.database;
  await db.update(
    'agent_folders',
    {'name': name},
    where: 'id = ?',
    whereArgs: [id],
  );
}

/// 解散编组：只删除编组及其成员映射，不删除智能体
Future<void> _deleteAgentFolder(String id) async {
  final db = await DatabaseService.database;
  await db.delete(
    'agent_folder_members',
    where: 'folder_id = ?',
    whereArgs: [id],
  );
  await db.delete('agent_folders', where: 'id = ?', whereArgs: [id]);
}

/// 批量加入编组。一个智能体只属于一个编组：加入前会先删除其旧编组映射
Future<void> _addAgentsToFolder(String folderId, List<String> agentIds) async {
  final db = await DatabaseService.database;
  final batch = db.batch();
  for (final agentId in agentIds) {
    batch.delete(
      'agent_folder_members',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
    batch.insert('agent_folder_members', {
      'folder_id': folderId,
      'agent_id': agentId,
    });
  }
  await batch.commit(noResult: true);
}

/// 将智能体从其所属编组中移出
Future<void> _removeAgentsFromFolder(List<String> agentIds) async {
  if (agentIds.isEmpty) return;
  final db = await DatabaseService.database;
  final placeholders = List.filled(agentIds.length, '?').join(',');
  await db.delete(
    'agent_folder_members',
    where: 'agent_id IN ($placeholders)',
    whereArgs: agentIds,
  );
}

Future<List<String>> _getFolderMemberAgentIds(String folderId) async {
  final db = await DatabaseService.database;
  final rows = await db.query(
    'agent_folder_members',
    columns: ['agent_id'],
    where: 'folder_id = ?',
    whereArgs: [folderId],
  );
  return rows.map((r) => r['agent_id'] as String).toList();
}

/// 所有编组及成员数（按创建时间升序）
Future<List<Map<String, dynamic>>> _getAgentFolders() async {
  final db = await DatabaseService.database;
  return await db.rawQuery('''SELECT f.id, f.name, f.created_at,
         (SELECT COUNT(*) FROM agent_folder_members m WHERE m.folder_id = f.id) AS member_count
       FROM agent_folders f ORDER BY f.created_at ASC''');
}

/// agent_id → folder_id 映射（一个智能体最多一条）
Future<Map<String, String>> _getAgentFolderMemberships() async {
  final db = await DatabaseService.database;
  final rows = await db.query('agent_folder_members');
  return {
    for (final r in rows) r['agent_id'] as String: r['folder_id'] as String,
  };
}
