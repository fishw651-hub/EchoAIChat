class LongTermMemory {
  final String id;
  final String field;
  final String content;
  final String? agentId;
  final String? groupId;
  final DateTime createdAt;
  final DateTime updatedAt;

  LongTermMemory({
    required this.id,
    required this.field,
    required this.content,
    this.agentId,
    this.groupId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  LongTermMemory copyWith({
    String? id, String? field, String? content, String? agentId, String? groupId, DateTime? createdAt, DateTime? updatedAt,
  }) => LongTermMemory(
    id: id ?? this.id, field: field ?? this.field, content: content ?? this.content,
    agentId: agentId ?? this.agentId, groupId: groupId ?? this.groupId,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );

  String toPromptLine() => '$id [$field]: $content';

  Map<String, dynamic> toMap() => {
    'id': id, 'field': field, 'content': content,
    'agent_id': agentId,
    'group_id': groupId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory LongTermMemory.fromMap(Map<String, dynamic> map) => LongTermMemory(
    id: map['id'] as String, field: map['field'] as String, content: map['content'] as String,
    agentId: map['agent_id'] as String?,
    groupId: map['group_id'] as String?,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  static const validFields = ['time','location','current_events','characters','relationships','goals','thoughts','status','to_do'];
}
