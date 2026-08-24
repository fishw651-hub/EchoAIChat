import 'dart:convert';
import '../services/tool_executor.dart';

class GroupMessage {
  final int? id;
  final String groupId;
  final String senderType;
  final String? senderId;
  final String? senderName;
  final String content;
  final int timestamp;
  final String? toolCallData;
  final List<ToolExecutionLog>? toolLogs;

  /// 仅内存态：流式生成中的临时消息。不入库、不参与序列化。
  final bool isStreaming;

  GroupMessage({
    this.id,
    required this.groupId,
    required this.senderType,
    this.senderId,
    this.senderName,
    required this.content,
    int? timestamp,
    this.toolCallData,
    List<ToolExecutionLog>? toolLogs,
    this.isStreaming = false,
  })  : toolLogs = toolLogs ?? _parseToolLogs(toolCallData),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  static List<ToolExecutionLog>? _parseToolLogs(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => ToolExecutionLog(
        toolName: e['toolName'] as String,
        arguments: Map<String, dynamic>.from(e['arguments'] as Map),
        result: e['result'] as String,
      )).toList();
    } catch (_) {
      return null;
    }
  }

  bool get isUser => senderType == 'user';
  bool get isAgent => senderType == 'agent';

  GroupMessage copyWith({
    int? id,
    String? groupId,
    String? senderType,
    String? senderId,
    String? senderName,
    String? content,
    int? timestamp,
    String? toolCallData,
    List<ToolExecutionLog>? toolLogs,
    bool? isStreaming,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderType: senderType ?? this.senderType,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCallData: toolCallData ?? this.toolCallData,
      toolLogs: toolLogs ?? this.toolLogs,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'group_id': groupId,
        'sender_type': senderType,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'timestamp': timestamp,
        'tool_call_data': toolCallData,
      };

  factory GroupMessage.fromMap(Map<String, dynamic> map) => GroupMessage(
        id: map['id'] as int?,
        groupId: map['group_id'] as String,
        senderType: map['sender_type'] as String,
        senderId: map['sender_id'] as String?,
        senderName: map['sender_name'] as String?,
        content: map['content'] as String,
        timestamp: map['timestamp'] as int,
        toolCallData: map['tool_call_data'] as String?,
      );
}
