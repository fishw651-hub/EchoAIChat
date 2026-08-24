class BaseMemory {
  final String id;
  final String type;
  final String content;
  final String? agentId;
  final String? groupId;
  final DateTime createdAt;
  final DateTime updatedAt;

  BaseMemory({
    required this.id, required this.type, required this.content, this.agentId, this.groupId,
    DateTime? createdAt, DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(), updatedAt = updatedAt ?? DateTime.now();

  bool get isSetting => type == 'setting';
  bool get isEvent => type == 'event';

  BaseMemory copyWith({
    String? id, String? type, String? content, String? agentId, String? groupId, DateTime? createdAt, DateTime? updatedAt,
  }) => BaseMemory(
    id: id ?? this.id, type: type ?? this.type, content: content ?? this.content,
    agentId: agentId ?? this.agentId, groupId: groupId ?? this.groupId,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );

  String toPromptLine() => '$id [$type]: $content';

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type, 'content': content, 'agent_id': agentId, 'group_id': groupId,
    'updated_at': updatedAt.millisecondsSinceEpoch, 'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory BaseMemory.fromMap(Map<String, dynamic> map) => BaseMemory(
    id: map['id'] as String, type: map['type'] as String, content: map['content'] as String,
    agentId: map['agent_id'] as String?,
    groupId: map['group_id'] as String?,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );
}
