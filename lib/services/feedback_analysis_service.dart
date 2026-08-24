import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'model_list_service.dart';
import '../config/server_config.dart';
import '../models/base_memory.dart';
import '../models/chat_message.dart' show ChatMessage;
import 'api_service.dart';
import 'database_service.dart';

/// 点赞 / 踩 分析服务
///
/// 用户长按消息点赞或踩时，调用 `deepseek-v4-flash` + thinking high，
/// 根据最近 5 轮对话分析用户偏好/不满，将结论作为 `event` 类型的 base memory 持久化，
/// 后续对话会自动通过 `_buildSystemPrompt()` 注入到提示词中。
class FeedbackAnalysisService {
  /// 分析用户点赞/踩的反馈并写入记忆
  ///
  /// [isLike] true=点赞，false=踩
  /// [recentMessages] 最近 5 轮对话（user + assistant 交替）
  /// [agentId] 当前智能体 ID
  /// [apiKey] 用户 API key
  ///
  /// 返回 null 表示成功，否则返回错误信息
  static Future<String?> analyzeAndStore({
    required bool isLike,
    required List<ChatMessage> recentMessages,
    required String agentId,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) return '请先登录账户';
    if (agentId.isEmpty) return '当前无智能体';
    if (recentMessages.isEmpty) return '没有可分析的对话';

    try {
      final dialogText = _formatRecentDialog(recentMessages);
      final systemPrompt = _buildSystemPrompt(isLike);
      final userPrompt = _buildUserPrompt(isLike, dialogText);

      final apiService = ApiService.fromConfig(
        baseUrl: ServerConfig.baseUrl,
        apiKey: apiKey,
        model: await ModelListService.getSelectedModel(),
        thinkingMode: true,
      );

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ];

      final result = await apiService.chatCompletion(
        messages: messages,
        tools: const [],
      );
      final content = ApiService.parseContent(result);

      if (content == null || content.trim().isEmpty) {
        return '分析结果为空';
      }

      // 提取并存储到 base_memories（event 类型，可被后续 system prompt 自动注入）
      final insight = content.trim();
      await _storeAsMemory(agentId, isLike, insight);
      return null;
    } catch (e) {
      debugPrint('[FeedbackAnalysis] error: $e');
      return '分析失败：$e';
    }
  }

  static String _formatRecentDialog(List<ChatMessage> msgs) {
    final buf = StringBuffer();
    for (final m in msgs) {
      final role = m.isUser ? '用户' : '智能体';
      buf.writeln('$role: ${m.content}');
    }
    return buf.toString();
  }

  static String _buildSystemPrompt(bool isLike) {
    final action = isLike ? '点赞' : '不点赞';
    final goal = isLike
        ? '分析用户喜欢这次回复的哪些方面（风格、内容、语气、节奏等），提炼出可复用的偏好结论'
        : '分析用户对这次回复的不满之处（哪里不符合预期、哪里让用户不舒服），提炼出需要避免的反模式';

    return '''你是一个用户偏好分析智能体。用户对智能体的最近一条回复点击了「$action」。
你的任务：$goal。

## 角色定位
- "我" = 你（分析智能体）
- "对方" = 用户
- "智能体" = 与用户对话的另一个 AI

## 输出要求
- 用一句简洁的中文陈述句总结结论
- 不要解释、不要分点、不要前缀（如"结论："）
- 50 字以内
- 必须基于对话内容，不要凭空捏造
- 用第三人称描述用户偏好（如"用户喜欢……" / "用户不喜欢……"）

## 示例
点赞示例输入：用户问"今天累不累"，智能体回复"累翻了，被组长抓去开会两小时……"
点赞示例输出：用户喜欢智能体用生活化口吻分享日常，能展现脆弱和真实情绪

踩示例输入：用户问"今天累不累"，智能体回复"作为AI我不会累，但我能理解你的疲惫"
踩示例输出：用户不喜欢智能体强调AI身份、用程式化共情替代真实回答''';
  }

  static String _buildUserPrompt(bool isLike, String dialog) {
    return '''用户对以下对话的最后一条智能体回复点击了「${isLike ? '点赞' : '踩'}」。

最近对话：
$dialog

请根据以上对话，按照系统提示的格式输出一条结论。''';
  }

  static Future<void> _storeAsMemory(
    String agentId,
    bool isLike,
    String insight,
  ) async {
    // 全局唯一 UUID（带 B- 前缀，与基础记忆新格式一致）
    final id = 'B-${const Uuid().v4()}';
    final memory = BaseMemory(
      id: id,
      type: 'event',
      content: '[${isLike ? '点赞反馈' : '踩反馈'}] $insight',
      agentId: agentId,
    );
    await DatabaseService.insertBaseMemory(memory);
  }
}
