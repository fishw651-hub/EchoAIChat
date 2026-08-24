import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'model_list_service.dart';
import '../models/long_term_memory.dart';
import 'api_service.dart';
import 'memory_service.dart';
import 'quota_service.dart';

void _olog(String msg) {
  debugPrint('[OCR] $msg');
}

/// Structured chat message extracted from a screenshot.
class OcrMessage {
  final String role; // 'me' or 'them'
  final String content;
  final String? speakerId; // avatar hash to distinguish speakers in group chat
  const OcrMessage({required this.role, required this.content, this.speakerId});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Result of the full OCR → persona + memory pipeline.
class OcrChatResult {
  final List<OcrMessage> messages;
  final String? persona;
  final int memoriesCreated;
  final int baseCreated;

  const OcrChatResult({
    required this.messages,
    this.persona,
    this.memoriesCreated = 0,
    this.baseCreated = 0,
  });
}

class OcrService {
  /// Result of group chat speaker analysis.
  static Future<List<GroupSpeakerResult>> analyzeGroupScreenshots({
    required List<String> imagePaths,
    required String apiKey,
    required String baseUrl,
    bool thinkingMode = true,
  }) async {
    _olog('Processing ${imagePaths.length} group screenshot(s)');

    final allMessages = <OcrMessage>[];
    for (final path in imagePaths) {
      _olog('─ OCR: ${path.split('/').last} ─');
      final msgs = await _ocrExtract(path);
      if (msgs.isNotEmpty) {
        allMessages.addAll(msgs);
        _olog('  → ${msgs.length} messages extracted');
      }
    }

    if (allMessages.isEmpty) {
      _olog('No messages extracted');
      return [];
    }

    // OCR 成功提取到消息后才消耗配额（客户端计数 + 服务端校验），
    // 避免识别失败也扣减配额（QuotaService 暂无退还方法）。
    await QuotaService.instance.consume(QuotaType.ocr);

    // Group 'them' messages by speakerId (avatar hash)
    final speakerGroups = <String?, List<OcrMessage>>{};
    for (final msg in allMessages) {
      if (msg.role == 'them') {
        speakerGroups.putIfAbsent(msg.speakerId, () => []).add(msg);
      }
    }

    if (speakerGroups.isEmpty) {
      _olog('No "them" messages found');
      return [];
    }

    _olog('Detected ${speakerGroups.length} distinct speaker(s)');

    final results = <GroupSpeakerResult>[];
    for (final entry in speakerGroups.entries) {
      final speakerMsgs = entry.value;
      _olog(
        '  Speaker hash=${entry.key?.substring(0, _min(8, entry.key?.length ?? 0))} msgs=${speakerMsgs.length}',
      );

      String? persona;
      try {
        persona = await _generatePersona(
          baseUrl: baseUrl,
          apiKey: apiKey,
          messages: speakerMsgs,
          thinkingMode: thinkingMode,
        );
        _olog('    Persona: ${persona.length} chars');
      } catch (e) {
        _olog('    Persona failed: $e');
      }

      results.add(
        GroupSpeakerResult(
          avatarHash: entry.key,
          messages: speakerMsgs,
          persona: persona,
        ),
      );
    }

    return results;
  }

  /// Process a single screenshot.
  static Future<OcrChatResult> analyzeChatScreenshot({
    required String imagePath,
    required String apiKey,
    required String baseUrl,
    bool thinkingMode = true,
  }) async {
    final result = await analyzeMultipleScreenshots(
      imagePaths: [imagePath],
      apiKey: apiKey,
      baseUrl: baseUrl,
      thinkingMode: thinkingMode,
    );
    return result;
  }

  /// Process multiple screenshots, merge messages, generate persona from combined chat.
  static Future<OcrChatResult> analyzeMultipleScreenshots({
    required List<String> imagePaths,
    required String apiKey,
    required String baseUrl,
    bool thinkingMode = true,
  }) async {
    _olog('Processing ${imagePaths.length} image(s)');

    // ── Step 1: OCR each image, merge all messages ──
    final allMessages = <OcrMessage>[];
    for (final path in imagePaths) {
      _olog('─ OCR: ${path.split('/').last} ─');
      final msgs = await _ocrExtract(path);
      if (msgs.isNotEmpty) {
        allMessages.addAll(msgs);
        _olog('  → ${msgs.length} messages extracted');
      }
    }

    if (allMessages.isEmpty) {
      _olog('No messages extracted from any image');
      return const OcrChatResult(messages: []);
    }
    // OCR 成功提取到消息后才消耗配额（客户端计数 + 服务端校验），
    // 避免识别失败也扣减配额（QuotaService 暂无退还方法）。
    await QuotaService.instance.consume(QuotaType.ocr);
    _olog(
      'Total: ${allMessages.length} messages from ${imagePaths.length} image(s)',
    );
    for (final m in allMessages) {
      _olog(
        '  [${m.role}] ${m.content.length > 50 ? '${m.content.substring(0, 50)}...' : m.content}',
      );
    }

    // ── Step 2: Generate persona with deep thinking (from combined messages) ──
    String? persona;
    try {
      persona = await _generatePersona(
        baseUrl: baseUrl,
        apiKey: apiKey,
        messages: allMessages,
        thinkingMode: thinkingMode,
      );
      _olog('Persona: ${persona.length} chars');
    } catch (e) {
      _olog('Persona failed: $e');
    }

    return OcrChatResult(messages: allMessages, persona: persona);
  }

  /// Step 3: Generate memories with correct agentId.
  static Future<Map<String, int>> generateMemories({
    required String baseUrl,
    required String apiKey,
    required List<OcrMessage> messages,
    required MemoryService memoryService,
    bool thinkingMode = true,
  }) async {
    return await _generateMemories(
      baseUrl: baseUrl,
      apiKey: apiKey,
      messages: messages,
      memoryService: memoryService,
      thinkingMode: thinkingMode,
    );
  }

  // ═══════════════════════════════════════════
  // Step 1: OCR with K-means clustering
  // ═══════════════════════════════════════════

  /// Find the dividing X coordinate between left (them) and right (me) clusters
  /// using 1D K-means (k=2). Falls back to imageCenter if clustering is unreliable.
  static double _findChatThreshold(List<double> xs, int imageWidth) {
    final imageCenter = imageWidth / 2;
    if (xs.length < 3) return imageCenter;

    double c1 = xs[0];
    double c2 = xs.last;
    if (c1 > c2) {
      final t = c1;
      c1 = c2;
      c2 = t;
    }
    if (c1 == c2) return imageCenter;

    int n1 = 0, n2 = 0;

    for (int iter = 0; iter < 50; iter++) {
      double s1 = 0, s2 = 0;
      n1 = 0;
      n2 = 0;

      for (final x in xs) {
        if ((x - c1).abs() <= (x - c2).abs()) {
          s1 += x;
          n1++;
        } else {
          s2 += x;
          n2++;
        }
      }

      if (n1 == 0 || n2 == 0) break;

      final nc1 = s1 / n1;
      final nc2 = s2 / n2;
      if (nc1 == c1 && nc2 == c2) break;
      c1 = nc1;
      c2 = nc2;
    }

    if (n1 < 2 || n2 < 2) return imageCenter;

    final left = c1 < c2 ? c1 : c2;
    final right = c1 < c2 ? c2 : c1;

    if (right - left < imageWidth * 0.15) return imageCenter;

    return (left + right) / 2;
  }

  static Future<List<OcrMessage>> _ocrExtract(String imagePath) async {
    final textRecognizer = TextRecognizer();
    try {
      final fileBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(fileBytes);
      if (image == null) {
        _olog('Failed to decode image');
        return [];
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await textRecognizer.processImage(inputImage);
      final blocks = recognizedText.blocks;
      if (blocks.isEmpty) {
        _olog('No text found');
        return [];
      }

      // Collect all lines with horizontal position + avatar hash
      final allLines = <_RawLine>[];
      for (final block in blocks) {
        for (final line in block.lines) {
          final rect = line.boundingBox;
          final centerX = (rect.left + rect.right) / 2;
          allLines.add(
            _RawLine(
              text: line.text.trim(),
              centerX: centerX,
              top: rect.top,
              left: rect.left,
              bottom: rect.bottom,
            ),
          );
        }
      }
      allLines.sort((a, b) => a.top.compareTo(b.top));

      // K-means clustering on non-system lines to find left/right dividing line
      final chatXs = allLines
          .where((l) => l.text.isNotEmpty && !_isSystemLine(l.text))
          .map((l) => l.centerX)
          .toList();
      final threshold = _findChatThreshold(chatXs, image.width);
      _olog(
        'K-means threshold: ${threshold.toStringAsFixed(0)} (width: ${image.width})',
      );

      // Compute avatar hashes for left-side lines (to distinguish speakers in group chat)
      for (int i = 0; i < allLines.length; i++) {
        final line = allLines[i];
        if (line.centerX < threshold) {
          final hash = _computeAvatarHash(
            image,
            line.left,
            line.top,
            line.bottom,
          );
          allLines[i] = _RawLine(
            text: line.text,
            centerX: line.centerX,
            top: line.top,
            left: line.left,
            bottom: line.bottom,
            avatarHash: hash,
          );
        }
      }

      // Merge adjacent same-role + same-speaker lines
      final messages = <OcrMessage>[];
      String? currentRole;
      String? currentHash;
      final buffer = StringBuffer();

      for (final line in allLines) {
        if (line.text.isEmpty) continue;
        if (_isSystemLine(line.text)) continue;

        final role = line.centerX < threshold ? 'them' : 'me';
        final hash = line.avatarHash;

        if (currentRole == null) {
          currentRole = role;
          currentHash = hash;
          buffer.write(line.text);
        } else if (role == currentRole &&
            _isSameSpeaker(role, currentHash, hash)) {
          buffer.write(line.text);
        } else {
          if (buffer.isNotEmpty) {
            messages.add(
              OcrMessage(
                role: currentRole,
                content: buffer.toString(),
                speakerId: currentHash,
              ),
            );
          }
          currentRole = role;
          currentHash = hash;
          buffer.clear();
          buffer.write(line.text);
        }
      }
      if (buffer.isNotEmpty && currentRole != null) {
        messages.add(
          OcrMessage(
            role: currentRole,
            content: buffer.toString(),
            speakerId: currentHash,
          ),
        );
      }

      final leftCount = messages.where((m) => m.role == 'them').length;
      final rightCount = messages.length - leftCount;
      _olog(
        'Result: ${messages.length} msgs (them=$leftCount me=$rightCount) from ${allLines.length} lines',
      );
      return messages;
    } catch (e) {
      _olog('OCR error: $e');
      return [];
    } finally {
      textRecognizer.close();
    }
  }

  static bool _isSystemLine(String text) {
    if (RegExp(r'^[\d:.\s]+$').hasMatch(text)) {
      return true;
    }
    if (RegExp(r'^\d{2,4}[\-/年月]\d{1,2}[\-/月日]\d{1,2}日?\s*$').hasMatch(text)) {
      return true;
    }
    if (RegExp(r'^[上下]午?\s*\d{1,2}[：:]\d{2}\s*$').hasMatch(text)) {
      return true;
    }
    if (text.contains('以上是打招呼') ||
        text.contains('你已添加了') ||
        text.contains('你们可以开始聊天') ||
        text.contains('对方正在输入') ||
        text.contains('消息已发出但被') ||
        text.contains('撤回了一条消息')) {
      return true;
    }
    // Filter very short single chars (often OCR noise)
    if (text.length <= 1 && !RegExp(r'[a-zA-Z一-鿿]').hasMatch(text)) return true;
    return false;
  }

  static bool _isSameSpeaker(
    String role,
    String? currentHash,
    String? newHash,
  ) {
    if (role == 'me') return true;
    if (currentHash == null || newHash == null) return true;
    return _hammingDistance(currentHash, newHash) <= _avatarHashThreshold;
  }

  // ═══════════════════════════════════════════
  // Step 2: Persona Generation
  // ═══════════════════════════════════════════

  static Future<String> _generatePersona({
    required String baseUrl,
    required String apiKey,
    required List<OcrMessage> messages,
    bool thinkingMode = true,
  }) async {
    final themMsgs = messages.where((m) => m.role == 'them').toList();
    final meMsgs = messages.where((m) => m.role == 'me').toList();

    if (themMsgs.isEmpty) return '';

    final themText = themMsgs.map((m) => '你说：${m.content}').join('\n');
    final meText = meMsgs.map((m) => '用户回答：${m.content}').join('\n');

    final systemPrompt = '''你是一位专业的人格分析师。你的任务是根据两个人的聊天记录，为"对方"生成一份完整、准确的人格提示词。

你需要从聊天记录中提取以下信息来构建人格：
1. **基础身份**：对方的名字、性别（如果能推断）、大致年龄或年龄段、职业或身份
2. **与用户的关系**：对方和"我"是什么关系（恋人、朋友、同学、同事、家人等），关系深度如何
3. **性格特征**：从对方的用词、语气、回复方式中分析性格——是外向还是内向、是感性还是理性、是主动还是被动
4. **说话习惯**：对方是否有独特的口头禅、常用表情/符号、语气词、句式特点、回复的长短偏好
5. **做过的事/共同经历**：聊天中提到过的事件、一起做过的事、共同的经历——这些都是基础记忆的重要素材
6. **提及的人物**：聊天中提到的其他人物（朋友、家人、同事等），以及他们之间的关系
7. **兴趣爱好**：对方关心的话题、喜欢的活动、经常讨论的内容

## 输出格式
直接输出一段人格提示词，用第二人称"你"来写（对着对方说）。不要加"人格提示词："等前缀。
格式参考：
"你是[名字]，[性别]，[大致年龄]，[身份/职业]。性格[具体性格描述]。你和用户是[关系]，[关系描述]。你的说话风格[具体描述]。你做过[具体事件]。你认识[提及的人物]。你喜欢[兴趣爱好]..."

## 规则
- **只从聊天记录推断**，不编造信息。如果某个信息无法推断，就省略不写
- 所有推断都要有聊天记录中的依据
- 长度 300-600 字，内容越丰富越好
- 保持自然流畅的文字，不要用列表或编号格式''';

    final userPrompt =
        '''## 对方的全部聊天消息（按时间顺序）
$themText

## 我（用户）的全部聊天消息（按时间顺序）
$meText

请根据以上完整的聊天记录，为"对方"生成一份详细的人格提示词。要包含：基础身份、与用户的关系、性格特征、说话习惯、共同经历、提及的人物、兴趣爱好。''';

    // Use deepseek-v4-flash with deep thinking for persona generation
    final apiService = ApiService.fromConfig(
      model: await ModelListService.getSelectedModel(),
      apiKey: apiKey,
      baseUrl: baseUrl,
      thinkingMode: thinkingMode,
    );

    final response = await apiService.chatCompletion(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      tools: [],
    );

    return ApiService.parseContent(response) ?? '';
  }

  // ═══════════════════════════════════════════
  // Step 3: Memory Generation
  // ═══════════════════════════════════════════

  static Future<Map<String, int>> _generateMemories({
    required String baseUrl,
    required String apiKey,
    required List<OcrMessage> messages,
    required MemoryService memoryService,
    bool thinkingMode = true,
  }) async {
    final chatText = messages
        .map((m) => '${m.role == 'me' ? '用户回答' : '你说'}：${m.content}')
        .join('\n\n');

    final existingLT = await memoryService.getLongTermMemories();
    final existingBM = await memoryService.getBaseMemories();

    final ltLines = existingLT.isNotEmpty
        ? existingLT.map((m) => m.toPromptLine()).join('\n')
        : '（无现有记忆）';
    final bmLines = existingBM.isNotEmpty
        ? existingBM.map((m) => m.toPromptLine()).join('\n')
        : '（无现有记忆）';

    final systemPrompt =
        '''你是专属于"对方"的记忆管理器。你的任务是从两人的聊天记录中提取关于"对方"的一切值得记住的信息。

## 长期记忆 (long_term) — 保存目前仍然成立的信息
使用以下字段分类：
- relationships：与用户的关系、与其他人的关系
- characters：对方是什么样的人（性格特征）
- current_events：对方最近在做什么、发生了什么
- goals：对方的目标、计划、想做的事
- thoughts：对方的想法、观点、态度
- status：对方的身体状态、生活状态、情绪状态
- time：对方提到的时间相关信息
- location：对方所在的地点、常去的地方
- to_do：对方需要做的事、约定

## 基础记忆 (base)
- setting：对方的背景设定（身份、职业、重要背景信息）
- event：与对方相关的重要事件、共同经历、聊天中提到过的往事

## 输出格式
严格的 JSON，不要 markdown：
{"long_term": [{"field": "字段名", "content": "具体内容，用'你'指代对方"}], "base": [{"type": "setting|event", "content": "具体内容，用'你'指代对方"}]}

## 规则
1. 每条 content 用"你"指代对方（如"你和用户是大学同学"）
2. 不记录琐碎闲聊——只记录真正有长期价值的信息
3. 如果现有记忆已有相同内容，不需要重复创建
4. content 要具体、可用（不只是"性格好"而是"性格开朗幽默，喜欢自嘲"）
5. 从聊天记录中尽可能多地提取——宁可多记不要遗漏

## 现有长期记忆
$ltLines

## 现有基础记忆
$bmLines

## 聊天记录（时间顺序）
$chatText''';

    final apiService = ApiService.fromConfig(
      model: await ModelListService.getSelectedModel(),
      apiKey: apiKey,
      baseUrl: baseUrl,
      thinkingMode: thinkingMode,
    );

    final response = await apiService.chatCompletion(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': '分析以上聊天记录，提取关于"对方"的所有值得记住的信息。只返回 JSON，不要其他内容。',
        },
      ],
      tools: [],
    );

    final content = ApiService.parseContent(response);
    if (content == null || content.isEmpty) return {'ltm': 0, 'bm': 0};

    final parsed = _parseJson(content);
    if (parsed == null) return {'ltm': 0, 'bm': 0};

    int ltm = 0, bm = 0;

    final longTerm = parsed['long_term'] as List?;
    if (longTerm != null) {
      for (final op in longTerm) {
        try {
          final field = (op['field'] as String?) ?? 'status';
          final cnt = (op['content'] as String?) ?? '';
          if (cnt.isNotEmpty && LongTermMemory.validFields.contains(field)) {
            await memoryService.createLongTermMemory(
              field: field,
              content: cnt,
            );
            ltm++;
          }
        } catch (e) {
          _olog('LTM err: $e');
        }
      }
    }

    final base = parsed['base'] as List?;
    if (base != null) {
      for (final op in base) {
        try {
          final type = (op['type'] as String?) ?? 'event';
          final cnt = (op['content'] as String?) ?? '';
          if (cnt.isNotEmpty && (type == 'setting' || type == 'event')) {
            await memoryService.createBaseMemory(type: type, content: cnt);
            bm++;
          }
        } catch (e) {
          _olog('BM err: $e');
        }
      }
    }

    _olog('Memories: LTM=$ltm BM=$bm');
    return {'ltm': ltm, 'bm': bm};
  }

  static Map<String, dynamic>? _parseJson(String content) {
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {}
    try {
      final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
      if (m != null) {
        return jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
      }
    } catch (_) {}
    try {
      final start = content.indexOf('{');
      final end = content.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return jsonDecode(content.substring(start, end + 1))
            as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

// ─── Helpers ───

const int _avatarSize = 44;
const int _avatarHashThreshold = 10;

class _RawLine {
  final String text;
  final double centerX;
  final double top;
  final double left;
  final double bottom;
  final String? avatarHash;
  const _RawLine({
    required this.text,
    required this.centerX,
    required this.top,
    required this.left,
    required this.bottom,
    this.avatarHash,
  });
}

/// Compute perceptual hash (aHash) of the avatar region to the left of a text block.
String? _computeAvatarHash(
  img.Image image,
  double textLeft,
  double textTop,
  double textBottom,
) {
  final avatarLeft = (textLeft - _avatarSize - 8).round();
  final textCenterY = (textTop + textBottom) / 2;
  final avatarTop = (textCenterY - _avatarSize / 2).round();

  final ax = avatarLeft.clamp(0, image.width - _avatarSize);
  final ay = avatarTop.clamp(0, image.height - _avatarSize);
  if (ax + _avatarSize > image.width || ay + _avatarSize > image.height) {
    return null;
  }

  try {
    final avatar = img.copyCrop(
      image,
      x: ax,
      y: ay,
      width: _avatarSize,
      height: _avatarSize,
    );
    final small = img.copyResize(avatar, width: 8, height: 8);

    int total = 0;
    final grays = List.filled(64, 0);
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final p = small.getPixel(x, y);
        final gray = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        grays[y * 8 + x] = gray;
        total += gray;
      }
    }
    final avg = total / 64;

    final sb = StringBuffer();
    for (final g in grays) {
      sb.write(g >= avg ? '1' : '0');
    }
    return sb.toString();
  } catch (_) {
    return null;
  }
}

/// Result of group speaker analysis.
class GroupSpeakerResult {
  final String? avatarHash;
  final List<OcrMessage> messages;
  final String? persona;
  const GroupSpeakerResult({
    this.avatarHash,
    required this.messages,
    this.persona,
  });
}

int _min(int a, int b) => a < b ? a : b;

int _hammingDistance(String a, String b) {
  if (a.length != b.length) return 64;
  int dist = 0;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) dist++;
  }
  return dist;
}
