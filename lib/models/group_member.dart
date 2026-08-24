class GroupMember {
  final int? id;
  final String groupId;
  final String agentId;
  final String role;
  final bool isPresent;
  final int joinedAt;

  GroupMember({
    this.id,
    required this.groupId,
    required this.agentId,
    this.role = 'member',
    this.isPresent = true,
    int? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now().millisecondsSinceEpoch;

  GroupMember copyWith({
    int? id,
    String? groupId,
    String? agentId,
    String? role,
    bool? isPresent,
    int? joinedAt,
  }) {
    return GroupMember(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      isPresent: isPresent ?? this.isPresent,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'group_id': groupId,
        'agent_id': agentId,
        'role': role,
        'is_present': isPresent ? 1 : 0,
        'joined_at': joinedAt,
      };

  factory GroupMember.fromMap(Map<String, dynamic> map) => GroupMember(
        id: map['id'] as int?,
        groupId: map['group_id'] as String,
        agentId: map['agent_id'] as String,
        role: (map['role'] as String?) ?? 'member',
        isPresent: (map['is_present'] as int?) == 1,
        joinedAt: map['joined_at'] as int,
      );
}
