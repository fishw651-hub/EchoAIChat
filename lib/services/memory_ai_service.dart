import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'model_list_service.dart';
import 'api_service.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/profile_entry.dart';
import 'memory_service.dart';
import 'plan_service.dart';
import 'user_profile_service.dart';
import 'vision_message_builder.dart';

void _mlog(String msg) {
  debugPrint('[MemoryAI] $msg');
}

/// 读取本地图片并 base64 编码（记忆 AI 挂图用）；
/// 文件缺失/读取失败返回 null，降级为 [图片] 文本占位
Future<String?> _readImageBase64(String imagePath) async {
  try {
    return base64Encode(await File(imagePath).readAsBytes());
  } catch (_) {
    return null;
  }
}

/// 短期消息 map 是否带图：优先 image_paths 列表（多图），回退 image_path 单图
bool _hasImages(Map<String, dynamic> m) {
  final paths = m['image_paths'];
  if (paths is List && paths.isNotEmpty) return true;
  return (m['image_path'] as String?)?.isNotEmpty == true;
}

class MemoryAiService {
  static Future<bool> analyzeAndApply({
    required MemoryService memoryService,
    required PlanService planService,
    required UserProfileService profileService,
    required String agentId,
    required String apiKey,
    required String baseUrl,
    required bool thinkingMode,
    required double temperature,
    required List<Map<String, dynamic>> shortTerm,
    required String persona,
    required List<LongTermMemory> existingLongTerm,
    required List<BaseMemory> existingBase,
    required List<ProfileEntry> existingProfile,
    bool enableProfile = false,
    String worldview = '',
  }) async {
    if (shortTerm.isEmpty || agentId.isEmpty || apiKey.isEmpty) return false;

    final longTermLines = existingLongTerm.isNotEmpty
        ? existingLongTerm.map((m) => m.toPromptLine()).join('\n')
        : '（无长期记忆）';
    final baseLines = existingBase.isNotEmpty
        ? existingBase.map((m) => m.toPromptLine()).join('\n')
        : '（无基础记忆）';
    final profileLines = existingProfile.isNotEmpty
        ? existingProfile
              .map(
                (p) =>
                    '${p.categoryLabel} - ${p.key}: ${p.value}（可信度${p.confidence}%）',
              )
              .join('\n')
        : '（暂无画像信息）';

    // 画像相关部分根据 enableProfile 条件包含
    final profileJsonField = enableProfile
        ? ', "profile": [{"action": "create|update", "category": "basic_info|interests|personality|habits|work_study|preferences|social|health", "key": "属性名", "value": "属性值", "confidence": 0-100}]'
        : '';
    final profileRules = enableProfile
        ? '''

## profile（用户画像）规则
- 从对话中提取对方（用户）的稳定事实，更新用户画像
- 只记录用户明确表达或有直接证据支持的事实；不要把智能体本人的信息归入用户画像，也不要猜测敏感属性
- confidence 根据确定性打分：用户直接说的 90+，间接推断的 50-70，猜测的 <50
- update 操作按 (key, category) 匹配现有画像条目并更新 value 和 confidence；如不存在则改为 create
- 如果用户明确否定或纠正了之前的信息，用 update 更新
- key 用简短的名词短语，如"姓名""年龄""职业""所在地""喜欢的音乐"等
- 可用分类：basic_info（基本信息）、interests（兴趣爱好）、personality（性格特点）、habits（生活习惯）、work_study（工作学习）、preferences（偏好）、social（社交关系）、health（健康状况）
- 如本轮没有值得提取的画像信息，返回空数组 "profile": []'''
        : '';
    final profileSection = enableProfile ? '\n## 现有用户画像\n$profileLines\n' : '';
    // 指令首句的画像要求同样受开关控制，避免诱导模型对未开启画像的智能体返回 profile 操作
    final profileIntro = enableProfile ? '，并提取对方（用户）的画像信息' : '';

    final shortTermLines = shortTerm
        .map((m) {
          final role = m['role'] as String;
          final content = m['content'] as String;
          // 关键：智能体（即"我"）说的话用"我说"，用户（即"对方"）说的话用"对方说"
          return role == 'user' ? '对方（用户）说：$content' : '我（智能体）说：$content';
        })
        .join('\n');

    final worldviewSection = worldview.isNotEmpty
        ? '\n## 世界观\n$worldview\n\n你必须将以上世界观作为所有记忆判断的基准背景。所有人物、事件、地点都必须符合这个世界观。\n'
        : '';

    final systemPrompt =
        '''你是记忆管理器。根据最新对话，判断哪些信息需要记录或清理，为智能体安排未来的计划消息$profileIntro。
你必须返回一个严格的 JSON 对象（不要加 markdown 代码块标记），格式为：
{"long_term": [{"action": "create|update|delete", "field": "time|location|current_events|characters|relationships|goals|thoughts|status|to_do", "content": "具体内容", "target_id": "L003（update/delete时必填）"}], "base": [{"action": "create|delete", "type": "setting|event", "content": "具体内容", "target_id": "B003（delete时必填）"}], "plans": [{"send_time": "30m|2h|ISO8601", "message": "到时间后由智能体发出的消息内容"}]$profileJsonField}
$worldviewSection

## 角色定位（极其重要）
- "我"= 智能体本人（即对话中发出发言的角色），对应 role=assistant
- "对方" / "用户" = 与智能体对话的人，对应 role=user
- 在下方"最新对话"中：
  - "我（智能体）说：xxx" → 这是智能体本人讲的话
  - "对方（用户）说：xxx" → 这是用户讲的话
- 因此，当智能体说"我叫小明"时，小明是智能体的名字；当对方（用户）说"我叫小红"时，小红是用户的名字
- 记忆条目和画像中的"用户"特指对方（与智能体对话的人），不要混淆

## 规则
1. 长期记忆保存目前仍然成立的实时信息（时间、地点、正在发生的事、人物特征、关系、目标、想法情绪、身体/生活状态、待办事项）
2. 基础记忆 setting 保存用户（对方）的背景设定（永久），event 保存已完结的重大事件
3. 当新旧信息冲突时，update 旧条目而非 create 新条目
4. 当信息已过时或被覆盖时，delete 旧条目（不归档——setting 直接删除，event 也直接删除）
5. 长期记忆不超过 15 条；超出时按以下优先级清理：（1）已过时的临时事件 （2）琐碎日常状态 （3）低重要性想法。优先保留：持续成立的人物特征/关系、未完成目标/待办、重大事件
6. 不记录琐碎聊天——只记录真正有长期价值的信息
7. 如果本轮对话没有值得记录的内容，返回空的 long_term 和 base 数组
8. 你只使用 L 和 B 开头的 target_id——不要编造不存在的 ID
9. 区分主语：智能体本人发生的事 vs 对方（用户）发生的事，content 字段中需写清楚是谁的信息
10. 只记录对话明确表达且具有长期价值的事实；不要臆测敏感属性，也不要把智能体的人设当作用户信息

## plan（计划消息）规则
- 当对话中提到未来时间点需要智能体主动联系对方时，安排 plan
- 常见场景：对方提到"明天有个会议"、"待会儿提醒我"、智能体想给对方惊喜问候、节日/生日祝福
- send_time 格式：相对时间（"30m"=30分钟后，"2h"=2小时后）或 ISO 8601（"2026-07-06T09:00:00"）
- message 内容：以智能体第一人称视角撰写（像智能体本人在那时主动发的话）
- 不要为已经过去的事件安排 plan；只为尚未发生的未来时间点安排
- 如本轮没有需要安排的计划，返回空数组 "plans": []
$profileRules

## field 字段说明
- time：当前时间（如"2026年7月5日下午"）
- location：当前地点（需写明主体，如"对方在杭州"或"我在云端"）
- current_events：正在发生的事（需写明主体，如"对方正在准备考试"）
- characters：人物特征——必须写明主体，如"对方：性格开朗"或"我：名字叫小红"
- relationships：人物关系（如"对方把我当朋友"或"对方有个妹妹"）
- goals：目标（需写明主体，如"对方想学钢琴"）
- thoughts：想法情绪（需写明主体，如"对方最近心情低落"）
- status：身体/生活状态（需写明主体，如"对方感冒了"）
- to_do：待办事项（需写明主体，如"对方明天要开会"）

记忆视角：以智能体第一人称视角记录，把对方称为"对方"，把智能体自己称为"我"。

## 现有长期记忆
$longTermLines

## 现有基础记忆
$baseLines$profileSection

## 最新对话
$shortTermLines

## 示例
对话：
对方（用户）说：我今年25岁，在杭州当老师。明天要去上海出差，有点紧张。
我（智能体）说：哇，杭州是个好地方！老师这个职业很伟大呢。出差很辛苦，上海天气怎么样？紧张是正常的，相信你能搞定！

输出：
{"long_term": [{"action": "create", "field": "current_events", "content": "对方明天去上海出差，心情紧张", "target_id": null}], "base": [], "plans": [{"send_time": "2026-07-06T08:30:00", "message": "早上好！今天就要出发去上海啦，记得检查一下行李和身份证哦，加油！"}]$profileJsonField}''';

    // 原生视觉模型（跟随所选模型）：未处理短期消息带图时，把真实图片按时间序
    // 附到 user 消息（最多 maxAttachedImages 张，与聊天上下文共用上限），
    // 记忆 AI 可据此提炼图片相关记忆；非视觉模型保持现状（[图片] 文本占位）
    final selectedModel = await ModelListService.getSelectedModel();
    final modelInfo = ModelListService.findById(
      await ModelListService.loadCached(),
      selectedModel,
    );
    const instructionText =
        '分析以上对话，返回需要执行的记忆操作。返回纯 JSON 对象，不要包装在 markdown 代码块中。';
    Object userContent = instructionText;
    if (modelInfo?.nativeVision == true && shortTerm.any(_hasImages)) {
      final attached = await VisionMessageBuilder.attachImagesToMessages(
        shortTerm,
        nativeVision: true,
        readImageBase64: _readImageBase64,
      );
      final imageParts = <Map<String, dynamic>>[
        for (final m in attached)
          if (m['content'] is List)
            for (final part
                in (m['content'] as List).whereType<Map<String, dynamic>>())
              if (part['type'] == 'image_url') part,
      ];
      if (imageParts.isNotEmpty) {
        userContent = <Map<String, dynamic>>[
          {
            'type': 'text',
            'text':
                '$instructionText（上方"最新对话"里标记 [图片] 的消息，其真实图片按时间顺序附在本消息后面，共 ${imageParts.length} 张；请结合图片内容提炼记忆）',
          },
          ...imageParts,
        ];
      }
    }

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userContent},
    ];

    _mlog('Calling Memory AI ($selectedModel)...');
    final startTime = DateTime.now();

    try {
      final apiService = ApiService.fromConfig(
        model: selectedModel,
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: thinkingMode,
        temperature: temperature,
      );

      final response = await apiService
          .chatCompletion(messages: messages, tools: [])
          .timeout(const Duration(seconds: 45));

      final content = ApiService.parseContent(response);
      if (content == null || content.isEmpty) {
        _mlog('Empty response');
        return false;
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _mlog(
        'Response (${content.length} chars, ${elapsed}ms): ${content.substring(0, _min(120, content.length))}',
      );

      final parsed = _parseJson(content);
      if (parsed == null) {
        _mlog('Failed to parse JSON from response');
        return false;
      }

      if (memoryService.agentId != agentId) {
        _mlog('Discarded stale memory result for agent $agentId');
        return false;
      }
      await _applyOperations(
        parsed,
        memoryService,
        planService,
        profileService,
        agentId,
        enableProfile,
      );
      return true;
    } on ApiException catch (e) {
      _mlog('API error: $e');
    } catch (e) {
      _mlog('Unexpected error: $e');
    }
    return false;
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
    MemoryService ms,
    PlanService ps,
    UserProfileService ups,
    String agentId,
    bool enableProfile,
  ) async {
    int created = 0,
        updated = 0,
        deleted = 0,
        planned = 0,
        profileCreated = 0,
        profileUpdated = 0;

    final longTerm = parsed['long_term'] as List?;
    if (longTerm != null) {
      for (final op in longTerm) {
        if (ms.agentId != agentId) return;
        try {
          final action = op['action'] as String? ?? '';
          final field = op['field'] as String? ?? 'status';
          final content = op['content'] as String? ?? '';
          final targetId = op['target_id'] as String?;

          switch (action) {
            case 'create':
              if (content.isNotEmpty) {
                await ms.createLongTermMemory(field: field, content: content);
                created++;
              }
              break;
            case 'update':
              if (targetId != null && content.isNotEmpty) {
                await ms.updateLongTermMemory(
                  targetId: targetId,
                  content: content,
                  field: field.isNotEmpty ? field : null,
                );
                updated++;
              }
              break;
            case 'delete':
              if (targetId != null) {
                await ms.deleteLongTermMemory(targetId);
                deleted++;
              }
              break;
          }
        } catch (e) {
          _mlog('  LT op failed: $e');
        }
      }
    }

    final base = parsed['base'] as List?;
    if (base != null) {
      for (final op in base) {
        if (ms.agentId != agentId) return;
        try {
          final action = op['action'] as String? ?? '';
          final type = op['type'] as String? ?? 'event';
          final content = op['content'] as String? ?? '';
          final targetId = op['target_id'] as String?;

          switch (action) {
            case 'create':
              if (content.isNotEmpty) {
                await ms.createBaseMemory(type: type, content: content);
                created++;
              }
              break;
            case 'delete':
              if (targetId != null) {
                await ms.deleteBaseMemory(targetId);
                deleted++;
              }
              break;
          }
        } catch (e) {
          _mlog('  BS op failed: $e');
        }
      }
    }

    final plans = parsed['plans'] as List?;
    if (plans != null) {
      for (final op in plans) {
        if (ms.agentId != agentId) return;
        try {
          final sendTime = op['send_time'] as String? ?? '';
          final message = op['message'] as String? ?? '';
          if (sendTime.isNotEmpty && message.isNotEmpty) {
            final scheduledTime = PlanService.parseSendTime(sendTime);
            if (scheduledTime.isAfter(DateTime.now())) {
              await ps.scheduleMessage(
                scheduledTime: scheduledTime,
                message: message,
                agentId: agentId,
              );
              planned++;
            }
          }
        } catch (e) {
          _mlog('  plan op failed: $e');
        }
      }
    }

    // enableProfile=false（未开启真实信息）时忽略模型擅自返回的 profile 操作，杜绝画像写入
    final profile = enableProfile ? parsed['profile'] as List? : null;
    if (profile != null) {
      for (final op in profile) {
        if (ms.agentId != agentId) return;
        try {
          final action = op['action'] as String? ?? '';
          final category = op['category'] as String? ?? '';
          final key = op['key'] as String? ?? '';
          final value = op['value'] as String? ?? '';
          final confidence = (op['confidence'] as num?)?.toInt() ?? 50;
          if (category.isEmpty || key.isEmpty || value.isEmpty) continue;

          switch (action) {
            case 'create':
              await ups.createEntry(
                category: category,
                key: key,
                value: value,
                confidence: confidence,
                source: 'ai_extracted',
              );
              profileCreated++;
              break;
            case 'update':
              final existing = await ups.getEntry(key, category);
              await ups.createEntry(
                category: category,
                key: key,
                value: value,
                confidence: confidence,
                source: 'ai_extracted',
              );
              if (existing != null) {
                profileUpdated++;
              } else {
                profileCreated++;
              }
              break;
          }
        } catch (e) {
          _mlog('  profile op failed: $e');
        }
      }
    }

    _mlog(
      'Applied: created=$created updated=$updated deleted=$deleted planned=$planned profileCreated=$profileCreated profileUpdated=$profileUpdated',
    );
  }

  static int _min(int a, int b) => a < b ? a : b;
}
