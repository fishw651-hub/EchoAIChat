import 'dart:io';

import 'package:aichat/services/account_database_scope.dart';
import 'package:aichat/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directory = await Directory.systemTemp.createTemp('aichat-db-migration-');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.onAccountSwitched = null;
    await DatabaseService.closeForTesting();
  });

  tearDown(() async {
    await DatabaseService.closeForTesting();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('v38 账号库包含本地迁移状态表', () async {
    await DatabaseService.switchAccount(101);
    final database = await DatabaseService.database;

    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'local_database_migrations'",
    );

    expect(await database.getVersion(), 38);
    expect(tables, hasLength(1));
  });

  test('目标账号库已存在时仍迁移 v37 旧库', () async {
    await DatabaseService.switchAccount(101);
    final target = await DatabaseService.database;
    await target.insert('agents', _agentRow('target-agent', '目标数据'));
    await DatabaseService.closeForTesting();
    await _seedLegacyDatabase(version: 37);

    await DatabaseService.switchAccount(101);
    final migrated = await DatabaseService.database;

    expect(
      await migrated.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['target-agent'],
      ),
      hasLength(1),
    );
    expect(
      await migrated.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['legacy-agent'],
      ),
      hasLength(1),
    );
  });

  test('低于 v35 的旧库不迁移也不删除', () async {
    final legacyPath = await _seedLegacyDatabase(version: 34);

    await expectLater(DatabaseService.switchAccount(101), throwsStateError);

    expect(await File(legacyPath).exists(), isTrue);
  });

  test('迁移覆盖聊天记忆群聊画像编组和其余业务数据', () async {
    final legacyPath = await _seedLegacyDatabase(version: 37);
    await _seedCompleteLegacyGraph(legacyPath);

    await DatabaseService.switchAccount(101);
    final database = await DatabaseService.database;

    for (final table in const [
      'long_term_memories',
      'base_memories',
      'short_term_messages',
      'chat_messages',
      'group_chats',
      'group_members',
      'group_messages',
      'group_short_term',
      'group_shared_memories',
      'user_profiles',
      'stickers',
      'local_sticker_messages',
      'agent_folders',
      'agent_folder_members',
      'planned_messages',
      'providers',
      'token_usage',
      'token_cost',
      'novel_generations',
      'draft_uploads',
    ]) {
      expect(
        await database.query(table),
        isNotEmpty,
        reason: '$table 应迁移旧版业务数据',
      );
    }
    final chat = (await database.query('chat_messages')).single;
    final stickerSnapshot = (await database.query(
      'local_sticker_messages',
    )).single;
    expect(chat['id'], isNot(900));
    expect(stickerSnapshot['chat_message_id'], chat['id']);
  });

  test('账号库较新的智能体和画像不被旧数据覆盖', () async {
    await DatabaseService.switchAccount(101);
    final target = await DatabaseService.database;
    await target.insert(
      'agents',
      _agentRow('same-agent', '目标新版人设', updatedAt: 200),
    );
    await target.insert('user_profiles', {
      'id': 'target-profile',
      'category': 'identity',
      'key': 'name',
      'value': '目标新版画像',
      'created_at': 1,
      'updated_at': 200,
    });
    await DatabaseService.closeForTesting();

    final legacyPath = await _seedLegacyDatabase(version: 37);
    final legacy = await databaseFactory.openDatabase(legacyPath);
    await legacy.insert(
      'agents',
      _agentRow('same-agent', '旧版人设', updatedAt: 100),
    );
    await legacy.insert('user_profiles', {
      'id': 'legacy-profile',
      'category': 'identity',
      'key': 'name',
      'value': '旧版画像',
      'created_at': 1,
      'updated_at': 100,
    });
    await legacy.close();

    await DatabaseService.switchAccount(101);
    final migrated = await DatabaseService.database;
    final agent = (await migrated.query(
      'agents',
      where: 'id = ?',
      whereArgs: ['same-agent'],
    )).single;
    final profile = (await migrated.query(
      'user_profiles',
      where: 'category = ? AND key = ?',
      whereArgs: ['identity', 'name'],
    )).single;

    expect(agent['persona'], '目标新版人设');
    expect(profile['value'], '目标新版画像');
  });

  test('悬空智能体引用使全部迁移回滚并保留旧库', () async {
    final legacyPath = await _seedLegacyDatabase(version: 37);
    final legacy = await databaseFactory.openDatabase(legacyPath);
    await legacy.insert('chat_messages', {
      'role': 'user',
      'content': '悬空消息',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'agent_id': 'missing-agent',
      'client_id': 'orphan-chat',
    });
    await legacy.close();

    await expectLater(DatabaseService.switchAccount(101), throwsStateError);

    expect(await File(legacyPath).exists(), isTrue);
    final target = await _openAccountDatabaseDirectly(101);
    expect(await target.query('agents'), isEmpty);
    expect(await target.query('chat_messages'), isEmpty);
    expect(await target.query('local_database_migrations'), isEmpty);
    await target.close();
  });

  test('迁移提交后删除旧库并记录 cleaned 状态且重复启动不重复导入', () async {
    final legacyPath = await _seedLegacyDatabase(version: 37);
    await _seedCompleteLegacyGraph(legacyPath);

    await DatabaseService.switchAccount(101);
    var database = await DatabaseService.database;
    expect(await database.query('token_usage'), hasLength(1));
    expect(await File(legacyPath).exists(), isFalse);
    expect(
      await database.query(
        'local_database_migrations',
        where: 'state = ?',
        whereArgs: ['cleaned'],
      ),
      hasLength(1),
    );

    await DatabaseService.closeForTesting();
    await DatabaseService.switchAccount(101);
    database = await DatabaseService.database;
    expect(await database.query('token_usage'), hasLength(1));
  });

  test('第二个账号不能读取第一个账号已认领但迁移失败的旧库', () async {
    final legacyPath = await _seedLegacyDatabase(version: 34);
    await expectLater(DatabaseService.switchAccount(101), throwsStateError);
    await DatabaseService.closeForTesting();

    await DatabaseService.switchAccount(202);
    final secondAccount = await DatabaseService.database;

    expect(await File(legacyPath).exists(), isTrue);
    expect(
      await secondAccount.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['legacy-agent'],
      ),
      isEmpty,
    );
  });

  for (final version in const [35, 36]) {
    test('v$version 近期旧库升级后迁移到 v38', () async {
      final legacyPath = await _seedLegacyDatabase(version: version);
      final legacy = await databaseFactory.openDatabase(legacyPath);
      await legacy.insert('long_term_memories', {
        'id': version == 35 ? 'L001' : 'L-v36-existing',
        'field': 'identity',
        'content': 'v$version 记忆',
        'agent_id': 'legacy-agent',
        'client_id': version == 35 ? 'L001' : 'L-v36-existing',
        'created_at': 1,
        'updated_at': 2,
      });
      await legacy.close();

      await DatabaseService.switchAccount(101);
      final database = await DatabaseService.database;
      final memory = (await database.query(
        'long_term_memories',
        where: 'content = ?',
        whereArgs: ['v$version 记忆'],
      )).single;
      final agent = (await database.query(
        'agents',
        where: 'id = ?',
        whereArgs: ['legacy-agent'],
      )).single;

      expect(memory['id'], startsWith('L-'));
      expect(memory['id'], isNot('L001'));
      expect(agent['max_response_length'], 300);
      expect(await database.getVersion(), 38);
    });
  }

  test('空 client_id 使用源库指纹生成确定性迁移键', () async {
    final legacyPath = await _seedLegacyDatabase(version: 37);
    final legacy = await databaseFactory.openDatabase(legacyPath);
    await legacy.insert('chat_messages', {
      'id': 700,
      'role': 'user',
      'content': '没有 client id',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'agent_id': 'legacy-agent',
    });
    await legacy.close();

    await DatabaseService.switchAccount(101);
    final database = await DatabaseService.database;
    final migrated = (await database.query(
      'chat_messages',
      where: 'content = ?',
      whereArgs: ['没有 client id'],
    )).single;

    expect(
      migrated['client_id'],
      matches(RegExp(r'^legacy-migration:[0-9a-f]{64}:chat_messages:700$')),
    );
  });
}

Map<String, Object?> _agentRow(
  String id,
  String persona, {
  int updatedAt = 1,
}) => {
  'id': id,
  'name': id,
  'persona': persona,
  'created_at': 1,
  'updated_at': updatedAt,
};

Future<String> _seedLegacyDatabase({required int version}) async {
  const templateUserId = 999999;
  await DatabaseService.switchAccount(templateUserId);
  final template = await DatabaseService.database;
  await template.rawQuery('PRAGMA wal_checkpoint(FULL)');
  await DatabaseService.closeForTesting();

  final databasesPath = await databaseFactory.getDatabasesPath();
  final templatePath = path.join(
    databasesPath,
    AccountDatabaseScope.databaseNameFor(templateUserId),
  );
  final legacyPath = path.join(
    databasesPath,
    AccountDatabaseMigration.legacyDatabaseName,
  );
  await File(templatePath).copy(legacyPath);

  final legacy = await databaseFactory.openDatabase(legacyPath);
  try {
    await legacy.execute('DROP TABLE IF EXISTS local_database_migrations');
    await legacy.insert('agents', _agentRow('legacy-agent', '旧版数据'));
    await legacy.setVersion(version);
  } finally {
    await legacy.close();
  }
  return legacyPath;
}

Future<void> _seedCompleteLegacyGraph(String legacyPath) async {
  final legacy = await databaseFactory.openDatabase(legacyPath);
  final recentTimestamp = DateTime.now().millisecondsSinceEpoch;
  try {
    await legacy.insert('long_term_memories', {
      'id': 'L-legacy-memory',
      'field': 'identity',
      'content': '长期记忆',
      'agent_id': 'legacy-agent',
      'created_at': 1,
      'updated_at': 2,
    });
    await legacy.insert('base_memories', {
      'id': 'B-legacy-memory',
      'type': 'setting',
      'content': '基础记忆',
      'agent_id': 'legacy-agent',
      'created_at': 1,
      'updated_at': 2,
    });
    await legacy.insert('short_term_messages', {
      'id': 'short-legacy',
      'role': 'user',
      'content': '短期消息',
      'timestamp': 3,
      'agent_id': 'legacy-agent',
      'memory_ai_processed': 1,
      'image_paths': '["legacy.png"]',
    });
    await legacy.insert('chat_messages', {
      'id': 900,
      'role': 'user',
      'content': 'legacy sticker message',
      'timestamp': 4,
      'short_mem_id': 'short-legacy',
      'agent_id': 'legacy-agent',
      'client_id': 'legacy-chat-client',
    });
    await legacy.insert('group_chats', {
      'id': 'legacy-group',
      'name': '旧群聊',
      'linked_memory': 1,
      'created_at': 1,
      'updated_at': 2,
    });
    await legacy.insert('group_members', {
      'id': 901,
      'group_id': 'legacy-group',
      'agent_id': 'legacy-agent',
      'joined_at': 1,
      'client_id': 'legacy-member-client',
    });
    await legacy.insert('group_messages', {
      'id': 902,
      'group_id': 'legacy-group',
      'sender_type': 'agent',
      'sender_id': 'legacy-agent',
      'sender_name': '旧智能体',
      'content': '群消息',
      'timestamp': 5,
      'client_id': 'legacy-group-message-client',
    });
    await legacy.insert('group_short_term', {
      'id': 903,
      'group_id': 'legacy-group',
      'role': 'assistant',
      'sender_name': '旧智能体',
      'content': '群短期消息',
      'timestamp': 5,
      'client_id': 'legacy-group-short-client',
    });
    await legacy.insert('group_shared_memories', {
      'id': 'GS-legacy-memory',
      'group_id': 'legacy-group',
      'field': 'event',
      'content': '群共享记忆',
      'updated_at': 6,
    });
    await legacy.insert('user_profiles', {
      'id': 'profile-legacy',
      'category': 'identity',
      'key': 'nickname',
      'value': '旧画像',
      'created_at': 1,
      'updated_at': 7,
    });
    await legacy.insert('stickers', {
      'id': 'sticker-legacy',
      'description': '旧表情',
      'image_path': 'sticker.png',
      'created_at': 1,
      'updated_at': 2,
    });
    await legacy.insert('local_sticker_messages', {
      'chat_message_id': 900,
      'sticker_id': 'sticker-legacy',
      'description_snapshot': '旧表情',
      'image_path_snapshot': 'sticker.png',
      'created_at': 4,
    });
    await legacy.insert('agent_folders', {
      'id': 'folder-legacy',
      'name': '旧编组',
      'created_at': 1,
    });
    await legacy.insert('agent_folder_members', {
      'folder_id': 'folder-legacy',
      'agent_id': 'legacy-agent',
    });
    await legacy.insert('planned_messages', {
      'id': 904,
      'scheduled_time': 10,
      'message': '旧计划',
      'agent_id': 'legacy-agent',
      'client_id': 'legacy-plan-client',
    });
    await legacy.insert('providers', {
      'id': 905,
      'name': 'legacy-provider',
      'api_base_url': 'https://example.com',
      'api_key': 'encrypted',
      'created_at': 1,
      'client_id': 'legacy-provider-client',
    });
    await legacy.insert('token_usage', {
      'id': 906,
      'timestamp': recentTimestamp,
      'prompt_tokens': 12,
      'completion_tokens': 13,
      'agent_id': 'legacy-agent',
    });
    await legacy.insert('token_cost', {
      'id': 907,
      'model': 'legacy-model',
      'price': 0.1,
      'unit': 'per_1000',
      'agent_id': 'legacy-agent',
      'created_at': 1,
    });
    await legacy.insert('novel_generations', {
      'id': 908,
      'style': 'legacy-style',
      'word_count': 500,
      'prompt': '旧提示',
      'result': '旧小说',
      'timestamp': recentTimestamp,
    });
    await legacy.insert('draft_uploads', {
      'id': 'draft-legacy',
      'type': 'agent',
      'name': '旧草稿',
      'data': '{}',
      'created_at': 1,
      'updated_at': 2,
    });
  } finally {
    await legacy.close();
  }
}

Future<Database> _openAccountDatabaseDirectly(int userId) async {
  final databasesPath = await databaseFactory.getDatabasesPath();
  return databaseFactory.openDatabase(
    path.join(databasesPath, AccountDatabaseScope.databaseNameFor(userId)),
  );
}
