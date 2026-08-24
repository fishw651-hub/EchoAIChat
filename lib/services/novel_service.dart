import '../services/api_service.dart';
import '../services/database_service.dart';

class NovelService {
  static const defaultStyles = ['默认', '古风', '现代', '悬疑', '科幻', '言情'];
  static const defaultWordCount = 500;

  /// 生成小说。
  /// 失败时抛出 [ApiException] 或其他异常，由调用方显示错误。
  /// 不再静默返回空字符串（之前的静默行为导致 UI 显示空白且秒出）。
  static Future<String> generate({
    required String content,
    required String style,
    required int wordCount,
    required String customPrompt,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (apiKey.isEmpty) {
      throw ApiException('请先登录账户');
    }
    if (model.isEmpty) {
      throw ApiException('未选择模型，请在设置中配置');
    }

    final systemPrompt = _buildSystemPrompt(style, wordCount, customPrompt);
    final userPrompt = _buildUserPrompt(content);
    final apiService = ApiService.fromConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);

    // 关键修复：必须包含 user 消息。仅有 system 消息时，部分服务端会直接返回空内容
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    final result = await apiService.chatCompletion(
      messages: messages,
      tools: const [],
    );

    final parsed = ApiService.parseContent(result);
    if (parsed == null || parsed.trim().isEmpty) {
      // 服务端返回了空内容：可能是 model 不支持、内容被安全过滤等
      final finishReason = ApiService.parseFinishReason(result);
      throw ApiException('服务端返回了空内容${finishReason != null ? '（finish_reason=$finishReason）' : ''}，请更换模型或重试',
          statusCode: 200, responseBody: result.toString());
    }
    return parsed;
  }

  static String _buildSystemPrompt(String style, int wordCount, String custom) {
    final base = '你是一位擅长叙事的小说家。'
        '请将用户提供的对话记录改写为「$style」风格的叙事小说，'
        '约 $wordCount 字。'
        '保留原意与情感，增加场景描写、心理活动和文学性表达。'
        '直接输出小说正文，不要加标题、说明、前后缀或 markdown 代码块。';
    final customPart = custom.isNotEmpty ? '\n额外要求：$custom' : '';
    return base + customPart;
  }

  static String _buildUserPrompt(String content) {
    return '请改写以下对话记录为小说：\n\n---\n$content\n---';
  }

  static Future<int> save({
    required String style,
    required int wordCount,
    required String prompt,
    required String result,
  }) async {
    return await DatabaseService.insertNovelGeneration(
      style: style,
      wordCount: wordCount,
      prompt: prompt,
      result: result,
    );
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
    return await DatabaseService.getNovelGenerations();
  }

  static Future<void> delete(int id) async {
    await DatabaseService.deleteNovelGeneration(id);
  }
}

