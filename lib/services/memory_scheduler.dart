import 'package:shared_preferences/shared_preferences.dart';

import '../models/base_memory.dart';
import '../models/long_term_memory.dart';
import '../models/profile_entry.dart';
import 'database_service.dart';
import 'memory_ai_service.dart';
import 'memory_analysis_coordinator.dart';
import 'memory_service.dart';
import 'plan_service.dart';
import 'user_profile_service.dart';

/// 作用域 MemoryService 工厂：按 agentId 建独立实例（默认 `MemoryService()..setAgentId`）。
typedef MemoryScopedServiceFactory = MemoryService Function(String agentId);

/// 未处理短期消息读取器（默认 [DatabaseService.getUnprocessedShortTermMessages]）。
typedef UnprocessedShortTermReader =
    Future<List<Map<String, dynamic>>> Function(String agentId);

/// 短期消息标记已处理器（默认 [DatabaseService.markShortTermMessagesProcessed]）。
typedef ShortTermProcessedMarker = Future<void> Function(List<String> ids);

/// 画像条目读取器（默认 [DatabaseService.getProfileEntries]）。
typedef ProfileEntriesLoader = Future<List<ProfileEntry>> Function();

/// 记忆 AI 分析执行器（默认 [MemoryAiService.analyzeAndApply]）。
typedef MemoryAiAnalyze =
    Future<bool> Function({
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
      bool enableProfile,
      String worldview,
    });

/// 记忆 AI 调度（从 ChatNotifier 抽取）：触发条件计数、并发保护、
/// 调用 Memory AI 的编排。IO 全部经 typedef 注入，可单元测试。
///
/// 触发条件：每 [roundsInterval] 轮对话触发一次，轮次持久化到
/// SharedPreferences（key: `memory_ai_rounds_<agentId>`）；
/// 并发保护由 [MemoryAnalysisCoordinator] 提供（同智能体在途任务去重）。
class MemoryAiScheduler {
  MemoryAiScheduler({
    required MemoryAnalysisCoordinator coordinator,
    required PlanService Function() planService,
    required UserProfileService Function() profileService,
    MemoryScopedServiceFactory? memoryServiceFactory,
    UnprocessedShortTermReader? readUnprocessed,
    ShortTermProcessedMarker? markProcessed,
    ProfileEntriesLoader? readProfileEntries,
    MemoryAiAnalyze? analyze,
  }) : _coordinator = coordinator,
       _planService = planService,
       _profileService = profileService,
       _memoryServiceFactory =
           memoryServiceFactory ?? _defaultMemoryServiceFactory,
       _readUnprocessed =
           readUnprocessed ?? DatabaseService.getUnprocessedShortTermMessages,
       _markProcessed =
           markProcessed ?? DatabaseService.markShortTermMessagesProcessed,
       _readProfileEntries =
           readProfileEntries ?? DatabaseService.getProfileEntries,
       _analyze = analyze ?? MemoryAiService.analyzeAndApply;

  static const int roundsInterval = 10;

  static String roundsKey(String agentId) => 'memory_ai_rounds_$agentId';

  final MemoryAnalysisCoordinator _coordinator;
  final PlanService Function() _planService;
  final UserProfileService Function() _profileService;
  final MemoryScopedServiceFactory _memoryServiceFactory;
  final UnprocessedShortTermReader _readUnprocessed;
  final ShortTermProcessedMarker _markProcessed;
  final ProfileEntriesLoader _readProfileEntries;
  final MemoryAiAnalyze _analyze;

  static MemoryService _defaultMemoryServiceFactory(String agentId) =>
      MemoryService()..setAgentId(agentId);

  /// 累加当前 agent 对话轮次，达到 [roundsInterval] 的倍数返回 true。
  Future<bool> shouldRunMemoryAi(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = roundsKey(agentId);
    final rounds = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, rounds);
    return rounds % roundsInterval == 0;
  }

  /// 重置触发计数器（清空聊天后对话轮次从头计起）。
  Future<void> resetRounds(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(roundsKey(agentId));
  }

  /// 主回复落库后调度记忆分析（后台执行，不占聊天 isLoading 生命周期）。
  ///
  /// [onApplied] 在分析成功且短期消息标记已处理后回调（用于当前智能体
  /// 的界面刷新）；调用方需自行处理容器已销毁的 StateError。
  void schedule({
    required String agentId,
    required String apiKey,
    required String baseUrl,
    required double temperature,
    required String persona,
    required String worldview,
    required bool enableProfile,
    Future<void> Function(String agentId)? onApplied,
  }) {
    _coordinator.schedule(agentId, () async {
      if (!await shouldRunMemoryAi(agentId)) return;

      final memoryService = _memoryServiceFactory(agentId);
      final unprocessed = await _readUnprocessed(agentId);
      if (unprocessed.isEmpty) return;

      final unprocessedIds = unprocessed
          .map((message) => message['id'] as String)
          .toList(growable: false);
      final existingLongTerm = await memoryService.getLongTermMemories();
      final existingBase = await memoryService.getBaseMemories();
      final existingProfile = enableProfile
          ? await _readProfileEntries()
          : <ProfileEntry>[];

      final success = await _analyze(
        memoryService: memoryService,
        planService: _planService(),
        profileService: _profileService(),
        agentId: agentId,
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: false,
        temperature: temperature,
        shortTerm: unprocessed,
        persona: persona,
        existingLongTerm: existingLongTerm,
        existingBase: existingBase,
        existingProfile: existingProfile,
        enableProfile: enableProfile,
        worldview: worldview,
      );
      if (!success) return;

      await _markProcessed(unprocessedIds);
      await onApplied?.call(agentId);
    });
  }
}
