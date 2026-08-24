import '../models/sync_policy.dart';

const allSyncTables = <String>[
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
];

const agentSyncClosureTables = <String>[
  'agents',
  'chat_messages',
  'short_term_messages',
  'long_term_memories',
  'base_memories',
  'planned_messages',
];

class SyncScope {
  SyncScope._({required this.mode, required Set<String> agentIds})
    : agentIds = Set.unmodifiable(agentIds);

  factory SyncScope.accountPolicy(SyncPolicy policy) {
    if (policy.scopeMode == SyncScopeMode.selected) {
      return SyncScope._(
        mode: SyncScopeMode.selected,
        agentIds: policy.selectedAgentIds,
      );
    }
    return SyncScope._(mode: SyncScopeMode.all, agentIds: const {});
  }

  factory SyncScope.oneShot(Set<String> agentIds) => SyncScope._(
    mode: SyncScopeMode.selected,
    agentIds: agentIds.where((id) => id.trim().isNotEmpty).toSet(),
  );

  factory SyncScope.all() => SyncScope._(
    mode: SyncScopeMode.all,
    agentIds: const {},
  );

  final SyncScopeMode mode;
  final Set<String> agentIds;

  List<String> get tables =>
      mode == SyncScopeMode.all ? allSyncTables : agentSyncClosureTables;

  bool allowsTable(String table) => tables.contains(table);

  bool allowsAgent(String agentId) =>
      mode == SyncScopeMode.all || agentIds.contains(agentId);

  List<Map<String, dynamic>> filterRows(
    String table,
    Iterable<Map<String, dynamic>> rows,
  ) {
    if (!allowsTable(table)) return const [];
    if (mode == SyncScopeMode.all) {
      return rows.map(Map<String, dynamic>.from).toList();
    }
    return rows
        .where((row) => _rowAllowed(table, row))
        .map(Map<String, dynamic>.from)
        .toList();
  }

  List<Map<String, dynamic>> filterTombstones(
    Iterable<Map<String, dynamic>> tombstones,
  ) {
    if (mode == SyncScopeMode.all) {
      return tombstones.map(Map<String, dynamic>.from).toList();
    }
    return tombstones
        .where((tombstone) {
          final table = _string(tombstone, 'table_name', 'TableName');
          if (!allowsTable(table)) return false;
          final agentId = table == 'agents'
              ? _string(tombstone, 'client_id', 'ClientID')
              : _string(tombstone, 'agent_id', 'AgentID');
          return allowsAgent(agentId);
        })
        .map(Map<String, dynamic>.from)
        .toList();
  }

  bool _rowAllowed(String table, Map<String, dynamic> row) {
    if (table == 'agents') {
      return allowsAgent(_string(row, 'client_id', 'ClientID', 'id', 'ID'));
    }
    if (!allowsAgent(_string(row, 'agent_id', 'AgentID'))) return false;
    if (table == 'long_term_memories' ||
        table == 'base_memories' ||
        table == 'planned_messages') {
      return _string(row, 'group_id', 'GroupID').isEmpty;
    }
    return true;
  }

  static String _string(
    Map<String, dynamic> row,
    String first, [
    String? second,
    String? third,
    String? fourth,
  ]) {
    for (final key in [first, second, third, fourth]) {
      if (key == null) continue;
      final value = row[key];
      if (value != null) return value.toString();
    }
    return '';
  }
}
