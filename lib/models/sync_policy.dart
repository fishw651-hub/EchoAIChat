enum SyncScopeMode { all, selected }

class SyncPolicy {
  const SyncPolicy.all({
    required this.version,
    this.realtimeEnabled = false,
    this.updatedAt,
  }) : scopeMode = SyncScopeMode.all,
       selectedAgentIds = const {};

  const SyncPolicy.selected({
    required Set<String> agentIds,
    required this.version,
    this.realtimeEnabled = false,
    this.updatedAt,
  }) : scopeMode = SyncScopeMode.selected,
       selectedAgentIds = agentIds;

  final SyncScopeMode scopeMode;
  final Set<String> selectedAgentIds;
  final bool realtimeEnabled;
  final int version;
  final DateTime? updatedAt;

  factory SyncPolicy.fromJson(Map<String, dynamic> json) {
    final selected =
        ((json['selected_agent_ids'] as List<dynamic>?) ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toSet();
    final version = (json['version'] as num?)?.toInt() ?? 1;
    final realtime = json['realtime_enabled'] as bool? ?? false;
    final updatedAt = DateTime.tryParse(json['updated_at']?.toString() ?? '');
    if (json['scope_mode'] == 'selected') {
      return SyncPolicy.selected(
        agentIds: selected,
        version: version,
        realtimeEnabled: realtime,
        updatedAt: updatedAt,
      );
    }
    return SyncPolicy.all(
      version: version,
      realtimeEnabled: realtime,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toUpdateJson() => {
    'scope_mode': scopeMode.name,
    'selected_agent_ids': selectedAgentIds.toList()..sort(),
    'realtime_enabled': realtimeEnabled,
    'expected_version': version,
  };

  SyncPolicy copyWith({
    SyncScopeMode? scopeMode,
    Set<String>? selectedAgentIds,
    bool? realtimeEnabled,
    int? version,
    DateTime? updatedAt,
  }) {
    final nextMode = scopeMode ?? this.scopeMode;
    if (nextMode == SyncScopeMode.selected) {
      return SyncPolicy.selected(
        agentIds: selectedAgentIds ?? this.selectedAgentIds,
        version: version ?? this.version,
        realtimeEnabled: realtimeEnabled ?? this.realtimeEnabled,
        updatedAt: updatedAt ?? this.updatedAt,
      );
    }
    return SyncPolicy.all(
      version: version ?? this.version,
      realtimeEnabled: realtimeEnabled ?? this.realtimeEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
