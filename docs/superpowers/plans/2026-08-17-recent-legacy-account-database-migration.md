# Recent Legacy Account Database Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将近期版本共享 `aichat.db` 安全、幂等地合并到首次认领账号的独立数据库，验证后清理旧库。

**Architecture:** 数据库 schema 升至 v38，并在账号库内以 `local_database_migrations` 记录“已提交/已清理”状态。原生端先 checkpoint 并复制旧库为暂存库，暂存库升级后通过单个目标事务按依赖顺序合并；整数主键重新生成并维护引用映射，提交后再删除旧文件。

**Tech Stack:** Flutter/Dart 3.11、sqflite、sqflite_common_ffi、SharedPreferences、crypto SHA-256、flutter_test。

## Global Constraints

- 只接受源库 `PRAGMA user_version` 35、36、37；目标 schema 版本固定为 38。
- 旧库仅由首次成功登录的账号数据库名认领，失败后其他账号不得读取。
- 所有业务数据与 `committed` 状态必须在目标库同一事务提交。
- 校验或合并失败时保留原始 `aichat.db`；仅完整成功后删除主文件、`-wal`、`-shm` 和暂存文件。
- 不迁移 `debug_logs`、`local_tombstones` 或运行时缓存。
- 数据库测试统一用 `flutter test --concurrency=1`，避免全局 `databaseFactory` 相互污染。
- 当前工作区存在重叠的未提交改动；执行阶段不创建包含整文件的自动提交，只保留可审查 diff。

---

### Task 1: v38 Schema And Migration State

**Files:**
- Modify: `lib/services/database_schema.dart`
- Test: `test/account_database_migration_test.dart`

**Interfaces:**
- Produces: `local_database_migrations(source_fingerprint, owner_database_name, state, committed_at, cleaned_at, error)`。
- Produces: `_currentDatabaseVersion == 38`，由普通账号库和暂存库共同使用。

- [ ] **Step 1: Write the failing schema test**

```dart
test('v38 账号库包含本地迁移状态表', () async {
  await DatabaseService.switchAccount(101);
  final db = await DatabaseService.database;
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='local_database_migrations'",
  );
  expect(tables, hasLength(1));
  expect(await db.getVersion(), 38);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart --plain-name "v38 账号库包含本地迁移状态表"`

Expected: FAIL because the current database version is 37 and the table is absent.

- [ ] **Step 3: Add the v38 schema**

```dart
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
```

Use the constant in `openDatabase(version:)`, execute the DDL in `_onCreate`, and execute it when `oldVersion < 38` in `_onUpgrade`.

- [ ] **Step 4: Run the focused test**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart --plain-name "v38 账号库包含本地迁移状态表"`

Expected: PASS.

### Task 2: Claim, Stage, And Recent-Version Upgrade

**Files:**
- Modify: `lib/services/account_database_migration.dart`
- Modify: `lib/services/database_service.dart`
- Test: `test/account_database_migration_test.dart`

**Interfaces:**
- Consumes: `_currentDatabaseVersion`, `_onUpgrade`, `_ensureGroupTablesExist`。
- Produces: `AccountDatabaseMigration.claimLegacyIfNeeded({required int? userId, required String targetDatabaseName})`，即使目标库已存在也会尝试安全合并。
- Produces: 仅允许 35、36、37 的 `_prepareStagingDatabase`。

- [ ] **Step 1: Add failing tests for target-exists migration and unsupported versions**

```dart
test('目标账号库已存在时仍迁移 v37 旧库', () async {
  await seedExistingTargetAccount(101);
  await seedLegacyDatabase(version: 37);
  await DatabaseService.switchAccount(101);
  expect(await findAgent('legacy-agent'), isNotNull);
  expect(await findAgent('target-agent'), isNotNull);
});

test('低于 v35 的旧库不迁移也不删除', () async {
  final legacy = await seedLegacyDatabase(version: 34);
  await expectLater(DatabaseService.switchAccount(101), throwsA(isA<StateError>()));
  expect(await File(legacy).exists(), isTrue);
});
```

- [ ] **Step 2: Run both tests and confirm RED**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart --plain-name "目标账号库已存在时仍迁移 v37 旧库"`

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart --plain-name "低于 v35 的旧库不迁移也不删除"`

Expected: first test misses legacy data; second test does not reject the unsupported version correctly.

- [ ] **Step 3: Implement claim and staging state machine**

```dart
if (owner != null && owner != targetDatabaseName) return;
final sourceVersion = await source.getVersion();
if (sourceVersion < 35 || sourceVersion > 37) {
  throw StateError('不支持的旧数据库版本: $sourceVersion');
}
await source.rawQuery('PRAGMA wal_checkpoint(FULL)');
await File(legacyPath).copy(stagingPath);
```

Open the staging copy at v38 with `_onUpgrade`, call `_ensureGroupTablesExist`, require `PRAGMA integrity_check == ok`, and verify the eight required core tables before merging. Remove the old `target database exists => return` branch.

- [ ] **Step 4: Run focused tests**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart`

Expected: the new staging tests pass; later merge tests may still be RED.

### Task 3: Atomic Merge And Conflict Rules

**Files:**
- Modify: `lib/services/account_database_migration.dart`
- Test: `test/account_database_migration_test.dart`

**Interfaces:**
- Produces: `_mergeStagingIntoTarget(Database source, Database target, String fingerprint, String owner)`。
- Produces: deterministic fallback `client_id = migration:<fingerprint>:<table>:<source-id>` for integer-key rows supporting `client_id`。
- Produces: `Map<int, int> chatMessageIds` used by sticker snapshots.

- [ ] **Step 1: Add failing merge tests**

```dart
test('迁移覆盖智能体聊天三层记忆群聊画像和编组', () async {
  await seedCompleteV37LegacyGraph();
  await DatabaseService.switchAccount(101);
  await expectCompleteGraphInAccountDatabase();
});

test('账号库较新的智能体和画像不被旧数据覆盖', () async {
  await seedNewerTargetRows(101);
  await seedOlderLegacyRows();
  await DatabaseService.switchAccount(101);
  expect((await findAgent('same-agent'))!['persona'], 'new persona');
  expect((await findProfile('identity', 'name'))!['value'], 'new value');
});
```

- [ ] **Step 2: Run and confirm RED**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart --plain-name "迁移覆盖智能体聊天三层记忆群聊画像和编组"`

Expected: FAIL because merge routines do not exist.

- [ ] **Step 3: Implement dependency-ordered merge in one transaction**

```dart
await target.transaction((txn) async {
  await mergeTextKeyTable(txn, 'agents');
  await mergeTextKeyTable(txn, 'group_chats');
  await mergeTextKeyTable(txn, 'long_term_memories');
  await mergeTextKeyTable(txn, 'base_memories');
  await mergeTextKeyTable(txn, 'group_shared_memories');
  await mergeTextKeyTable(txn, 'short_term_messages');
  chatMessageIds.addAll(await mergeIntegerTable(txn, 'chat_messages'));
  await mergeProfilesByCategoryAndKey(txn);
  await mergeStickerSnapshots(txn, chatMessageIds);
  await validateMergedGraph(txn);
  await txn.insert('local_database_migrations', committedRow);
});
```

Load source rows before opening the target transaction. Filter every insert/update to columns shared by source and target. For text/composite keys, insert missing rows and only update existing rows when source `max(updated_at, sync_updated_at)` is strictly newer. For `user_profiles`, resolve identity by `category + key`; for integer IDs insert without the old `id` and store old-to-new maps.

- [ ] **Step 4: Run merge tests**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart`

Expected: complete graph and conflict tests pass.

### Task 4: Validation, Idempotency, Ownership, And Cleanup

**Files:**
- Modify: `lib/services/account_database_migration.dart`
- Test: `test/account_database_migration_test.dart`

**Interfaces:**
- Consumes: committed migration row and source fingerprint.
- Produces: cleanup-only resume when state is `committed`; state becomes `cleaned` after file deletion.

- [ ] **Step 1: Add failing safety tests**

```dart
test('表情快照引用重映射后的聊天 ID', () async {
  final legacyPath = await seedLegacyDatabase(version: 37);
  await seedLegacyChatWithSticker(legacyPath, chatId: 900);
  await DatabaseService.switchAccount(101);
  final db = await DatabaseService.database;
  final snapshot = (await db.query('local_sticker_messages')).single;
  final chat = await db.query(
    'chat_messages',
    where: 'id = ?',
    whereArgs: [snapshot['chat_message_id']],
  );
  expect(chat.single['content'], 'legacy sticker message');
  expect(snapshot['chat_message_id'], isNot(900));
});

test('引用校验失败会回滚且保留旧库', () async {
  final legacyPath = await seedLegacyDatabase(version: 37);
  await seedLegacyChat(legacyPath, agentId: 'missing-agent');
  await expectLater(DatabaseService.switchAccount(101), throwsStateError);
  expect(await File(legacyPath).exists(), isTrue);
  final target = await openAccountDatabaseDirectly(101);
  expect(await target.query('agents', where: 'id = ?', whereArgs: ['legacy-agent']), isEmpty);
  expect(await target.query('local_database_migrations'), isEmpty);
  await target.close();
});

test('提交标记存在时只重试清理而不重复导入', () async {
  final legacyPath = await seedLegacyDatabase(version: 37);
  final fingerprint = sha256.convert(await File(legacyPath).readAsBytes()).toString();
  final target = await openAccountDatabaseDirectly(101);
  await target.insert('local_database_migrations', {
    'source_fingerprint': fingerprint,
    'owner_database_name': AccountDatabaseScope.databaseNameFor(101),
    'state': 'committed',
    'committed_at': 1,
  });
  await target.close();
  await DatabaseService.switchAccount(101);
  expect(await File(legacyPath).exists(), isFalse);
  expect(await DatabaseService.getChatMessageCount('legacy-agent'), 0);
});

test('第二个账号不能认领第一个账号已经认领的旧库', () async {
  final legacyPath = await seedLegacyDatabase(version: 34);
  await expectLater(DatabaseService.switchAccount(101), throwsStateError);
  await DatabaseService.closeForTesting();
  await DatabaseService.switchAccount(202);
  expect(await File(legacyPath).exists(), isTrue);
  expect(await findAgent('legacy-agent'), isNull);
});

test('成功后删除旧库 WAL SHM 和暂存文件', () async {
  final legacyPath = await seedLegacyDatabase(version: 37);
  await File('$legacyPath-wal').writeAsBytes(const [1]);
  await File('$legacyPath-shm').writeAsBytes(const [1]);
  await DatabaseService.switchAccount(101);
  expect(await File(legacyPath).exists(), isFalse);
  expect(await File('$legacyPath-wal').exists(), isFalse);
  expect(await File('$legacyPath-shm').exists(), isFalse);
  expect(
    Directory(directory.path).listSync().where((e) => e.path.contains('.migration-')),
    isEmpty,
  );
});
```

- [ ] **Step 2: Run safety tests and confirm RED**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart`

Expected: at least the rollback, cleanup resume, or ownership test fails before implementation.

- [ ] **Step 3: Implement validation and cleanup**

```dart
final integrity = await txn.rawQuery('PRAGMA integrity_check');
if (integrity.single.values.single.toString().toLowerCase() != 'ok') {
  throw StateError('目标数据库完整性检查失败');
}
for (final suffix in ['', '-wal', '-shm']) {
  final file = File('$legacyPath$suffix');
  if (await file.exists()) await file.delete();
}
```

Before commit, verify every source agent resolves, every source chat has an ID mapping, every profile resolves to a row no older than source, every non-null agent/group reference exists, and every sticker snapshot points at a migrated chat. If a committed row already exists, skip all inserts and retry cleanup only.

- [ ] **Step 4: Run migration regression tests**

Run: `flutter test --concurrency=1 test/account_database_migration_test.dart test/account_database_switch_test.dart test/database_memory_uuid_migration_test.dart`

Expected: PASS with zero failures.

### Task 5: Static Analysis And Full Regression

**Files:**
- Verify: `lib/services/account_database_migration.dart`
- Verify: `lib/services/database_schema.dart`
- Verify: `lib/services/database_service.dart`
- Verify: `test/account_database_migration_test.dart`

**Interfaces:**
- Consumes: all earlier tasks.
- Produces: verified migration implementation and reviewable diff.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/services/account_database_migration.dart lib/services/database_schema.dart lib/services/database_service.dart test/account_database_migration_test.dart`

Expected: formatter exits 0.

- [ ] **Step 2: Run focused analysis**

Run: `flutter analyze lib/services/account_database_migration.dart lib/services/database_schema.dart lib/services/database_service.dart test/account_database_migration_test.dart`

Expected: 0 errors.

- [ ] **Step 3: Run full Flutter tests serially**

Run: `flutter test --concurrency=1`

Expected: all tests pass.

- [ ] **Step 4: Inspect only migration-related diff**

Run: `git diff -- docs/superpowers/plans/2026-08-17-recent-legacy-account-database-migration.md lib/services/account_database_migration.dart lib/services/database_schema.dart lib/services/database_service.dart test/account_database_migration_test.dart`

Expected: no unrelated Go/server or UI changes.
