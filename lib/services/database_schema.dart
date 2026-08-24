// DatabaseService 的schema 建表与迁移（_onCreate/_onUpgrade/_ensureGroupTablesExist）实现。
// 本文件是 database_service.dart 的 part：方法体以库私有顶层函数承载，
// 公有静态外观（DatabaseService.xxx）与签名保留在主文件的一行委托中。
part of 'database_service.dart';

const _currentDatabaseVersion = 38;
const _createLocalDatabaseMigrationsSql = '''
CREATE TABLE IF NOT EXISTS local_database_migrations (
  source_fingerprint TEXT PRIMARY KEY,
  owner_database_name TEXT NOT NULL,
  state TEXT NOT NULL,
  committed_at INTEGER NOT NULL,
  cleaned_at INTEGER,
  error TEXT
)
''';

// ─── 打开数据库 ───

Future<String> _databasePathForName(String databaseName) async {
  if (kIsWeb) return databaseName;
  return join(await getDatabasesPath(), databaseName);
}

Future<Database> _initDatabase({required String databaseName}) async {
  String path;
  if (kIsWeb) {
    // ffi_web 使用 IndexedDB 持久化，路径只需文件名
    path = databaseName;
  } else {
    path = await _databasePathForName(databaseName);
  }
  final db = await openDatabase(
    path,
    version: _currentDatabaseVersion,
    onConfigure: (db) async {
      // WAL 模式在 ffi_web/sqlite-wasm 上可能不支持，失败时静默退化
      try {
        await db.rawQuery('PRAGMA journal_mode=WAL');
      } catch (_) {
        // ffi_web 不支持 WAL，使用默认 journal mode
      }
    },
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
  await _ensureGroupTablesExist(db);
  try {
    await _migrateLegacySyncClientIds(db, deviceId: await DeviceIdService.id);
  } catch (error) {
    debugPrint('[DB] legacy sync client_id migration failed: $error');
  }
  return db;
}

Future<void> _migrateLegacySyncClientIds(
  Database database, {
  required String deviceId,
  List<String> tables = const [
    'chat_messages',
    'group_members',
    'group_messages',
    'group_short_term',
    'planned_messages',
    'providers',
  ],
}) async {
  if (deviceId.isEmpty) return;
  try {
    await database.execute('PRAGMA wal_checkpoint(FULL)');
  } catch (_) {
    // Web SQLite 不支持 WAL checkpoint。
  }
  await database.transaction((transaction) async {
    for (final table in tables) {
      final rows = await transaction.query(
        table,
        columns: ['id', 'client_id'],
        where:
            "client_id IS NOT NULL AND client_id <> '' "
            "AND client_id NOT GLOB '*[^0-9]*'",
      );
      for (final row in rows) {
        final localId = row['id'];
        if (localId == null) continue;
        await transaction.update(
          table,
          {'client_id': '$deviceId:$table:$localId'},
          where: 'id = ? AND client_id = ?',
          whereArgs: [localId, row['client_id']],
        );
      }
    }
  });
}

Future<void> _migrateNetworkSourceColumns(Database database) async {
  final statements = <String>[
    'ALTER TABLE agents ADD COLUMN network_id INTEGER',
    'ALTER TABLE agents ADD COLUMN network_uploader_id INTEGER',
    "ALTER TABLE agents ADD COLUMN network_source TEXT NOT NULL DEFAULT 'none'",
    'ALTER TABLE agents ADD COLUMN network_version INTEGER',
    'ALTER TABLE group_chats ADD COLUMN opening_line TEXT',
    'ALTER TABLE group_chats ADD COLUMN opening_speaker_agent_id TEXT',
    'ALTER TABLE group_chats ADD COLUMN network_id INTEGER',
    'ALTER TABLE group_chats ADD COLUMN network_uploader_id INTEGER',
    "ALTER TABLE group_chats ADD COLUMN network_source TEXT NOT NULL DEFAULT 'none'",
    'ALTER TABLE group_chats ADD COLUMN network_version INTEGER',
  ];
  for (final statement in statements) {
    try {
      await database.execute(statement);
    } catch (_) {
      // 已存在的列无需重复迁移。
    }
  }
}

// ─── 建表与版本迁移 ───

Future<void> _onCreate(Database db, int version) async {
  await db.execute(_createLocalDatabaseMigrationsSql);
  await db.execute(
    '''CREATE TABLE agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, gender TEXT DEFAULT '', description TEXT DEFAULT '', persona TEXT NOT NULL, opening_line TEXT, avatar_color INTEGER, avatar_path TEXT, avatar_data TEXT, chat_background TEXT, worldview TEXT DEFAULT '', is_active INTEGER DEFAULT 0, real_info_enabled INTEGER DEFAULT 0, proactive_care_enabled INTEGER DEFAULT 0, proactive_care_daily_limit INTEGER DEFAULT 1, proactive_care_min_interval_hours INTEGER DEFAULT 3, max_response_length INTEGER NOT NULL DEFAULT 300, network_id INTEGER, network_uploader_id INTEGER, network_source TEXT NOT NULL DEFAULT 'none', network_version INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE long_term_memories (id TEXT PRIMARY KEY, field TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE base_memories (id TEXT PRIMARY KEY, type TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE planned_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, scheduled_time INTEGER NOT NULL, message TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, agent_id TEXT, group_id TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, agent_id TEXT, group_id TEXT, memory_ai_processed INTEGER DEFAULT 0, image_path TEXT, image_paths TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT, agent_id TEXT, group_id TEXT, image_path TEXT, image_paths TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE stickers (id TEXT PRIMARY KEY, description TEXT NOT NULL, image_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER)''',
  );
  await db.execute(
    '''CREATE TABLE local_sticker_messages (chat_message_id INTEGER PRIMARY KEY, sticker_id TEXT, description_snapshot TEXT NOT NULL, image_path_snapshot TEXT NOT NULL, created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER, agent_id TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT, agent_id TEXT)''',
  );
  await db.execute(
    '''CREATE TABLE group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, avatar_icon TEXT, avatar_path TEXT, group_persona TEXT, opening_line TEXT, opening_speaker_agent_id TEXT, speech_mode TEXT DEFAULT 'free', simulator_mode INTEGER DEFAULT 0, world_setting TEXT, linked_memory INTEGER DEFAULT 0, network_id INTEGER, network_uploader_id INTEGER, network_source TEXT NOT NULL DEFAULT 'none', network_version INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE agent_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE agent_folder_members (folder_id TEXT NOT NULL, agent_id TEXT NOT NULL, PRIMARY KEY (folder_id, agent_id))''',
  );
  await db.execute(
    '''CREATE TABLE group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE, FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE)''',
  );
  await db.execute(
    '''CREATE TABLE group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''',
  );
  await db.execute(
    '''CREATE TABLE group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER, memory_ai_processed INTEGER DEFAULT 0, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''',
  );
  await db.execute(
    '''CREATE TABLE group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''',
  );
  await db.execute(
    '''CREATE TABLE token_cost (id INTEGER PRIMARY KEY AUTOINCREMENT, model TEXT NOT NULL, price REAL NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT 'per_1000', agent_id TEXT, created_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE novel_generations (id INTEGER PRIMARY KEY AUTOINCREMENT, style TEXT NOT NULL, word_count INTEGER DEFAULT 500, prompt TEXT NOT NULL, result TEXT NOT NULL, timestamp INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS user_profiles (id TEXT PRIMARY KEY, category TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, confidence INTEGER DEFAULT 50, source TEXT DEFAULT 'ai_extracted', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  );
  await db.execute(
    '''CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_cat_key ON user_profiles(category, key)''',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS draft_uploads (id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT, data TEXT NOT NULL, cover_color INTEGER, updated_at INTEGER, created_at INTEGER)''',
  );
  await ProactiveCareStore.createTable(db);
  // v23: 多端同步相关
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS local_tombstones (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, client_id TEXT NOT NULL, agent_id TEXT, created_at INTEGER NOT NULL)''',
  );
  for (final table in [
    'agents',
    'chat_messages',
    'short_term_messages',
    'group_chats',
    'group_members',
    'group_messages',
    'group_short_term',
    'group_shared_memories',
    'long_term_memories',
    'base_memories',
    'planned_messages',
    'user_profiles',
    'providers',
  ]) {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN client_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN sync_updated_at INTEGER');
    } catch (_) {}
  }
}

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  debugPrint('[DB] onUpgrade: $oldVersion -> $newVersion');
  if (oldVersion < 2) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER)''',
    );
  }
  if (oldVersion < 3) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT)''',
    );
  }
  if (oldVersion < 4) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, gender TEXT DEFAULT '', description TEXT DEFAULT '', persona TEXT NOT NULL, avatar_color INTEGER, is_active INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    for (final table in [
      'long_term_memories',
      'base_memories',
      'short_term_messages',
      'chat_messages',
      'debug_logs',
      'token_usage',
      'planned_messages',
    ]) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN agent_id TEXT');
      } catch (_) {}
    }
  }
  if (oldVersion < 5) {
    try {
      await db.execute("ALTER TABLE agents ADD COLUMN avatar_path TEXT");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE agents ADD COLUMN chat_background TEXT");
    } catch (_) {}
  }
  if (oldVersion < 6) {
    try {
      await db.execute("ALTER TABLE chat_messages ADD COLUMN image_path TEXT");
    } catch (_) {}
  }
  if (oldVersion < 7) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, group_persona TEXT, speech_mode TEXT DEFAULT 'free', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER)''',
    );
    for (final table in [
      'long_term_memories',
      'base_memories',
      'short_term_messages',
      'chat_messages',
      'planned_messages',
    ]) {
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN group_id TEXT");
      } catch (_) {}
    }
  }
  if (oldVersion < 8) {
    debugPrint('[DB] v8 migration: ensuring group tables exist');
    await _ensureGroupTablesExist(db);
  }
  if (oldVersion < 9) {
    try {
      await db.execute("ALTER TABLE agents ADD COLUMN opening_line TEXT");
    } catch (_) {}
    debugPrint('[DB] v9 migration: added opening_line column');
  }
  if (oldVersion < 10) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS token_cost (id INTEGER PRIMARY KEY AUTOINCREMENT, model TEXT NOT NULL, price REAL NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT 'per_1000', agent_id TEXT, created_at INTEGER NOT NULL)''',
    );
    debugPrint('[DB] v10 migration: added token_cost table');
  }
  if (oldVersion < 11) {
    try {
      await db.execute(
        "ALTER TABLE debug_logs ADD COLUMN prompt_tokens INTEGER",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE debug_logs ADD COLUMN completion_tokens INTEGER",
      );
    } catch (_) {}
    debugPrint('[DB] v11 migration: added token columns to debug_logs');
  }
  if (oldVersion < 12) {
    for (final table in [
      'long_term_memories',
      'base_memories',
      'short_term_messages',
      'chat_messages',
      'debug_logs',
      'planned_messages',
      'token_usage',
    ]) {
      try {
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_${table}_agent ON $table(agent_id)",
        );
      } catch (_) {}
    }
    try {
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_long_term_memories_group ON long_term_memories(agent_id, group_id)",
      );
    } catch (_) {}
    try {
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_base_memories_group ON base_memories(agent_id, group_id)",
      );
    } catch (_) {}
    debugPrint('[DB] v12 migration: added agent_id indices');
  }
  if (oldVersion < 14) {
    for (final table in ['long_term_memories', 'base_memories']) {
      try {
        await db.delete(
          table,
          where: 'agent_id IS NULL OR agent_id = ?',
          whereArgs: [''],
        );
      } catch (_) {}
    }
    debugPrint(
      '[DB] v14 migration: cleaned up records with null/empty agent_id in long_term_memories and base_memories',
    );
  }
  if (oldVersion < 15) {
    try {
      await db.execute(
        "ALTER TABLE group_chats ADD COLUMN simulator_mode INTEGER DEFAULT 0",
      );
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE group_chats ADD COLUMN world_setting TEXT");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE agents ADD COLUMN source_group_id TEXT");
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE agents ADD COLUMN is_sim_character INTEGER DEFAULT 0",
      );
    } catch (_) {}
    debugPrint('[DB] v15 migration: added simulator mode columns');
  }
  if (oldVersion < 16) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS novel_generations (id INTEGER PRIMARY KEY AUTOINCREMENT, style TEXT NOT NULL, word_count INTEGER DEFAULT 500, prompt TEXT NOT NULL, result TEXT NOT NULL, timestamp INTEGER NOT NULL)''',
    );
    debugPrint('[DB] v16 migration: added novel_generations table');
  }
  if (oldVersion < 17) {
    try {
      await db.execute(
        "ALTER TABLE debug_logs ADD COLUMN prompt_tokens INTEGER",
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE debug_logs ADD COLUMN completion_tokens INTEGER",
      );
    } catch (_) {}
    debugPrint('[DB] v17 migration: ensured debug_logs token columns');
  }
  if (oldVersion < 18) {
    try {
      await db.execute(
        "ALTER TABLE agents ADD COLUMN worldview TEXT DEFAULT ''",
      );
    } catch (_) {}
    debugPrint('[DB] v18 migration: added worldview column');
  }
  if (oldVersion < 19) {
    try {
      await db.execute(
        "ALTER TABLE agents ADD COLUMN is_group_only INTEGER DEFAULT 0",
      );
    } catch (_) {}
    debugPrint('[DB] v19 migration: added is_group_only column');
  }
  if (oldVersion < 20) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS user_profiles (id TEXT PRIMARY KEY, category TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, confidence INTEGER DEFAULT 50, source TEXT DEFAULT 'ai_extracted', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    try {
      await db.execute(
        '''CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_cat_key ON user_profiles(category, key)''',
      );
    } catch (_) {}
    debugPrint('[DB] v20 migration: added user_profiles table');
  }
  if (oldVersion < 21) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS draft_uploads (id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT, data TEXT NOT NULL, cover_color INTEGER, updated_at INTEGER, created_at INTEGER)''',
    );
    debugPrint('[DB] v21 migration: added draft_uploads table');
  }
  if (oldVersion < 22) {
    try {
      await db.execute(
        'ALTER TABLE agents ADD COLUMN real_info_enabled INTEGER DEFAULT 0',
      );
    } catch (_) {}
    debugPrint('[DB] v22 migration: added agents.real_info_enabled');
  }
  if (oldVersion < 23) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS local_tombstones (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, client_id TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final table in [
      'agents',
      'chat_messages',
      'short_term_messages',
      'group_chats',
      'group_members',
      'group_messages',
      'group_short_term',
      'group_shared_memories',
      'long_term_memories',
      'base_memories',
      'planned_messages',
      'user_profiles',
      'providers',
    ]) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN client_id TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN sync_updated_at INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'UPDATE $table SET client_id = CAST(id AS TEXT) WHERE client_id IS NULL',
        );
      } catch (_) {}
      try {
        await db.execute(
          'UPDATE $table SET sync_updated_at = ? WHERE sync_updated_at IS NULL',
          [now],
        );
      } catch (_) {}
    }
    debugPrint(
      '[DB] v23 migration: added client_id + sync_updated_at to 13 sync tables, created local_tombstones',
    );
  }
  if (oldVersion < 24) {
    try {
      await db.execute("ALTER TABLE group_chats ADD COLUMN avatar_icon TEXT");
    } catch (_) {}
    debugPrint('[DB] v24 migration: added group_chats.avatar_icon');
  }
  if (oldVersion < 25) {
    try {
      await db.execute("ALTER TABLE group_chats ADD COLUMN avatar_path TEXT");
    } catch (_) {}
    debugPrint('[DB] v25 migration: added group_chats.avatar_path');
  }
  if (oldVersion < 26) {
    try {
      await db.execute('ALTER TABLE local_tombstones ADD COLUMN agent_id TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE short_term_messages ADD COLUMN memory_ai_processed INTEGER DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE group_short_term ADD COLUMN memory_ai_processed INTEGER DEFAULT 0',
      );
    } catch (_) {}
    debugPrint(
      '[DB] v26 migration: added local_tombstones.agent_id, memory_ai_processed',
    );
  }
  if (oldVersion < 27) {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS stickers (id TEXT PRIMARY KEY, description TEXT NOT NULL, image_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS local_sticker_messages (chat_message_id INTEGER PRIMARY KEY, sticker_id TEXT, description_snapshot TEXT NOT NULL, image_path_snapshot TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    );
    debugPrint('[DB] v27 migration: added local sticker tables');
  }
  if (oldVersion < 28) {
    // avatar_data：智能体头像 base64，随多端同步携带，对端落盘还原
    try {
      await db.execute("ALTER TABLE agents ADD COLUMN avatar_data TEXT");
    } catch (_) {}
    debugPrint('[DB] v28 migration: added agents.avatar_data');
  }
  if (oldVersion < 29) {
    // AI 主动关心：开关 + 每日上限 + 最小间隔
    try {
      await db.execute(
        'ALTER TABLE agents ADD COLUMN proactive_care_enabled INTEGER DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE agents ADD COLUMN proactive_care_daily_limit INTEGER DEFAULT 1',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE agents ADD COLUMN proactive_care_min_interval_hours INTEGER DEFAULT 3',
      );
    } catch (_) {}
    debugPrint('[DB] v29 migration: added agents proactive_care_* columns');
  }
  if (oldVersion < 30) {
    // 智能体编组 + 群聊记忆共用
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS agent_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS agent_folder_members (folder_id TEXT NOT NULL, agent_id TEXT NOT NULL, PRIMARY KEY (folder_id, agent_id))''',
    );
    try {
      await db.execute(
        'ALTER TABLE group_chats ADD COLUMN linked_memory INTEGER DEFAULT 0',
      );
    } catch (_) {}
    debugPrint(
      '[DB] v30 migration: added agent_folders tables, group_chats.linked_memory',
    );
  }
  if (oldVersion < 31) {
    // 短期记忆携带真实图片：image_path 存本地图片路径，
    // 原生视觉模型构建上下文/记忆 AI 时按路径现读挂图
    try {
      await db.execute(
        'ALTER TABLE short_term_messages ADD COLUMN image_path TEXT',
      );
    } catch (_) {}
    debugPrint('[DB] v31 migration: added short_term_messages.image_path');
  }
  if (oldVersion < 32) {
    // 多图消息：image_paths 存 JSON 数组字符串（一条消息多张图），
    // image_path 列保留并写入首图兼容旧版读取
    try {
      await db.execute('ALTER TABLE chat_messages ADD COLUMN image_paths TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE short_term_messages ADD COLUMN image_paths TEXT',
      );
    } catch (_) {}
    debugPrint('[DB] v32 migration: added image_paths columns');
  }
  if (oldVersion < 33) {
    await _migrateNetworkSourceColumns(db);
    debugPrint('[DB] v33 migration: added network provenance columns');
  }
  if (oldVersion < 34) {
    await ProactiveCareStore.createTable(db);
    debugPrint('[DB] v34 migration: added proactive_care_state table');
  }
  if (oldVersion < 35) {
    try {
      await db.execute(
        'ALTER TABLE group_chats ADD COLUMN opening_speaker_agent_id TEXT',
      );
    } catch (_) {}
    debugPrint('[DB] v35 migration: added group opening speaker');
  }
  if (oldVersion < 36) {
    await _migrateMemoryIdsToUuid(db);
    debugPrint('[DB] v36 migration: memory ids rewritten to prefixed UUIDs');
  }
  if (oldVersion < 37) {
    try {
      await db.execute(
        'ALTER TABLE agents ADD COLUMN max_response_length INTEGER NOT NULL DEFAULT 300',
      );
    } catch (_) {}
    debugPrint('[DB] v37 migration: added agents.max_response_length');
  }
  if (oldVersion < 38) {
    await db.execute(_createLocalDatabaseMigrationsSql);
    debugPrint('[DB] v38 migration: added local database migration state');
  }
}

/// v36：重写三张记忆表的局部取号 id 为全局唯一 UUID。
///
/// 背景：long_term_memories / base_memories / group_shared_memories 的
/// id TEXT PRIMARY KEY 全局唯一，但旧版按 agent/group 局部取号
/// （L001/B001/GS001），配合 ConflictAlgorithm.replace 会跨智能体整行
/// 静默覆盖。迁移把旧 id 重写为「前缀-uuid4」（L-/B-/GS- 前缀保留，
/// 供 forget 等工具按前缀路由），并：
///   - client_id 为空或等于旧 id 的，一并更新为新 id（保持 id == client_id）
///   - local_tombstones 中引用旧 id 的墓碑同步重写
/// 幂等：已是新格式（含「前缀-」）的行跳过，重复执行不再改写。
Future<void> _migrateMemoryIdsToUuid(Database db) async {
  const tablePrefixes = {
    'long_term_memories': 'L',
    'base_memories': 'B',
    'group_shared_memories': 'GS',
  };
  const uuid = Uuid();
  for (final entry in tablePrefixes.entries) {
    final table = entry.key;
    final prefix = entry.value;
    final rows = await db.query(table, columns: ['id', 'client_id']);
    for (final row in rows) {
      final oldId = row['id']?.toString() ?? '';
      if (oldId.isEmpty || oldId.startsWith('$prefix-')) continue;
      final newId = '$prefix-${uuid.v4()}';
      await db.update(
        table,
        {'id': newId},
        where: 'id = ?',
        whereArgs: [oldId],
      );
      final clientId = row['client_id']?.toString() ?? '';
      if (clientId.isEmpty || clientId == oldId) {
        await db.update(
          table,
          {'client_id': newId},
          where: 'id = ?',
          whereArgs: [newId],
        );
      }
      try {
        await db.update(
          'local_tombstones',
          {'client_id': newId},
          where: 'table_name = ? AND client_id = ?',
          whereArgs: [table, oldId],
        );
      } catch (_) {
        // local_tombstones 缺失时不阻断迁移
      }
    }
  }
}

// ─── 群聊表健壮性补齐 ───

/// Ensure all group-related tables exist, regardless of migration state.
Future<void> _ensureGroupTablesExist(Database db) async {
  // 始终尝试添加 agents 表可能缺失的列（旧版本迁移可能不完整）
  try {
    await db.execute("ALTER TABLE agents ADD COLUMN opening_line TEXT");
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE agents ADD COLUMN source_group_id TEXT");
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE agents ADD COLUMN is_sim_character INTEGER DEFAULT 0",
    );
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE agents ADD COLUMN is_group_only INTEGER DEFAULT 0",
    );
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE agents ADD COLUMN worldview TEXT DEFAULT ''");
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE agents ADD COLUMN max_response_length INTEGER NOT NULL DEFAULT 300",
    );
  } catch (_) {}
  await _migrateNetworkSourceColumns(db);

  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='group_chats'",
  );
  if (tables.isEmpty) {
    debugPrint('[DB] _ensureGroupTablesExist: initializing...');
    try {
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, group_persona TEXT, speech_mode TEXT DEFAULT 'free', simulator_mode INTEGER DEFAULT 0, world_setting TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
      );
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER)''',
      );
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT)''',
      );
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER)''',
      );
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER)''',
      );
      for (final table in [
        'long_term_memories',
        'base_memories',
        'short_term_messages',
        'chat_messages',
        'planned_messages',
      ]) {
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN group_id TEXT");
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[DB] _ensureGroupTablesExist create error: $e');
    }
  } else {
    debugPrint('[DB] group tables already exist, attempting column patch');
  }

  // 无论表是否新建，都尝试补齐可能缺失的列（已存在则 try/catch 吞掉）
  // 修复：旧版本迁移可能未跑全（v15 ALTER 失败被吞），导致 simulator_mode/world_setting 缺失
  try {
    await db.execute(
      "ALTER TABLE group_chats ADD COLUMN simulator_mode INTEGER DEFAULT 0",
    );
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE group_chats ADD COLUMN world_setting TEXT");
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE group_chats ADD COLUMN avatar_icon TEXT");
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE group_chats ADD COLUMN avatar_path TEXT");
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE group_chats ADD COLUMN opening_speaker_agent_id TEXT",
    );
  } catch (_) {}
  try {
    await db.execute(
      "UPDATE group_short_term SET role = 'assistant' WHERE role = 'agent'",
    );
  } catch (_) {}
  try {
    await db.execute("ALTER TABLE debug_logs ADD COLUMN prompt_tokens INTEGER");
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE debug_logs ADD COLUMN completion_tokens INTEGER",
    );
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE short_term_messages ADD COLUMN memory_ai_processed INTEGER DEFAULT 0",
    );
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE group_short_term ADD COLUMN memory_ai_processed INTEGER DEFAULT 0",
    );
  } catch (_) {}
  // v31: 短期记忆携带真实图片路径
  try {
    await db.execute(
      "ALTER TABLE short_term_messages ADD COLUMN image_path TEXT",
    );
  } catch (_) {}
  // v32: 多图消息 image_paths（JSON 数组字符串）
  try {
    await db.execute("ALTER TABLE chat_messages ADD COLUMN image_paths TEXT");
  } catch (_) {}
  try {
    await db.execute(
      "ALTER TABLE short_term_messages ADD COLUMN image_paths TEXT",
    );
  } catch (_) {}
  // v30: 群聊记忆共用标记 + 智能体编组表
  try {
    await db.execute(
      "ALTER TABLE group_chats ADD COLUMN linked_memory INTEGER DEFAULT 0",
    );
  } catch (_) {}
  try {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS agent_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS agent_folder_members (folder_id TEXT NOT NULL, agent_id TEXT NOT NULL, PRIMARY KEY (folder_id, agent_id))''',
    );
  } catch (_) {}
}
