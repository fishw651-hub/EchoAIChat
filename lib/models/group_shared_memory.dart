class GroupSharedMemory {
  final String id;
  final String groupId;
  final String field;
  final String content;
  final DateTime updatedAt;

  GroupSharedMemory({
    required this.id,
    required this.groupId,
    required this.field,
    required this.content,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  static const validFields = [
    'time',
    'location',
    'current_events',
    'characters',
    'relationships',
    'goals',
    'thoughts',
    'status',
    'to_do',
  ];

  GroupSharedMemory copyWith({
    String? id,
    String? groupId,
    String? field,
    String? content,
    DateTime? updatedAt,
  }) {
    return GroupSharedMemory(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      field: field ?? this.field,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String toPromptLine() => '$id [$field]: $content';

  Map<String, dynamic> toMap() => {
        'id': id,
        'group_id': groupId,
        'field': field,
        'content': content,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory GroupSharedMemory.fromMap(Map<String, dynamic> map) =>
      GroupSharedMemory(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        field: map['field'] as String,
        content: map['content'] as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}
