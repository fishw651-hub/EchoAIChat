import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ProactiveCareClaim {
  const ProactiveCareClaim({
    required this.agentId,
    required this.token,
    required this.baselineChatId,
  });

  final String agentId;
  final String token;
  final int? baselineChatId;
}

class ProactiveCareStore {
  ProactiveCareStore(this._database);

  static const tableName = 'proactive_care_state';
  static const _uuid = Uuid();

  final Database _database;

  static Future<void> createTable(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        agent_id TEXT PRIMARY KEY,
        sent_date TEXT,
        sent_count INTEGER NOT NULL DEFAULT 0,
        pending_since INTEGER,
        claim_token TEXT,
        claim_expires_at INTEGER,
        baseline_chat_id INTEGER
      )
    ''');
  }

  Future<ProactiveCareClaim?> claim({
    required String agentId,
    required DateTime now,
    required int dailyLimit,
    required int minIntervalHours,
    Duration claimTtl = const Duration(minutes: 10),
  }) {
    return _database.transaction((transaction) async {
      await transaction.insert(
        tableName,
        {'agent_id': agentId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final stateRows = await transaction.query(
        tableName,
        where: 'agent_id = ?',
        whereArgs: [agentId],
        limit: 1,
      );
      final state = stateRows.isEmpty ? null : stateRows.first;
      final nowMs = now.millisecondsSinceEpoch;
      final activeClaim = state?['claim_token']?.toString() ?? '';
      final claimExpiresAt = (state?['claim_expires_at'] as num?)?.toInt();
      if (activeClaim.isNotEmpty &&
          claimExpiresAt != null &&
          claimExpiresAt > nowMs) {
        return null;
      }

      final today = _dateKey(now);
      final sentCount = state?['sent_date'] == today
          ? (state?['sent_count'] as num?)?.toInt() ?? 0
          : 0;
      if (sentCount >= dailyLimit) return null;

      var pendingSince = (state?['pending_since'] as num?)?.toInt();
      if (pendingSince != null) {
        final latestUserRows = await transaction.query(
          'chat_messages',
          columns: ['timestamp'],
          where: 'agent_id = ? AND role = ?',
          whereArgs: [agentId, 'user'],
          orderBy: 'timestamp DESC, id DESC',
          limit: 1,
        );
        final latestUserAt = latestUserRows.isEmpty
            ? null
            : (latestUserRows.first['timestamp'] as num?)?.toInt();
        if (latestUserAt == null || latestUserAt <= pendingSince) return null;
        pendingSince = null;
      }

      final latestRows = await transaction.query(
        'chat_messages',
        columns: ['id', 'timestamp'],
        where: 'agent_id = ?',
        whereArgs: [agentId],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      final latest = latestRows.isEmpty ? null : latestRows.first;
      final latestAt = (latest?['timestamp'] as num?)?.toInt();
      if (latestAt != null &&
          nowMs - latestAt < Duration(hours: minIntervalHours).inMilliseconds) {
        return null;
      }

      final baselineChatId = (latest?['id'] as num?)?.toInt();
      final token = _uuid.v4();
      final claimed = await transaction.update(
        tableName,
        {
          'sent_date': today,
          'sent_count': sentCount,
          'pending_since': pendingSince,
          'claim_token': token,
          'claim_expires_at': now.add(claimTtl).millisecondsSinceEpoch,
          'baseline_chat_id': baselineChatId,
        },
        where: '''agent_id = ? AND (
          claim_token IS NULL OR claim_token = '' OR
          claim_expires_at IS NULL OR claim_expires_at <= ?
        )''',
        whereArgs: [agentId, nowMs],
      );
      if (claimed != 1) return null;
      return ProactiveCareClaim(
        agentId: agentId,
        token: token,
        baselineChatId: baselineChatId,
      );
    });
  }

  Future<bool> commit(
    ProactiveCareClaim claim, {
    required String content,
    required DateTime sentAt,
  }) {
    return _database.transaction((transaction) async {
      final stateRows = await transaction.query(
        tableName,
        where: '''agent_id = ? AND claim_token = ? AND
          claim_expires_at IS NOT NULL AND claim_expires_at > ?''',
        whereArgs: [
          claim.agentId,
          claim.token,
          sentAt.millisecondsSinceEpoch,
        ],
        limit: 1,
      );
      if (stateRows.isEmpty) return false;

      final latestRows = await transaction.query(
        'chat_messages',
        columns: ['id'],
        where: 'agent_id = ?',
        whereArgs: [claim.agentId],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      final latestChatId = latestRows.isEmpty
          ? null
          : (latestRows.first['id'] as num?)?.toInt();
      if (latestChatId != claim.baselineChatId) {
        await _clearClaim(transaction, claim);
        return false;
      }

      final sentAtMs = sentAt.millisecondsSinceEpoch;
      final shortMemId = 'S-${_uuid.v4()}';

      final state = stateRows.first;
      final today = _dateKey(sentAt);
      final sentCount = state['sent_date'] == today
          ? (state['sent_count'] as num?)?.toInt() ?? 0
          : 0;
      final updated = await transaction.update(
        tableName,
        {
          'sent_date': today,
          'sent_count': sentCount + 1,
          'pending_since': sentAtMs,
          'claim_token': null,
          'claim_expires_at': null,
          'baseline_chat_id': null,
        },
        where: 'agent_id = ? AND claim_token = ?',
        whereArgs: [claim.agentId, claim.token],
      );
      if (updated != 1) return false;

      await transaction.insert('short_term_messages', {
        'id': shortMemId,
        'role': 'assistant',
        'content': content,
        'timestamp': sentAtMs,
        'agent_id': claim.agentId,
      });
      await transaction.insert('chat_messages', {
        'role': 'assistant',
        'content': content,
        'timestamp': sentAtMs,
        'short_mem_id': shortMemId,
        'agent_id': claim.agentId,
      });
      return true;
    });
  }

  Future<void> release(ProactiveCareClaim claim) {
    return _database.transaction(
      (transaction) => _clearClaim(transaction, claim),
    );
  }

  static Future<void> _clearClaim(
    DatabaseExecutor database,
    ProactiveCareClaim claim,
  ) async {
    await database.update(
      tableName,
      {'claim_token': null, 'claim_expires_at': null, 'baseline_chat_id': null},
      where: 'agent_id = ? AND claim_token = ?',
      whereArgs: [claim.agentId, claim.token],
    );
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
