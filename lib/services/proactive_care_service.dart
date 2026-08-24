import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'model_list_service.dart';

import '../config/server_config.dart';
import '../models/agent.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'memory_service.dart';
import 'notification_service.dart';
import 'proactive_care_store.dart';
import 'quota_service.dart';
import 'real_info_service.dart';
import 'secure_session_store.dart';

/// 清醒窗口（分钟数，0–1439）
class AwakeWindow {
  const AwakeWindow(this.startMinutes, this.endMinutes);

  final int startMinutes;
  final int endMinutes;

  /// 默认关心窗口：8:00–20:00
  static const fallback = AwakeWindow(8 * 60, 20 * 60);

  bool contains(DateTime t) {
    final m = t.hour * 60 + t.minute;
    return m >= startMinutes && m < endMinutes;
  }

  @override
  String toString() => 'AwakeWindow($startMinutes-$endMinutes)';
}

/// 主动关心纯逻辑（可单测，不依赖 Flutter 插件）
class ProactiveCarePolicy {
  ProactiveCarePolicy._();

  /// 主动关心也遵循智能体编辑页设置的回复长度。
  static String responseLengthGuidance(int maxResponseLength) {
    final normalized = Agent.normalizeResponseLength(maxResponseLength);
    return '自然简短（${normalized}字以内），就像真人随手发的一条消息。';
  }

  static bool hasUserReplied({
    required DateTime pendingSince,
    required DateTime? latestUserMessageTime,
  }) {
    return latestUserMessageTime != null &&
        latestUserMessageTime.isAfter(pendingSince);
  }

  /// 从画像 habits 文本（key/value 拼接）尽力解析清醒窗口。
  /// 支持形式："23:30睡 7点起"、"7:00-23:00"、"晚上11点睡，早上7点起床" 等。
  /// 只解析成功的一侧用解析值，另一侧用默认值；完全失败回退默认窗口。
  static AwakeWindow parseAwakeWindow(Iterable<String> texts) {
    var start = AwakeWindow.fallback.startMinutes;
    var end = AwakeWindow.fallback.endMinutes;
    var parsedStart = false;
    var parsedEnd = false;

    final joined = texts.where((t) => t.trim().isNotEmpty).join('；');
    if (joined.isEmpty) return AwakeWindow.fallback;

    // 区间形式："7:00-23:00"、"7点-23点"、"8:00~22:30"
    final rangeRe = RegExp(
      r'(\d{1,2})(?::(\d{1,2}))?\s*点?\s*[-~—–至到]\s*(\d{1,2})(?::(\d{1,2}))?\s*点?',
    );
    final rangeMatch = rangeRe.firstMatch(joined);
    if (rangeMatch != null) {
      final sh = int.parse(rangeMatch.group(1)!);
      final sm = int.tryParse(rangeMatch.group(2) ?? '') ?? 0;
      final eh = int.parse(rangeMatch.group(3)!);
      final em = int.tryParse(rangeMatch.group(4) ?? '') ?? 0;
      final s = _clampWake(sh * 60 + sm);
      final e = _clampSleep(_normalizeSleepHour(eh) * 60 + em);
      if (s != null && e != null && e > s) {
        start = s;
        end = e;
        parsedStart = parsedEnd = true;
      }
    }

    if (!parsedStart) {
      // 起床形式："7点起"、"7:30起床"、"早上6点半起"
      final wakeRe = RegExp(
        r'(\d{1,2})(?::(\d{1,2}))?\s*点?\s*半?\s*(?:起床|起来|起)(?!\w)',
      );
      final m = wakeRe.firstMatch(joined);
      if (m != null) {
        var h = int.parse(m.group(1)!);
        var min = int.tryParse(m.group(2) ?? '') ?? 0;
        if (joined.substring(0, m.end).contains('半') &&
            m.group(2) == null &&
            RegExp(r'点半').hasMatch(joined)) {
          min = 30;
        }
        final s = _clampWake(h * 60 + min);
        if (s != null) {
          start = s;
          parsedStart = true;
        }
      }
    }

    if (!parsedEnd) {
      // 睡觉形式："23:30睡"、"11点睡觉"、"凌晨1点睡"
      final sleepRe = RegExp(
        r'(\d{1,2})(?::(\d{1,2}))?\s*点?\s*(?:睡觉|入睡|睡)(?!\w|前)',
      );
      final m = sleepRe.firstMatch(joined);
      if (m != null) {
        final h = int.parse(m.group(1)!);
        final min = int.tryParse(m.group(2) ?? '') ?? 0;
        final e = _clampSleep(_normalizeSleepHour(h) * 60 + min);
        if (e != null) {
          end = e;
          parsedEnd = true;
        }
      }
    }

    if (!parsedStart && !parsedEnd) return AwakeWindow.fallback;
    if (end <= start) return AwakeWindow.fallback;
    return AwakeWindow(start, end);
  }

  /// 睡眠时间归一化：6–11 点视为晚上（+12），0–5 点视为凌晨
  static int _normalizeSleepHour(int h) => (h >= 6 && h <= 11) ? h + 12 : h;

  /// 起床窗口合法范围：04:00–12:00
  static int? _clampWake(int minutes) {
    if (minutes < 4 * 60 || minutes > 12 * 60) return null;
    return minutes;
  }

  /// 睡觉窗口合法范围：17:00–24:00 或 00:00–05:00（凌晨归一到 24h+ 不支持，取 23:59 上限）
  static int? _clampSleep(int minutes) {
    if (minutes >= 24 * 60) return null;
    if (minutes < 5 * 60) return null; // 凌晨睡太反常，视为解析错误
    if (minutes < 17 * 60) return null;
    return minutes;
  }
}

/// AI 主动关心服务：检查触发条件 → 走服务器中继生成 → 写库 → 通知。
/// 不依赖 Riverpod，前台与后台 isolate（alarm 回调）均可运行。
class ProactiveCareService {
  ProactiveCareService._();
  static final ProactiveCareService instance = ProactiveCareService._();

  /// 单航班防重入（前台 + alarm isolate 各自进程内互斥）
  static bool _running = false;

  /// 主动关心消息落库后的回调（前台用于刷新聊天 UI），由 main.dart 注册
  void Function(String agentId)? onMessageDelivered;

  NotificationService? _notificationService;

  /// 注入通知服务（前台用 main.dart 全局实例；后台 isolate 自建）
  set notificationService(NotificationService service) =>
      _notificationService = service;

  /// 后台 isolate 入口：自行恢复鉴权并执行一轮检查。
  /// 任何失败静默降级——后台失败留给前台补发。
  static Future<void> runBackgroundCheck() async {
    try {
      // 后台 isolate 中没有 authProvider，从 secure storage 恢复 JWT 注入配额服务
      final session = await SecureSessionStore().read();
      final jwt = session?.jwtToken;
      if (jwt != null && jwt.isNotEmpty) {
        QuotaService.instance.authHeaderProvider = () => <String, String>{
          'Authorization': 'Bearer $jwt',
        };
        QuotaService.instance.cacheOwnerProvider = () => session?.username;
      }
      await instance.checkAndTrigger();
    } catch (e) {
      debugPrint('[ProactiveCare] background check failed: $e');
    }
  }

  /// 执行一轮检查（单航班）。返回本次成功主动发送的智能体 id 列表。
  Future<List<String>> checkAndTrigger() async {
    if (_running) return const [];
    _running = true;
    try {
      return await _checkAndTriggerInner();
    } finally {
      _running = false;
    }
  }

  Future<List<String>> _checkAndTriggerInner() async {
    final delivered = <String>[];
    List<Agent> agents;
    try {
      agents = await DatabaseService.getAgents();
    } catch (e) {
      // 后台 isolate 中 sqflite 可能不可用，静默降级
      debugPrint('[ProactiveCare] load agents failed: $e');
      return delivered;
    }
    final candidates = agents.where(
      (a) => a.realInfoEnabled && a.proactiveCareEnabled && !a.isGroupOnly,
    );
    if (candidates.isEmpty) return delivered;

    // 清醒窗口：默认 8:00–20:00，按画像 habits 作息微调
    final window = await _resolveAwakeWindow();
    final now = DateTime.now();
    if (!window.contains(now)) return delivered;

    // 缓存窗口供 alarm 调度使用
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('proactive_care_window_start', window.startMinutes);
      await prefs.setInt('proactive_care_window_end', window.endMinutes);
    } catch (_) {}

    final apiKey = await _resolveApiKey();
    if (apiKey == null || apiKey.isEmpty) return delivered;

    for (final agent in candidates) {
      try {
        final sent = await _trySendForAgent(agent, now, apiKey);
        if (sent) delivered.add(agent.id);
      } catch (e) {
        debugPrint('[ProactiveCare] agent ${agent.id} failed: $e');
      }
    }
    return delivered;
  }

  Future<AwakeWindow> _resolveAwakeWindow() async {
    try {
      final entries = await DatabaseService.getProfileEntriesByCategory(
        'habits',
      );
      final texts = <String>[];
      for (final e in entries) {
        if (e.key.contains('作息') ||
            e.key.contains('起床') ||
            e.key.contains('睡觉') ||
            e.key.contains('睡眠')) {
          texts.add(e.key);
          texts.add(e.value);
        }
      }
      if (texts.isEmpty) return AwakeWindow.fallback;
      return ProactiveCarePolicy.parseAwakeWindow(texts);
    } catch (_) {
      return AwakeWindow.fallback;
    }
  }

  /// 前台优先用 authProvider 注入的 key 不可得时，回退 secure storage
  Future<String?> _resolveApiKey() async {
    try {
      final session = await SecureSessionStore().read();
      final key = session?.apiKey ?? session?.jwtToken;
      if (key != null && key.isNotEmpty) return key;
    } catch (_) {}
    return null;
  }

  Future<bool> _trySendForAgent(
    Agent agent,
    DateTime now,
    String apiKey,
  ) async {
    final db = await DatabaseService.database;
    final store = ProactiveCareStore(db);
    final claim = await store.claim(
      agentId: agent.id,
      now: now,
      dailyLimit: agent.proactiveCareDailyLimit,
      minIntervalHours: agent.proactiveCareMinIntervalHours,
    );
    if (claim == null) return false;

    String? serverClaimToken;
    var committed = false;
    try {
      serverClaimToken = await QuotaService.instance.claimProactiveCare(
        agent.id,
      );

      final content = await _generateProactiveMessage(
        agent,
        apiKey,
        proactiveClaimToken: serverClaimToken,
      );
      if (content == null || content.isEmpty) return false;

      committed = await store.commit(
        claim,
        content: content,
        sentAt: DateTime.now(),
      );
      if (!committed) return false;

      await _notify(agent, content);
      onMessageDelivered?.call(agent.id);
      return true;
    } finally {
      if (!committed) {
        try {
          await store.release(claim);
        } finally {
          if (serverClaimToken != null) {
            await QuotaService.instance.releaseProactiveCare(serverClaimToken);
          }
        }
      }
    }
  }

  Future<String?> _generateProactiveMessage(
    Agent agent,
    String apiKey, {
    required String proactiveClaimToken,
  }) async {
    final systemPrompt = await _buildProactiveSystemPrompt(agent);

    // 近期对话上下文（只读，不写入触发消息）
    final memoryService = MemoryService()..setAgentId(agent.id);
    await memoryService.loadShortTermFromDb(10);
    final context = memoryService.shortTermMessages
        .map((m) => <String, dynamic>{'role': m.role, 'content': m.content})
        .toList();

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...context,
      {'role': 'user', 'content': '（系统事件：一段时间没有对话了，现在由你主动发一条消息）'},
    ];
    apiMessages[0]['agent_id'] = agent.id;

    final apiService = ApiService.fromConfig(
      model: await ModelListService.getSelectedModel(),
      apiKey: apiKey,
      baseUrl: ServerConfig.baseUrl,
      thinkingMode: false,
      temperature: 1.0,
      clientAgentId: agent.id,
      requestKind: 'proactive_care',
      proactiveClaimToken: proactiveClaimToken,
    );
    final response = await apiService.chatCompletion(
      messages: apiMessages,
      tools: const [],
    );

    // token 用量记录（与聊天路径一致）
    final usage = response['usage'] as Map<String, dynamic>?;
    if (usage != null) {
      final prompt = usage['prompt_tokens'] as int?;
      final completion = usage['completion_tokens'] as int?;
      if (prompt != null && completion != null) {
        try {
          await DatabaseService.insertTokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            model: response['model'] as String?,
            agentId: agent.id,
          );
        } catch (_) {}
      }
    }

    final content = ApiService.parseContent(response)?.trim();
    return (content == null || content.isEmpty) ? null : content;
  }

  Future<String> _buildProactiveSystemPrompt(Agent agent) async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final weekStr = weekdays[now.weekday - 1];

    final persona = agent.persona
        .replaceAll('{{NAME}}', agent.name)
        .replaceAll('{{GENDER}}', agent.gender)
        .replaceAll('{{DESCRIPTION}}', agent.description);

    final buf = StringBuffer('【当前真实时间】$timeStr（星期$weekStr）\n\n');
    buf.writeln(persona);
    if (agent.worldview.isNotEmpty) {
      buf.writeln('\n## 世界观\n${agent.worldview}\n');
      buf.writeln('你必须严格遵守以上世界观设定。你的所有言行都必须基于这个世界观。');
    }

    // 真实环境信息（后台 isolate 中插件可能不可用，失败静默跳过）
    try {
      final realInfo = await RealInfoService.collectAll();
      buf.writeln('\n${RealInfoService.formatPrompt(realInfo)}\n');
    } catch (_) {}

    // 用户画像摘要
    try {
      final entries = await DatabaseService.getProfileEntries();
      if (entries.isNotEmpty) {
        buf.writeln('\n## 用户画像');
        for (final e in entries.take(20)) {
          buf.writeln('- ${e.key}: ${e.value}');
        }
      }
    } catch (_) {}

    buf.writeln('''
## 角色定位（极其重要）
- "你" = 智能体本人（即对话中发出消息的角色）
- "用户" / "对方" = 与你对话的人

## 主动关心
现在由你主动开启对话。用户有一段时间没有和你聊天了。从以下方式中自然选择其一：
1. 表达对用户的关心（可结合你了解到的作息、习惯、近况）；
2. 按你的世界观/人设，报备你刚才在做什么；
3. 分享一件你想分享的事。
要求：第一人称、完全符合人设、${ProactiveCarePolicy.responseLengthGuidance(agent.maxResponseLength)}
直接输出消息内容，不要解释，不要使用任何工具。''');
    return buf.toString();
  }

  Future<void> _notify(Agent agent, String content) async {
    try {
      var service = _notificationService;
      if (service == null) {
        service = NotificationService();
        await service.initialize();
      }
      // 头像大图标：文件存在才用
      String? avatarPath;
      if (!kIsWeb &&
          agent.avatarPath != null &&
          agent.avatarPath!.isNotEmpty &&
          File(agent.avatarPath!).existsSync()) {
        avatarPath = agent.avatarPath;
      }
      await service.showProactiveCareNotification(
        id: agent.id.hashCode & 0x7fffffff,
        agentName: agent.name,
        message: content,
        avatarPath: avatarPath,
        payload: 'proactive:${agent.id}',
      );
    } catch (e) {
      debugPrint('[ProactiveCare] notify failed: $e');
    }
  }
}
