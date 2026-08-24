import 'package:aichat/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v36 迁移测试：旧版局部取号 id（L001/B001/b3/GS001）升级为带前缀 UUID，
/// 数据不丢、client_id 对齐、墓碑引用重写，且迁移幂等。
void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await database.execute(
      'CREATE TABLE long_term_memories ('
      'id TEXT PRIMARY KEY, field TEXT NOT NULL, content TEXT NOT NULL, '
      'agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, '
      'created_at INTEGER NOT NULL, client_id TEXT)',
    );
    await database.execute(
      'CREATE TABLE base_memories ('
      'id TEXT PRIMARY KEY, type TEXT NOT NULL, content TEXT NOT NULL, '
      'agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, '
      'created_at INTEGER NOT NULL, client_id TEXT)',
    );
    await database.execute(
      'CREATE TABLE group_shared_memories ('
      'id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, '
      'content TEXT NOT NULL, updated_at INTEGER, client_id TEXT)',
    );
    await database.execute(
      'CREATE TABLE local_tombstones ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, '
      'client_id TEXT NOT NULL, agent_id TEXT, created_at INTEGER NOT NULL)',
    );
  });

  tearDown(() => database.close());

  Future<void> seedLegacyRows() async {
    // 旧格式：L/B/GS + 局部序号；client_id 或为空、或等于 id（v23 迁移产物）
    await database.insert('long_term_memories', {
      'id': 'L001',
      'field': 'status',
      'content': 'agent-a 的长期记忆',
      'agent_id': 'agent-a',
      'updated_at': 1,
      'created_at': 1,
      'client_id': 'L001',
    });
    await database.insert('long_term_memories', {
      'id': 'L002',
      'field': 'goals',
      'content': 'agent-b 的长期记忆',
      'agent_id': 'agent-b',
      'updated_at': 2,
      'created_at': 2,
      'client_id': null,
    });
    await database.insert('base_memories', {
      'id': 'B001',
      'type': 'setting',
      'content': '世界观设定',
      'agent_id': 'agent-a',
      'updated_at': 1,
      'created_at': 1,
      'client_id': 'B001',
    });
    // 反馈服务旧格式：小写 b + 数字
    await database.insert('base_memories', {
      'id': 'b3',
      'type': 'event',
      'content': '点赞反馈',
      'agent_id': 'agent-a',
      'updated_at': 2,
      'created_at': 2,
      'client_id': '',
    });
    await database.insert('group_shared_memories', {
      'id': 'GS001',
      'group_id': 'group-1',
      'field': 'status',
      'content': '群共享记忆',
      'updated_at': 1,
      'client_id': 'GS001',
    });
    await database.insert('local_tombstones', {
      'table_name': 'long_term_memories',
      'client_id': 'L001',
      'agent_id': 'agent-a',
      'created_at': 1,
    });
    await database.insert('local_tombstones', {
      'table_name': 'base_memories',
      'client_id': 'B001',
      'agent_id': 'agent-a',
      'created_at': 1,
    });
  }

  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  test('旧取号 id 迁移为带前缀 UUID 且数据不丢', () async {
    await seedLegacyRows();

    await DatabaseService.migrateMemoryIdsToUuid(database);

    final longTerm = await database.query(
      'long_term_memories',
      orderBy: 'created_at',
    );
    expect(longTerm, hasLength(2));
    expect(longTerm[0]['content'], 'agent-a 的长期记忆');
    expect(longTerm[0]['agent_id'], 'agent-a');
    expect(longTerm[1]['content'], 'agent-b 的长期记忆');
    for (final row in longTerm) {
      final id = row['id'] as String;
      expect(id, startsWith('L-'));
      expect(uuidPattern.hasMatch(id.substring(2)), isTrue);
      // client_id 为空或等于旧 id → 一并更新为新 id
      expect(row['client_id'], id);
    }
    expect(longTerm[0]['id'] != longTerm[1]['id'], isTrue);

    final base = await database.query('base_memories', orderBy: 'created_at');
    expect(base, hasLength(2));
    expect(base[0]['content'], '世界观设定');
    expect(base[1]['content'], '点赞反馈');
    for (final row in base) {
      final id = row['id'] as String;
      expect(id, startsWith('B-'));
      expect(uuidPattern.hasMatch(id.substring(2)), isTrue);
      expect(row['client_id'], id);
    }

    final shared = await database.query('group_shared_memories');
    expect(shared, hasLength(1));
    expect(shared.single['content'], '群共享记忆');
    expect(shared.single['id'], startsWith('GS-'));
    expect(shared.single['client_id'], shared.single['id']);

    // 墓碑引用重写为新 id
    final tombstones = await database.query('local_tombstones');
    expect(tombstones, hasLength(2));
    expect(
      tombstones.firstWhere(
        (t) => t['table_name'] == 'long_term_memories',
      )['client_id'],
      longTerm[0]['id'],
    );
    expect(
      tombstones.firstWhere((t) => t['table_name'] == 'base_memories',
      )['client_id'],
      base[0]['id'],
    );
  });

  test('迁移幂等：重复执行不改写已是新格式的行', () async {
    await seedLegacyRows();
    await DatabaseService.migrateMemoryIdsToUuid(database);

    final before = await database.query('long_term_memories');
    final beforeBase = await database.query('base_memories');
    final beforeShared = await database.query('group_shared_memories');
    final beforeTombstones = await database.query('local_tombstones');

    // 第二次执行（模拟重复迁移 / 混有新格式行的库）
    await DatabaseService.migrateMemoryIdsToUuid(database);

    expect(await database.query('long_term_memories'), before);
    expect(await database.query('base_memories'), beforeBase);
    expect(await database.query('group_shared_memories'), beforeShared);
    expect(await database.query('local_tombstones'), beforeTombstones);
  });

  test('client_id 与旧 id 不同的行保留原 client_id', () async {
    await database.insert('long_term_memories', {
      'id': 'L007',
      'field': 'status',
      'content': '已同步过的记忆',
      'agent_id': 'agent-a',
      'updated_at': 1,
      'created_at': 1,
      'client_id': 'server-assigned-id',
    });

    await DatabaseService.migrateMemoryIdsToUuid(database);

    final row = (await database.query('long_term_memories')).single;
    expect(row['id'], startsWith('L-'));
    expect(row['client_id'], 'server-assigned-id');
  });
}
