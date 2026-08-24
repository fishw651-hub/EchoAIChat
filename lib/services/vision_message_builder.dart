import 'image_paths_codec.dart';

/// 图片文件读取器：按本地路径读出 JPEG 字节的 base64（不带 data: 前缀）；
/// 读不到（文件缺失/损坏等）返回 null，调用方据此降级为 [图片] 文本占位。
/// 注入而非直接 dart:io 读取：保持本文件纯 Dart、可单元测试。
typedef VisionImageReader = Future<String?> Function(String imagePath);

/// 视觉消息构建：发图时两条路径（原生视觉 / 绑定视觉模型）共用的纯函数，
/// 不依赖 Flutter/IO，便于单元测试。
class VisionMessageBuilder {
  VisionMessageBuilder._();

  /// 历史消息中图片的文本占位（原生视觉路径下，图片不进历史上下文）
  static const String imagePlaceholder = '[图片]';

  /// 视觉描述调用的系统提示词：必须强制详细可用，
  /// 让主聊天模型仅凭文字就能完全理解图片内容。
  static const String describeSystemPrompt =
      '你是视觉描述助手。请详细描述图片中的人物、物体、场景、动作、文字内容、'
      '颜色、布局与相互关系，输出一段完整自然的描述，让无法看到图片的人也能完全理解'
      '图片内容。不要遗漏重要细节，不要输出"这是一张图片"之类的空话。';

  /// 原生视觉路径：OpenAI 数组型 content（text + image_url）。
  /// [base64Jpeg] 为 JPEG 字节的 base64 编码（不带 data: 前缀）。
  static List<Map<String, dynamic>> buildNativeContent({
    required String userText,
    required String base64Jpeg,
  }) {
    return buildNativeContentMulti(userText: userText, base64Jpegs: [base64Jpeg]);
  }

  /// 原生视觉路径（多图）：text + 每张图一个 image_url part。
  static List<Map<String, dynamic>> buildNativeContentMulti({
    required String userText,
    required List<String> base64Jpegs,
  }) {
    return [
      {
        'type': 'text',
        'text': userText.isEmpty ? imagePlaceholder : userText,
      },
      for (final base64Jpeg in base64Jpegs)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$base64Jpeg'},
        },
    ];
  }

  /// 非原生 + 绑定视觉模型路径：主聊天请求中该用户消息的文本形态。
  /// 用户同时输了文字时拼接在描述标记之前。
  static String composeDescribedContent({
    required String userText,
    required String description,
  }) {
    final tag = '[用户发送了一张图片，图片内容：$description]';
    return userText.isEmpty ? tag : '$userText\n$tag';
  }

  /// 非原生 + 绑定视觉模型路径（多图）：逐张描述后合并为一条标记，
  /// 单张时退化为 [composeDescribedContent] 的单图格式。
  static String composeMultiDescribedContent({
    required String userText,
    required List<String> descriptions,
  }) {
    if (descriptions.length <= 1) {
      return composeDescribedContent(
        userText: userText,
        description: descriptions.isEmpty ? '' : descriptions.first,
      );
    }
    final merged = [
      for (var i = 0; i < descriptions.length; i++) '${i + 1}. ${descriptions[i]}',
    ].join(' ');
    final tag = '[用户发送了${descriptions.length}张图片，图片内容：$merged]';
    return userText.isEmpty ? tag : '$userText\n$tag';
  }

  /// 视觉描述调用的 messages：系统提示词 + 带图 user 消息。
  static List<Map<String, dynamic>> buildDescribeMessages({
    required String userText,
    required String base64Jpeg,
  }) {
    return [
      {'role': 'system', 'content': describeSystemPrompt},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': userText.isEmpty ? '请描述这张图片。' : userText,
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$base64Jpeg'},
          },
        ],
      },
    ];
  }

  /// 图片消息存入短期记忆的初始文本（历史降级为 [图片] 占位）。
  static String historyPlaceholder(String userText) {
    return userText.isEmpty ? imagePlaceholder : '$userText\n$imagePlaceholder';
  }

  /// 一次请求最多附带的图片数（取最近 N 张带图消息，更早的保持 [图片] 文本占位）。
  /// 限制 base64 体积与视觉 token 消耗。聊天上下文与记忆 AI 共用此上限。
  static const int maxAttachedImages = 3;

  /// 给历史消息挂图（原生视觉模型专用），聊天上下文与记忆 AI 共用。
  ///
  /// 输入 maps 每项含 role/content，另可带 'image_path'（String?，单图旧格式）
  /// 与 'image_paths'（字符串列表 或 JSON 数组字符串，多图新格式；为空回退
  /// image_path）。输出为新列表，maps 只含 role/content（两个图片键一定被剥离）：
  /// - [nativeVision] 为 false 或 [readImageBase64] 为 null：原样返回（行为不变）
  /// - 带图且读取成功：content 变数组型（text + 每张图一个 image_url），文本尾部的
  ///   [图片] 占位行随之移除（真实图片替代占位）
  /// - 全部读取失败（文件缺失等）：保持原文本，即 [图片] 占位降级
  /// 上限按"张数"跨消息累计：把每条消息的图片列表按消息时间序展开后取最近
  /// [limit] 张（一条多图消息可占多张额度），更早的图片保持 [图片] 文本占位。
  static Future<List<Map<String, dynamic>>> attachImagesToMessages(
    List<Map<String, dynamic>> messages, {
    required bool nativeVision,
    VisionImageReader? readImageBase64,
    int limit = maxAttachedImages,
  }) async {
    if (!nativeVision || readImageBase64 == null) {
      return [
        for (final m in messages) {'role': m['role'], 'content': m['content']},
      ];
    }
    // 展开每条消息的图片（image_paths 优先，回退 image_path），按消息序排列
    final pathsPerMessage = <int, List<String>>{};
    final occurrences = <int>[]; // 每张图对应的消息索引，按时间序
    for (var i = 0; i < messages.length; i++) {
      final paths = _imagePathsOf(messages[i]);
      if (paths.isEmpty) continue;
      pathsPerMessage[i] = paths;
      occurrences.addAll(List.filled(paths.length, i));
    }
    // 总量超限取最近 limit 张：按消息统计可挂数量（取该消息图片列表尾部）
    final budgetPerMessage = <int, int>{};
    final start = occurrences.length <= limit ? 0 : occurrences.length - limit;
    for (var k = start; k < occurrences.length; k++) {
      final idx = occurrences[k];
      budgetPerMessage[idx] = (budgetPerMessage[idx] ?? 0) + 1;
    }
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final content = m['content'];
      final budget = budgetPerMessage[i] ?? 0;
      if (budget == 0 || content is! String) {
        result.add({'role': m['role'], 'content': content});
        continue;
      }
      final paths = pathsPerMessage[i]!;
      final toAttach = paths.sublist(paths.length - budget);
      final base64List = <String>[];
      for (final path in toAttach) {
        final base64 = await readImageBase64(path);
        if (base64 != null) base64List.add(base64);
      }
      if (base64List.isEmpty) {
        result.add({'role': m['role'], 'content': content});
        continue;
      }
      result.add({
        'role': m['role'],
        'content': buildNativeContentMulti(
          userText: _stripTrailingPlaceholder(content),
          base64Jpegs: base64List,
        ),
      });
    }
    return result;
  }

  /// 读取消息 map 的图片路径列表：优先 image_paths（List 或 JSON 数组字符串），
  /// 为空回退 image_path 单图。
  static List<String> _imagePathsOf(Map<String, dynamic> m) {
    final raw = m['image_paths'];
    if (raw is List) {
      final paths = raw.whereType<String>().where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) return paths;
    } else if (raw is String && raw.isNotEmpty) {
      final paths = ImagePathsCodec.decode(raw);
      if (paths.isNotEmpty) return paths;
    }
    final single = m['image_path'] as String?;
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  /// 移除挂图消息文本尾部的 [图片] 占位行（占位被真实图片替代）。
  static String _stripTrailingPlaceholder(String content) {
    if (content == imagePlaceholder) return '';
    const suffix = '\n$imagePlaceholder';
    if (content.endsWith(suffix)) {
      return content.substring(0, content.length - suffix.length);
    }
    return content;
  }
}
