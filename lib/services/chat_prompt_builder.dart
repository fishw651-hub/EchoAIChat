import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/agent.dart';
import '../models/base_memory.dart';
import '../models/long_term_memory.dart';
import '../models/profile_entry.dart';
import 'database_service.dart';
import 'real_info_service.dart';

/// 默认人设（无智能体且无基础设定记忆时的兜底）。
const defaultSystemPersona = '''你是{{NAME}}。{{DESCRIPTION}}

你可以用小括号表达动作或表情，例如（轻轻叹气）（笑着看你）。

永远不要出现"已记住""已遗忘""根据记忆""作为AI"等机械表达。记忆更新在后台完成，你只需自然地回应。把记忆信息自然融入对话。''';

const privateChatToolPolicy = '''
## 工具使用
- 普通回复使用 chat 工具发送最终自然语言内容。
- 用户要求未来提醒时调用 plan 工具，并可同时调用 chat 工具确认已经安排。
- 不需要未来提醒时不得调用 plan。
- 记忆更新由独立的记忆服务负责，不要调用未提供的记忆工具。
''';

/// 长期记忆读取器：注入而非直接调 MemoryService，保持可单元测试。
typedef LongTermMemoriesReader = Future<List<LongTermMemory>> Function();

/// 基础记忆读取器。
typedef BaseMemoriesReader = Future<List<BaseMemory>> Function();

/// 真实信息（环境信息）采集器，默认 [RealInfoService.collectAll]。
typedef RealInfoReader = Future<Map<String, String>> Function();

/// 用户画像条目读取器，默认 [DatabaseService.getProfileEntries]。
typedef ProfileEntriesReader = Future<List<ProfileEntry>> Function();

/// 日志输出（默认走 debugPrint，测试可注入 no-op）。
typedef ChatPromptLogger = void Function(String message);

void _defaultLog(String msg) {
  debugPrint('║ $msg');
}

/// 私聊系统提示词构建（从 ChatNotifier 抽取的纯组串逻辑）。
///
/// 所有 IO（记忆列表 / 真实信息 / 用户画像）都通过 typedef 注入，
/// 本类只做字符串组装与降级策略：
/// - 整体构建超时/异常 → [buildFallback]（无人格画像、无记忆的精简版）
/// - 单份记忆列表读取失败 → 该份按空列表处理（"（暂无…条目）"占位）
class ChatPromptBuilder {
  ChatPromptBuilder({
    Duration memoryTimeout = const Duration(seconds: 2),
    RealInfoReader? readRealInfo,
    ProfileEntriesReader? readProfileEntries,
    ChatPromptLogger log = _defaultLog,
  }) : _memoryTimeout = memoryTimeout,
       _readRealInfo = readRealInfo ?? RealInfoService.collectAll,
       _readProfileEntries =
           readProfileEntries ?? DatabaseService.getProfileEntries,
       _log = log;

  final Duration _memoryTimeout;
  final RealInfoReader _readRealInfo;
  final ProfileEntriesReader _readProfileEntries;
  final ChatPromptLogger _log;

  /// 构建完整系统提示词。超时或任何异常时降级为 [buildFallback]。
  Future<String> build({
    required LongTermMemoriesReader readLongTerm,
    required BaseMemoriesReader readBase,
    Agent? agent,
  }) async {
    try {
      return await _buildUnsafe(
        readLongTerm: readLongTerm,
        readBase: readBase,
        agent: agent,
      ).timeout(_memoryTimeout);
    } catch (e) {
      _log('Build system prompt degraded without memories: $e');
      return buildFallback(agent);
    }
  }

  Future<String> _buildUnsafe({
    required LongTermMemoriesReader readLongTerm,
    required BaseMemoriesReader readBase,
    Agent? agent,
  }) async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final weekStr = weekdays[now.weekday - 1];

    final longTermFuture = _readMemoryList('long-term memories', readLongTerm);
    final baseFuture = _readMemoryList('base memories', readBase);
    final longTermMemories = await longTermFuture;
    final baseMemories = await baseFuture;
    String persona;
    if (agent != null) {
      persona = agent.persona
          .replaceAll('{{NAME}}', agent.name)
          .replaceAll('{{GENDER}}', agent.gender)
          .replaceAll('{{DESCRIPTION}}', agent.description);
    } else {
      final personaLines = baseMemories
          .where((m) => m.isSetting)
          .map((m) => m.content)
          .join('\n');
      persona = personaLines.isNotEmpty ? personaLines : defaultSystemPersona;
    }

    final longTermPrompt = longTermMemories.isNotEmpty
        ? longTermMemories.map((m) => m.toPromptLine()).join('\n')
        : '（暂无长期记忆条目）';
    final basePrompt = baseMemories.isNotEmpty
        ? baseMemories.map((m) => m.toPromptLine()).join('\n')
        : '（暂无基础记忆条目）';

    final worldview = agent?.worldview ?? '';
    final worldviewSection = worldview.isNotEmpty
        ? '''

## 世界观
$worldview

你必须严格遵守以上世界观设定。你的所有言行、记忆和理解都必须基于这个世界观。\n'''
        : '';
    final responseLength =
        agent?.maxResponseLength ?? Agent.defaultResponseLength;
    final responseLengthSection =
        '''

## 回复长度
- 每次回复尽量控制在不超过 $responseLength 个字以内。
- 优先保证内容完整、自然，不要为了凑字数重复或截断句子。
''';

    var realInfoSection = '';
    var userProfileSection = '';
    if (agent?.realInfoEnabled == true) {
      final realInfo = await _readRealInfo();
      realInfoSection = '\n${RealInfoService.formatPrompt(realInfo)}\n';

      // 注入用户人格画像数据，让 AI 真正"了解"用户
      try {
        final profileEntries = await _readProfileEntries();
        if (profileEntries.isNotEmpty) {
          // 按分类分组，按可信度降序排序，每分类最多取 5 条
          final grouped = <String, List<ProfileEntry>>{};
          for (final e in profileEntries) {
            grouped.putIfAbsent(e.category, () => []).add(e);
          }
          final buf = StringBuffer('\n## 用户画像\n');
          buf.writeln(
            '以下是系统通过对话自动总结的关于用户的信息，请自然地参考这些信息来理解用户。低可信度条目仅作参考；不确定时请向用户确认，不要把它当作事实断言。',
          );
          for (final cat in ProfileEntry.validCategories) {
            final list = grouped[cat];
            if (list == null || list.isEmpty) continue;
            list.sort((a, b) => b.confidence.compareTo(a.confidence));
            final label = ProfileEntry.categoryLabels[cat] ?? cat;
            final icon = ProfileEntry.categoryIcons[cat] ?? '📌';
            buf.writeln('### $icon $label');
            for (final e in list.take(5)) {
              buf.writeln('- ${e.key}: ${e.value}（可信度${e.confidence}%）');
            }
          }
          userProfileSection = '\n${buf.toString()}\n';
        }
      } catch (e) {
        _log('Load profile entries for prompt failed: $e');
      }
    }

    var prompt =
        '''【当前真实时间】$timeStr（星期$weekStr）

$persona
$worldviewSection
$responseLengthSection
$realInfoSection$userProfileSection
## 角色定位（极其重要）
- "你" = 智能体本人（即对话中发出回复的角色）
- "用户" / "对方" = 与你对话的人
- 当用户说"我叫小明"时，小明是用户的名字；当你（智能体）说"我叫小红"时，小红是你的名字

## 你的记忆
你的长期和基础记忆由系统自动管理，你只需参考它们来了解用户。这些记忆会在对话中自然更新，你不需要主动维护。

【长期记忆】
$longTermPrompt

【基础记忆】
$basePrompt

## 对话风格
- 严格按照设定中的人设说话。
- 把记忆中的信息自然地融入对话。
- 回复温暖、松弛，像个真人，而不是解决问题的人工智能。
$privateChatToolPolicy''';

    _log(
      'PROMPT ASSERT | agent=${agent?.id ?? '(none)'} memories LT=${longTermMemories.length} BM=${baseMemories.length} prompt=${prompt.length}chars',
    );

    return prompt;
  }

  Future<List<T>> _readMemoryList<T>(
    String label,
    Future<List<T>> Function() loader,
  ) async {
    try {
      return await loader().timeout(_memoryTimeout);
    } catch (e) {
      _log('Load $label failed; using empty context: $e');
      return <T>[];
    }
  }

  /// 精简版提示词：主构建失败（超时/异常）时的降级结果。
  String buildFallback(Agent? agent) {
    final persona = agent == null
        ? defaultSystemPersona
        : agent.persona
              .replaceAll('{{NAME}}', agent.name)
              .replaceAll('{{GENDER}}', agent.gender)
              .replaceAll('{{DESCRIPTION}}', agent.description);
    final worldview = agent?.worldview.trim() ?? '';
    final worldviewSection = worldview.isEmpty ? '' : '\n## 世界观\n$worldview\n';
    final responseLength =
        agent?.maxResponseLength ?? Agent.defaultResponseLength;
    return '''$persona
$worldviewSection
## 回复长度
- 每次回复尽量控制在不超过 $responseLength 个字以内。
- 优先保证内容完整、自然，不要为了凑字数重复或截断句子。

## 角色定位（极其重要）
- "你" = 智能体本人（即对话中发出回复的角色）
- "用户" / "对方" = 与你对话的人

## 对话风格
- 严格按照设定中的人设说话。
- 回复温暖、松弛，像个真人，而不是解决问题的人工智能。
$privateChatToolPolicy''';
  }
}
