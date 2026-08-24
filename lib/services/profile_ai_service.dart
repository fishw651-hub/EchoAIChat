import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'model_list_service.dart';
import 'api_service.dart';
import 'user_profile_service.dart';
import 'database_service.dart';
import '../models/profile_entry.dart';

void _plog(String msg) {
  debugPrint('[ProfileAI] $msg');
}

class ProfileAiService {
  static const userFactPolicy =
      '只记录用户明确表达或有直接证据支持的稳定事实；不要把智能体本人的信息归入用户画像，也不要猜测敏感属性。';

  static Future<void> analyzeAndApply({
    required UserProfileService profileService,
    required String apiKey,
    required String baseUrl,
    required double temperature,
    required List<Map<String, dynamic>> shortTerm,
  }) async {
    if (shortTerm.isEmpty || apiKey.isEmpty) return;

    final existingEntries = await DatabaseService.getProfileEntries();
    final profileLines = existingEntries.isNotEmpty
        ? existingEntries
              .map(
                (p) =>
                    '${p.categoryLabel} - ${p.key}: ${p.value}（可信度${p.confidence}%）',
              )
              .join('\n')
        : '（暂无画像信息）';

    final shortTermLines = shortTerm
        .map((m) {
          final role = m['role'] as String;
          final content = m['content'] as String;
          // 关键：智能体（即"我"）说的话用"我说"，用户（即"对方"）说的话用"对方说"
          return role == 'user' ? '对方（用户）说：$content' : '我（智能体）说：$content';
        })
        .join('\n');

    final systemPrompt =
        '''你是用户画像分析师。根据对话内容，提取对方（用户）的相关信息并更新用户画像。
你必须返回一个严格的 JSON 对象（不要加 markdown 代码块标记），格式为：
{"create": [{"category": "分类", "key": "属性名", "value": "属性值", "confidence": 0-100}], "update": [{"category": "分类", "key": "属性名", "value": "新值", "confidence": 0-100}]}

## 角色定位（极其重要）
- "我" = 智能体本人（即对话中发出回复的角色），对应 role=assistant
- "对方" / "用户" = 与智能体对话的人，对应 role=user
- 在下方"最新对话"中：
  - "我（智能体）说：xxx" → 这是智能体本人讲的话
  - "对方（用户）说：xxx" → 这是用户讲的话
- 你只提取"对方（用户）"的画像信息，不要把智能体本人的信息误归到用户画像

$userFactPolicy

可用的分类：
- basic_info：基本信息（姓名、年龄、职业、所在地等）
- interests：兴趣爱好（爱好、喜欢的活动）
- personality：性格特点（内向/外向、理性/感性等）
- habits：生活习惯（作息、饮食等）
- work_study：工作学习（职业、行业、学校等）
- preferences：偏好（喜欢的颜色、食物、音乐等）
- social：社交关系（家人、朋友、宠物等）
- health：健康状况（过敏、锻炼等）

规则：
1. confidence 根据确定性打分：用户直接说的 90+，间接推断的 50-70，猜测的 <50
2. 如果某条信息已存在且内容没有变化，不要重复输出
3. update 操作按 (key, category) 匹配现有条目并更新 value 和 confidence；如果不存在则改为 create
4. 如果用户明确否定或纠正了之前的信息，用 update 更新（如之前"喜欢猫"现在说"其实更喜欢狗"，update key=喜欢的动物 value=狗）
5. 不输出琐碎、无意义的临时信息（如"刚才吃了饭""现在在上班"等）
6. 如果本轮没有值得提取的信息，返回空的数组 {"create": [], "update": []}
7. key 用简短的名词短语，如"姓名""年龄""职业""所在地""喜欢的音乐"等，不要用句子或问题形式

## 现有画像
$profileLines

## 最新对话
$shortTermLines

## 示例
对话：
对方（用户）说：我今年25岁，在杭州当老师。
我（智能体）说：哇，杭州是个好地方！老师这个职业很伟大呢。

输出：
{"create": [{"category": "basic_info", "key": "年龄", "value": "25岁", "confidence": 95}, {"category": "work_study", "key": "职业", "value": "老师", "confidence": 95}, {"category": "basic_info", "key": "所在地", "value": "杭州", "confidence": 95}], "update": []}''';

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': '分析以上对话，提取用户画像信息。返回纯 JSON 对象，不要包装在 markdown 代码块中。',
      },
    ];

    try {
      // 使用 flash 模型（非思考模式，降低成本：从 3× 倍率降至 1×）
      final apiService = ApiService.fromConfig(
        model: await ModelListService.getSelectedModel(),
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: false,
        temperature: temperature,
      );

      final response = await apiService.chatCompletion(
        messages: messages,
        tools: [],
      );

      final content = ApiService.parseContent(response);
      if (content == null || content.isEmpty) {
        _plog('Empty response');
        return;
      }

      final parsed = _parseJson(content);
      if (parsed == null) {
        _plog('Failed to parse JSON from response');
        return;
      }

      await _applyOperations(parsed, profileService);
    } on ApiException catch (e) {
      _plog('API error: $e');
    } catch (e) {
      _plog('Unexpected error: $e');
    }
  }

  static Map<String, dynamic>? _parseJson(String content) {
    try {
      return jsonDecode(content) as Map<String, dynamic>?;
    } catch (_) {
      try {
        final match = RegExp(
          r'```(?:json)?\s*([\s\S]*?)```',
        ).firstMatch(content);
        if (match != null) {
          return jsonDecode(match.group(1)!.trim()) as Map<String, dynamic>?;
        }
      } catch (_) {}
      try {
        final start = content.indexOf('{');
        final end = content.lastIndexOf('}');
        if (start >= 0 && end > start) {
          return jsonDecode(content.substring(start, end + 1))
              as Map<String, dynamic>?;
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<void> _applyOperations(
    Map<String, dynamic> parsed,
    UserProfileService ps,
  ) async {
    int created = 0, updated = 0;

    final creates = parsed['create'] as List?;
    if (creates != null) {
      for (final op in creates) {
        try {
          final category = op['category'] as String? ?? '';
          final key = op['key'] as String? ?? '';
          final value = op['value'] as String? ?? '';
          final confidence = (op['confidence'] as num?)?.toInt() ?? 50;
          if (category.isNotEmpty && key.isNotEmpty && value.isNotEmpty) {
            await ps.createEntry(
              category: category,
              key: key,
              value: value,
              confidence: confidence,
              source: 'ai_extracted',
            );
            created++;
          }
        } catch (e) {
          _plog('  create op failed: $e');
        }
      }
    }

    final updates = parsed['update'] as List?;
    if (updates != null) {
      for (final op in updates) {
        try {
          final category = op['category'] as String? ?? '';
          final key = op['key'] as String? ?? '';
          final value = op['value'] as String? ?? '';
          final confidence = (op['confidence'] as num?)?.toInt() ?? 50;
          if (category.isNotEmpty && key.isNotEmpty && value.isNotEmpty) {
            final existing = await ps.getEntry(key, category);
            if (existing != null) {
              await ps.createEntry(
                category: category,
                key: key,
                value: value,
                confidence: confidence,
                source: 'ai_extracted',
              );
              updated++;
            } else {
              await ps.createEntry(
                category: category,
                key: key,
                value: value,
                confidence: confidence,
                source: 'ai_extracted',
              );
              created++;
            }
          }
        } catch (e) {
          _plog('  update op failed: $e');
        }
      }
    }

    _plog('Applied: created=$created updated=$updated');
  }

  /// 为指定分类生成 1-3 个补充问题（用于思维导图分类节点的"补充此项"按钮）。
  /// 使用 flash 思考模型，根据已有画像信息设计填补空白或深化的问题。
  /// 失败时返回该分类的 1 个默认兜底问题。
  static Future<List<ProfileQuestion>> generateQuestionsForCategory({
    required String category,
    required List<ProfileEntry> existingEntries,
    required String apiKey,
    required String baseUrl,
    required double temperature,
  }) async {
    if (apiKey.isEmpty) return [_defaultQuestion(category)];

    final categoryLabel = ProfileEntry.categoryLabels[category] ?? category;
    final existingLines = existingEntries.isEmpty
        ? '（该分类暂无信息）'
        : existingEntries.map((p) => '${p.key}: ${p.value}').join('\n');

    final systemPrompt =
        '''你是用户画像访谈员。针对「$categoryLabel」分类，根据用户已有的画像信息，设计 1-3 个该分类下的补充问题。
问题应填补空白或深化已有信息，避免重复已有内容。

要求：
1. 问题温暖、口语化、像朋友聊天，不要审问式
2. 用开放式问题，避免是非题（不要问"你喜欢X吗？"，而问"你平时喜欢做什么？"）
3. key 用简短名词短语，如"姓名""年龄""职业""所在地""喜欢的音乐"等
4. 避免过度私密或敏感问题（如收入、政治倾向、宗教信仰等）

返回严格的 JSON 数组（不要 markdown 代码块标记）：
[{"question": "问题文案", "key": "建议的属性名"}]

已有信息：
$existingLines''';

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': '请生成补充问题。'},
    ];

    try {
      final apiService = ApiService.fromConfig(
        model: await ModelListService.getSelectedModel(),
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: false,
        temperature: temperature,
      );
      final response = await apiService.chatCompletion(
        messages: messages,
        tools: [],
      );
      final content = ApiService.parseContent(response);
      if (content == null || content.isEmpty) {
        return [_defaultQuestion(category)];
      }

      final parsed = _parseJsonArray(content);
      if (parsed == null || parsed.isEmpty) return [_defaultQuestion(category)];

      final result = <ProfileQuestion>[];
      for (final item in parsed.take(3)) {
        final q = item['question'] as String?;
        final k = item['key'] as String?;
        if (q != null && q.isNotEmpty && k != null && k.isNotEmpty) {
          result.add(ProfileQuestion(question: q, suggestedKey: k));
        }
      }
      return result.isEmpty ? [_defaultQuestion(category)] : result;
    } catch (e) {
      _plog('generateQuestionsForCategory error: $e');
      return [_defaultQuestion(category)];
    }
  }

  static ProfileQuestion _defaultQuestion(String category) {
    final label = ProfileEntry.categoryLabels[category] ?? category;
    return ProfileQuestion(
      question: '关于 $label，你还有什么想补充的吗？',
      suggestedKey: '补充信息',
    );
  }

  static List<Map<String, dynamic>>? _parseJsonArray(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      try {
        final match = RegExp(
          r'```(?:json)?\s*([\s\S]*?)```',
        ).firstMatch(content);
        if (match != null) {
          final decoded = jsonDecode(match.group(1)!.trim());
          if (decoded is List) return decoded.cast<Map<String, dynamic>>();
        }
      } catch (_) {}
      try {
        final start = content.indexOf('[');
        final end = content.lastIndexOf(']');
        if (start >= 0 && end > start) {
          final decoded = jsonDecode(content.substring(start, end + 1));
          if (decoded is List) return decoded.cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }
    return null;
  }
}

/// AI 生成的画像补充问题。
class ProfileQuestion {
  final String question;
  final String suggestedKey;
  const ProfileQuestion({required this.question, required this.suggestedKey});
}
