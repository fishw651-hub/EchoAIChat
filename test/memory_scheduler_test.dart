import 'package:aichat/models/base_memory.dart';
import 'package:aichat/models/long_term_memory.dart';
import 'package:aichat/models/profile_entry.dart';
import 'package:aichat/services/memory_analysis_coordinator.dart';
import 'package:aichat/services/memory_scheduler.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:aichat/services/notification_service.dart';
import 'package:aichat/services/plan_service.dart';
import 'package:aichat/services/user_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMemoryService extends MemoryService {
  _FakeMemoryService({this.longTerm = const [], this.base = const []});

  final List<LongTermMemory> longTerm;
  final List<BaseMemory> base;

  @override
  Future<List<LongTermMemory>> getLongTermMemories() async => longTerm;

  @override
  Future<List<BaseMemory>> getBaseMemories() async => base;
}

class _AnalyzeCall {
  String? agentId;
  String? apiKey;
  String? baseUrl;
  double? temperature;
  String? persona;
  String? worldview;
  bool? enableProfile;
  List<Map<String, dynamic>>? shortTerm;
  List<LongTermMemory>? existingLongTerm;
  List<BaseMemory>? existingBase;
  List<ProfileEntry>? existingProfile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryAnalysisCoordinator coordinator;
  late _FakeMemoryService memoryService;
  late List<Map<String, dynamic>> unprocessed;
  late List<String> markedIds;
  late List<ProfileEntry> profileEntries;
  late _AnalyzeCall analyzeCall;
  late int analyzeCount;
  late bool analyzeResult;
  late List<String> appliedAgentIds;

  MemoryAiScheduler buildScheduler() {
    return MemoryAiScheduler(
      coordinator: coordinator,
      planService: () =>
          PlanService(notificationService: NotificationService()),
      profileService: () => UserProfileService(),
      memoryServiceFactory: (_) => memoryService,
      readUnprocessed: (_) async => unprocessed,
      markProcessed: (ids) async => markedIds.addAll(ids),
      readProfileEntries: () async => profileEntries,
      analyze:
          ({
            required memoryService,
            required planService,
            required profileService,
            required agentId,
            required apiKey,
            required baseUrl,
            required thinkingMode,
            required temperature,
            required shortTerm,
            required persona,
            required existingLongTerm,
            required existingBase,
            required existingProfile,
            enableProfile = false,
            worldview = '',
          }) async {
            analyzeCount++;
            analyzeCall
              ..agentId = agentId
              ..apiKey = apiKey
              ..baseUrl = baseUrl
              ..temperature = temperature
              ..persona = persona
              ..worldview = worldview
              ..enableProfile = enableProfile
              ..shortTerm = shortTerm
              ..existingLongTerm = existingLongTerm
              ..existingBase = existingBase
              ..existingProfile = existingProfile;
            return analyzeResult;
          },
    );
  }

  void scheduleDefault(MemoryAiScheduler scheduler, {String agentId = 'a1'}) {
    scheduler.schedule(
      agentId: agentId,
      apiKey: 'key-123',
      baseUrl: 'https://example.test',
      temperature: 1.3,
      persona: '你是小红',
      worldview: '末世',
      enableProfile: false,
      onApplied: (id) async => appliedAgentIds.add(id),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    coordinator = MemoryAnalysisCoordinator();
    memoryService = _FakeMemoryService(
      longTerm: [LongTermMemory(id: 'L-1', field: '喜好', content: '草莓')],
      base: [BaseMemory(id: 'B-1', type: 'setting', content: '夜猫子')],
    );
    unprocessed = [
      {'id': 's1', 'role': 'user', 'content': '你好'},
      {'id': 's2', 'role': 'assistant', 'content': '你好呀'},
    ];
    markedIds = [];
    profileEntries = [];
    analyzeCall = _AnalyzeCall();
    analyzeCount = 0;
    analyzeResult = true;
    appliedAgentIds = [];
  });

  group('MemoryAiScheduler.shouldRunMemoryAi 触发计数', () {
    test('第 1-9 轮 false，第 10 轮 true，之后重新计数', () async {
      final scheduler = buildScheduler();
      for (var i = 1; i <= 9; i++) {
        expect(
          await scheduler.shouldRunMemoryAi('a1'),
          isFalse,
          reason: '第 $i 轮',
        );
      }
      expect(await scheduler.shouldRunMemoryAi('a1'), isTrue);
      expect(await scheduler.shouldRunMemoryAi('a1'), isFalse);
    });

    test('计数按 agentId 隔离', () async {
      final scheduler = buildScheduler();
      for (var i = 1; i <= 9; i++) {
        await scheduler.shouldRunMemoryAi('a1');
      }
      // a2 从头计起，不受 a1 影响
      expect(await scheduler.shouldRunMemoryAi('a2'), isFalse);
      expect(await scheduler.shouldRunMemoryAi('a1'), isTrue);
    });

    test('resetRounds 后计数从头开始', () async {
      final scheduler = buildScheduler();
      for (var i = 1; i <= 9; i++) {
        await scheduler.shouldRunMemoryAi('a1');
      }
      await scheduler.resetRounds('a1');
      expect(await scheduler.shouldRunMemoryAi('a1'), isFalse);
    });
  });

  group('MemoryAiScheduler.schedule 编排', () {
    test('未满 10 轮不调用记忆 AI', () async {
      final scheduler = buildScheduler();
      scheduleDefault(scheduler);
      await coordinator.waitForIdle('a1');
      expect(analyzeCount, 0);
      expect(markedIds, isEmpty);
      expect(appliedAgentIds, isEmpty);
    });

    test('第 10 轮触发：读取未处理消息与既有记忆，成功后标记已处理并回调', () async {
      final scheduler = buildScheduler();
      SharedPreferences.setMockInitialValues({
        MemoryAiScheduler.roundsKey('a1'): 9,
      });
      scheduleDefault(scheduler);
      await coordinator.waitForIdle('a1');

      expect(analyzeCount, 1);
      expect(analyzeCall.agentId, 'a1');
      expect(analyzeCall.apiKey, 'key-123');
      expect(analyzeCall.baseUrl, 'https://example.test');
      expect(analyzeCall.temperature, 1.3);
      expect(analyzeCall.persona, '你是小红');
      expect(analyzeCall.worldview, '末世');
      expect(analyzeCall.enableProfile, isFalse);
      expect(analyzeCall.shortTerm, unprocessed);
      expect(analyzeCall.existingLongTerm!.single.id, 'L-1');
      expect(analyzeCall.existingBase!.single.id, 'B-1');
      // enableProfile=false：画像为空且不读取
      expect(analyzeCall.existingProfile, isEmpty);
      expect(markedIds, ['s1', 's2']);
      expect(appliedAgentIds, ['a1']);
    });

    test('无未处理短期消息时不调用记忆 AI', () async {
      unprocessed = [];
      final scheduler = buildScheduler();
      SharedPreferences.setMockInitialValues({
        MemoryAiScheduler.roundsKey('a1'): 9,
      });
      scheduleDefault(scheduler);
      await coordinator.waitForIdle('a1');
      expect(analyzeCount, 0);
      expect(markedIds, isEmpty);
    });

    test('分析失败时不标记已处理、不回调', () async {
      analyzeResult = false;
      final scheduler = buildScheduler();
      SharedPreferences.setMockInitialValues({
        MemoryAiScheduler.roundsKey('a1'): 9,
      });
      scheduleDefault(scheduler);
      await coordinator.waitForIdle('a1');
      expect(analyzeCount, 1);
      expect(markedIds, isEmpty);
      expect(appliedAgentIds, isEmpty);
    });

    test('enableProfile=true 时读取并传入既有画像', () async {
      profileEntries = [
        ProfileEntry(
          id: 'p1',
          category: 'basic_info',
          key: '姓名',
          value: '小明',
          confidence: 90,
        ),
      ];
      final scheduler = buildScheduler();
      SharedPreferences.setMockInitialValues({
        MemoryAiScheduler.roundsKey('a1'): 9,
      });
      scheduler.schedule(
        agentId: 'a1',
        apiKey: 'key-123',
        baseUrl: 'https://example.test',
        temperature: 1.3,
        persona: '你是小红',
        worldview: '',
        enableProfile: true,
      );
      await coordinator.waitForIdle('a1');
      expect(analyzeCall.enableProfile, isTrue);
      expect(analyzeCall.existingProfile!.single.id, 'p1');
    });

    test('同智能体任务在途时重复调度被去重', () async {
      final scheduler = buildScheduler();
      SharedPreferences.setMockInitialValues({
        MemoryAiScheduler.roundsKey('a1'): 9,
      });
      scheduleDefault(scheduler);
      scheduleDefault(scheduler);
      await coordinator.waitForIdle('a1');
      expect(analyzeCount, 1);
    });
  });
}
