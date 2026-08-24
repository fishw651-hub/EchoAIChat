// DatabaseService 的providers / token_usage / stickers / token_cost / novel / user_profiles / draft_uploads实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

// ─── 供应商 ───

Future<List<ProviderConfig>> _getProviders() async {
  final db = await DatabaseService.database;
  final maps = await db.query('providers', orderBy: 'id ASC');
  return maps.map(ProviderConfig.fromMap).toList();
}

// ⚠️ providers 表的 api_key 当前为明文存储且该表在 13 表同步范围内——
// 此路径目前无调用方（休眠代码）。重新启用前必须先把 key 移到
// flutter_secure_storage 或恢复加密写入，并从同步范围排除，否则明文上云。
Future<int> _insertProvider(ProviderConfig p) async {
  final db = await DatabaseService.database;
  return await db.insert('providers', p.toMap());
}

Future<void> _updateProvider(ProviderConfig p) async {
  final db = await DatabaseService.database;
  await db.update('providers', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
}

Future<void> _deleteProvider(int id) async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('providers', 'id = ?', [id]);
  await db.delete('providers', where: 'id = ?', whereArgs: [id]);
}

// ─── Token 用量 ───

Future<void> _insertTokenUsage({
  required int promptTokens,
  required int completionTokens,
  String? model,
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  await db.insert('token_usage', {
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'model': model,
    'agent_id': agentId,
  });
}

Future<List<Map<String, dynamic>>> _getTokenUsage({
  int days = 30,
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  final cutoff = DateTime.now()
      .subtract(Duration(days: days))
      .millisecondsSinceEpoch;
  final where = agentId != null
      ? 'timestamp >= ? AND agent_id = ?'
      : 'timestamp >= ?';
  final whereArgs = agentId != null ? [cutoff, agentId] : [cutoff];
  return await db.query(
    'token_usage',
    where: where,
    whereArgs: whereArgs,
    orderBy: 'timestamp ASC',
  );
}

// ─── 表情包 / 贴纸快照 ───

Future<String> _insertSticker({
  required String id,
  required String description,
  required String imagePath,
  required int createdAt,
  required int updatedAt,
}) async {
  final db = await DatabaseService.database;
  await db.insert('stickers', {
    'id': id,
    'description': description,
    'image_path': imagePath,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': null,
  });
  return id;
}

Future<List<Map<String, dynamic>>> _getStickers({
  bool includeDeleted = false,
}) async {
  final db = await DatabaseService.database;
  return db.query(
    'stickers',
    where: includeDeleted ? null : 'deleted_at IS NULL',
    orderBy: 'created_at ASC',
  );
}

Future<void> _updateSticker({
  required String id,
  required String description,
  required int updatedAt,
}) async {
  final db = await DatabaseService.database;
  await db.update(
    'stickers',
    {'description': description, 'updated_at': updatedAt},
    where: 'id = ? AND deleted_at IS NULL',
    whereArgs: [id],
  );
}

Future<void> _softDeleteSticker(String id, int deletedAt) async {
  final db = await DatabaseService.database;
  await db.update(
    'stickers',
    {'deleted_at': deletedAt, 'updated_at': deletedAt},
    where: 'id = ? AND deleted_at IS NULL',
    whereArgs: [id],
  );
}

Future<void> _insertStickerMessageSnapshot({
  required int chatMessageId,
  required String? stickerId,
  required String description,
  required String imagePath,
  required int createdAt,
}) async {
  final db = await DatabaseService.database;
  await db.insert('local_sticker_messages', {
    'chat_message_id': chatMessageId,
    'sticker_id': stickerId,
    'description_snapshot': description,
    'image_path_snapshot': imagePath,
    'created_at': createdAt,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Map<String, dynamic>?> _getStickerMessageSnapshot(
  int chatMessageId,
) async {
  final db = await DatabaseService.database;
  final rows = await db.query(
    'local_sticker_messages',
    where: 'chat_message_id = ?',
    whereArgs: [chatMessageId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

/// 批量取贴纸快照：一次 IN 查询替代每条消息一次往返（N+1）。
/// 返回 chat_message_id → 快照行。SQLite 变量上限 999，按 500 分批。
Future<Map<int, Map<String, dynamic>>> _getStickerMessageSnapshots(
  List<int> chatMessageIds,
) async {
  if (chatMessageIds.isEmpty) return const {};
  final db = await DatabaseService.database;
  final result = <int, Map<String, dynamic>>{};
  for (var i = 0; i < chatMessageIds.length; i += 500) {
    final chunk = chatMessageIds.sublist(
      i,
      i + 500 > chatMessageIds.length ? chatMessageIds.length : i + 500,
    );
    final placeholders = List.filled(chunk.length, '?').join(',');
    final rows = await db.query(
      'local_sticker_messages',
      where: 'chat_message_id IN ($placeholders)',
      whereArgs: chunk,
    );
    for (final row in rows) {
      result[row['chat_message_id'] as int] = row;
    }
  }
  return result;
}

// ─── Token Cost ───

Future<void> _upsertTokenCost({
  required String model,
  required double price,
  required String unit,
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  final existing = await db.query(
    'token_cost',
    where: 'model = ? AND agent_id IS ?',
    whereArgs: [model, agentId],
  );
  if (existing.isNotEmpty) {
    await db.update(
      'token_cost',
      {'price': price, 'unit': unit},
      where: 'model = ? AND agent_id IS ?',
      whereArgs: [model, agentId],
    );
  } else {
    await db.insert('token_cost', {
      'model': model,
      'price': price,
      'unit': unit,
      'agent_id': agentId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

Future<Map<String, dynamic>?> _getTokenPrice({
  required String model,
  String? agentId,
}) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'token_cost',
    where: 'model = ? AND agent_id IS ?',
    whereArgs: [model, agentId],
  );
  if (maps.isEmpty) return null;
  return {
    'price': (maps.first['price'] as num).toDouble(),
    'unit': maps.first['unit'] as String,
  };
}

Future<List<Map<String, dynamic>>> _getAllTokenCosts() async {
  final db = await DatabaseService.database;
  return await db.query('token_cost', orderBy: 'created_at DESC');
}

Future<void> _deleteTokenCost(String model, {String? agentId}) async {
  final db = await DatabaseService.database;
  await db.delete(
    'token_cost',
    where: 'model = ? AND agent_id IS ?',
    whereArgs: [model, agentId],
  );
}

// ─── 小说生成 ───

Future<int> _insertNovelGeneration({
  required String style,
  required int wordCount,
  required String prompt,
  required String result,
}) async {
  final db = await DatabaseService.database;
  return await db.insert('novel_generations', {
    'style': style,
    'word_count': wordCount,
    'prompt': prompt,
    'result': result,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });
}

Future<List<Map<String, dynamic>>> _getNovelGenerations() async {
  final db = await DatabaseService.database;
  return await db.query('novel_generations', orderBy: 'timestamp DESC');
}

Future<void> _deleteNovelGeneration(int id) async {
  final db = await DatabaseService.database;
  await db.delete('novel_generations', where: 'id = ?', whereArgs: [id]);
}

// ─── Profile Entries ───

Future<List<ProfileEntry>> _getProfileEntries() async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'user_profiles',
    orderBy: 'category ASC, key ASC',
  );
  return maps.map(ProfileEntry.fromMap).toList();
}

Future<List<ProfileEntry>> _getProfileEntriesByCategory(String category) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'user_profiles',
    where: 'category = ?',
    whereArgs: [category],
    orderBy: 'updated_at DESC',
  );
  return maps.map(ProfileEntry.fromMap).toList();
}

Future<ProfileEntry?> _getProfileEntry(String key, String category) async {
  final db = await DatabaseService.database;
  final maps = await db.query(
    'user_profiles',
    where: 'key = ? AND category = ?',
    whereArgs: [key, category],
    limit: 1,
  );
  return maps.isNotEmpty ? ProfileEntry.fromMap(maps.first) : null;
}

Future<void> _insertProfileEntry(ProfileEntry entry) async {
  final db = await DatabaseService.database;
  await db.insert(
    'user_profiles',
    entry.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _updateProfileEntry(ProfileEntry entry) async {
  final db = await DatabaseService.database;
  await db.update(
    'user_profiles',
    entry.toMap(),
    where: 'id = ?',
    whereArgs: [entry.id],
  );
}

Future<void> _deleteProfileEntry(String id) async {
  final db = await DatabaseService.database;
  await _recordTombstoneSingle('user_profiles', id);
  await db.delete('user_profiles', where: 'id = ?', whereArgs: [id]);
}

Future<int> _getProfileEntryCount() async {
  final db = await DatabaseService.database;
  final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM user_profiles');
  return result.isNotEmpty ? (result.first['cnt'] as int) : 0;
}

Future<void> _clearProfileEntries() async {
  final db = await DatabaseService.database;
  await _recordTombstonesBeforeDelete('user_profiles', '1=1', []);
  await db.delete('user_profiles');
}

// ─── 草稿箱 ───

Future<List<Map<String, dynamic>>> _getAllDrafts() async {
  final db = await DatabaseService.database;
  final result = await db.query('draft_uploads', orderBy: 'updated_at DESC');
  return result;
}

Future<List<Map<String, dynamic>>> _getDraftsByType(String type) async {
  final db = await DatabaseService.database;
  final result = await db.query(
    'draft_uploads',
    where: 'type = ?',
    whereArgs: [type],
    orderBy: 'updated_at DESC',
  );
  return result;
}

Future<Map<String, dynamic>?> _getDraft(String id) async {
  final db = await DatabaseService.database;
  final result = await db.query(
    'draft_uploads',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return result.isEmpty ? null : result.first;
}

Future<String> _insertDraft({
  required String type,
  required String data,
  String? name,
  int? coverColor,
}) async {
  final db = await DatabaseService.database;
  final id = '${DateTime.now().millisecondsSinceEpoch}_${type[0]}';
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('draft_uploads', {
    'id': id,
    'type': type,
    'name': name,
    'data': data,
    'cover_color': coverColor,
    'updated_at': now,
    'created_at': now,
  });
  return id;
}

Future<void> _updateDraft(
  String id, {
  String? name,
  String? data,
  int? coverColor,
}) async {
  final db = await DatabaseService.database;
  final updates = <String, dynamic>{};
  if (name != null) updates['name'] = name;
  if (data != null) updates['data'] = data;
  if (coverColor != null) updates['cover_color'] = coverColor;
  updates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
  await db.update('draft_uploads', updates, where: 'id = ?', whereArgs: [id]);
}

Future<void> _deleteDraft(String id) async {
  final db = await DatabaseService.database;
  await db.delete('draft_uploads', where: 'id = ?', whereArgs: [id]);
}
