import 'dart:convert';
import 'dart:io';

import 'api_service.dart';
import 'chat_runtime_policy.dart';
import 'vision_message_builder.dart';

/// 图片字节读取器：按本地路径读出原始字节。注入而非直接 dart:io 读取，
/// 保持可单元测试；默认实现走文件系统。
typedef ImageBytesReader = Future<List<int>> Function(String imagePath);

/// 视觉描述 API 工厂：按视觉模型参数构造 ApiService（注入以便测试替换 HTTP 层）。
typedef DescribeApiFactory =
    ApiService Function({
      required String model,
      required String apiKey,
      required String baseUrl,
    });

Future<List<int>> _defaultReadBytes(String imagePath) =>
    File(imagePath).readAsBytes();

/// 聊天图片处理（从 ChatNotifier 抽取）：本地图片 base64 读取 +
/// 非原生视觉路径的图片详细描述调用。
class ChatImageService {
  ChatImageService({ImageBytesReader? readBytes, DescribeApiFactory? apiFactory})
    : _readBytes = readBytes ?? _defaultReadBytes,
      _apiFactory = apiFactory ?? _defaultApiFactory;

  final ImageBytesReader _readBytes;
  final DescribeApiFactory _apiFactory;

  static ApiService _defaultApiFactory({
    required String model,
    required String apiKey,
    required String baseUrl,
  }) {
    return ApiService.fromConfig(
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      thinkingMode: false,
      temperature: ChatRuntimePolicy.standard.temperature!,
    );
  }

  /// 读取本地图片并 base64 编码（历史短期消息挂图用）；
  /// 文件缺失/读取失败返回 null，由调用方降级为 [图片] 文本占位
  Future<String?> readImageBase64(String imagePath) async {
    try {
      return base64Encode(await _readBytes(imagePath));
    } catch (_) {
      return null;
    }
  }

  /// 非原生视觉路径：调用绑定的视觉模型生成图片详细描述。
  /// 就是一次普通的 chatCompletion（走服务器正常计费）。
  /// 失败抛异常，由 sendMessage 的 catch 统一处理（不静默吞）。
  Future<String> describeImage({
    required String visionModelId,
    required String apiKey,
    required String baseUrl,
    required String userText,
    required String imagePath,
  }) async {
    final imageBytes = await _readBytes(imagePath);
    final visionService = _apiFactory(
      model: visionModelId,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );
    final response = await visionService.chatCompletion(
      messages: VisionMessageBuilder.buildDescribeMessages(
        userText: userText,
        base64Jpeg: base64Encode(imageBytes),
      ),
      tools: const [],
      toolChoice: 'none',
    );
    final description = ApiService.parseContent(response);
    if (description == null || description.trim().isEmpty) {
      throw ApiException('图片识别失败：视觉模型未返回有效描述');
    }
    return description.trim();
  }

  /// 多图：逐张串行生成描述后返回列表，任一张失败整体抛异常
  /// （整体发送失败并退配额，不静默吞）。
  Future<List<String>> describeImages({
    required String visionModelId,
    required String apiKey,
    required String baseUrl,
    required String userText,
    required List<String> imagePaths,
  }) async {
    final descriptions = <String>[];
    for (final path in imagePaths) {
      descriptions.add(
        await describeImage(
          visionModelId: visionModelId,
          apiKey: apiKey,
          baseUrl: baseUrl,
          userText: userText,
          imagePath: path,
        ),
      );
    }
    return descriptions;
  }
}
