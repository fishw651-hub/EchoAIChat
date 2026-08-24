import '../services/tool_executor.dart';

class ChatMessage {
  final int? dbId;
  final String role;
  final String content;
  final DateTime timestamp;
  final List<ToolExecutionLog>? toolLogs;
  final String? shortMemId;
  final String? imagePath;
  final List<String>? imagePaths;
  final int? promptTokens;
  final int? completionTokens;
  final bool isStreaming;
  final String? stickerId;
  final String? stickerDescription;
  final String? stickerPath;

  ChatMessage({
    this.dbId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.toolLogs,
    this.shortMemId,
    this.imagePath,
    this.imagePaths,
    this.promptTokens,
    this.completionTokens,
    this.isStreaming = false,
    this.stickerId,
    this.stickerDescription,
    this.stickerPath,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// 全部图片路径：优先多图列表，为空回退单图 imagePath（兼容旧数据）
  List<String> get allImagePaths =>
      (imagePaths != null && imagePaths!.isNotEmpty)
      ? imagePaths!
      : (imagePath != null ? [imagePath!] : const <String>[]);

  ChatMessage copyWith({String? content, bool? isStreaming, int? dbId}) {
    return ChatMessage(
      dbId: dbId ?? this.dbId,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      toolLogs: toolLogs,
      shortMemId: shortMemId,
      imagePath: imagePath,
      imagePaths: imagePaths,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      isStreaming: isStreaming ?? this.isStreaming,
      stickerId: stickerId,
      stickerDescription: stickerDescription,
      stickerPath: stickerPath,
    );
  }
}
