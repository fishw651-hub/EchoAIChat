class PlannedMessage {
  final int? id;
  final DateTime scheduledTime;
  final String message;
  final bool delivered;
  final String? agentId;
  final String? groupId;

  PlannedMessage({
    this.id,
    required this.scheduledTime,
    required this.message,
    this.delivered = false,
    this.agentId,
    this.groupId,
  });

  PlannedMessage copyWith({
    int? id,
    DateTime? scheduledTime,
    String? message,
    bool? delivered,
    String? agentId,
    String? groupId,
  }) {
    return PlannedMessage(
      id: id ?? this.id,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      message: message ?? this.message,
      delivered: delivered ?? this.delivered,
      agentId: agentId ?? this.agentId,
      groupId: groupId ?? this.groupId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'scheduled_time': scheduledTime.millisecondsSinceEpoch,
        'message': message,
        'delivered': delivered ? 1 : 0,
        'agent_id': agentId,
        'group_id': groupId,
      };

  factory PlannedMessage.fromMap(Map<String, dynamic> map) => PlannedMessage(
        id: map['id'] as int?,
        scheduledTime:
            DateTime.fromMillisecondsSinceEpoch(map['scheduled_time'] as int),
        message: map['message'] as String,
        delivered: (map['delivered'] as int) == 1,
        agentId: map['agent_id'] as String?,
        groupId: map['group_id'] as String?,
      );
}
