import '../services/image_paths_codec.dart';

class ShortTermMessage {
  final String id;
  final String role;
  final String content;
  final String? agentId;

  /// 本地图片路径（图片消息）；原生视觉模型构建上下文/记忆 AI 时按此路径现读挂图。
  /// 多图消息时为完整列表的首图（兼容字段），完整列表见 [imagePaths]。
  final String? imagePath;

  /// 多图消息的全部本地图片路径（image_paths 列，JSON 数组解码后的列表）
  final List<String>? imagePaths;
  final DateTime timestamp;

  ShortTermMessage({required this.id, required this.role, required this.content, this.agentId, this.imagePath, this.imagePaths, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {'id': id, 'role': role, 'content': content};
  Map<String, dynamic> toMap() => {'id': id, 'role': role, 'content': content, 'agent_id': agentId,
    // image_path 保留写入首图兼容旧版读取；完整列表存 image_paths（JSON 数组）
    'image_path': imagePath ?? ((imagePaths != null && imagePaths!.isNotEmpty) ? imagePaths!.first : null),
    'image_paths': ImagePathsCodec.encode(imagePaths),
    'timestamp': timestamp.millisecondsSinceEpoch};

  factory ShortTermMessage.fromMap(Map<String, dynamic> map) {
    // 读取兼容：优先 image_paths（JSON 数组），为空回退 image_path 单图列
    final paths = ImagePathsCodec.resolve(
      imagePathsRaw: map['image_paths'] as String?,
      imagePath: map['image_path'] as String?,
    );
    return ShortTermMessage(
      id: map['id'] as String, role: map['role'] as String, content: map['content'] as String,
      agentId: map['agent_id'] as String?,
      imagePath: map['image_path'] as String?,
      imagePaths: paths.isEmpty ? null : paths,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }

  Map<String, dynamic> toOpenAiMessage() => {'role': role, 'content': content};
}
