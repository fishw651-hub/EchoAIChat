import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/server_config.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/agent.dart';
import '../models/profile_entry.dart';
import '../services/group_service.dart';
import '../services/api_service.dart';
import '../services/chat_stream_assembler.dart';
import '../services/tool_executor.dart';
import '../services/database_service.dart';
import '../services/memory_service.dart';
import '../services/memory_ai_service.dart';
import '../services/plan_service.dart';
import '../services/quota_service.dart';
import '../services/chat_runtime_policy.dart';
import '../services/model_list_service.dart';
import '../services/proactive_care_alarm.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService();
});

class GroupState {
  final List<GroupChat> groups;
  final GroupChat? activeGroup;
  final List<GroupMember> members;
  final List<GroupMessage> messages;
  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> debugMessages;
  final QuotaType? quotaExceeded;

  /// 是否还有更早的群历史消息未加载（向上翻页加载）
  final bool hasMoreMessages;

  const GroupState({
    this.groups = const [],
    this.activeGroup,
    this.members = const [],
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.debugMessages = const [],
    this.quotaExceeded,
    this.hasMoreMessages = false,
  });

  GroupState copyWith({
    List<GroupChat>? groups,
    GroupChat? activeGroup,
    List<GroupMember>? members,
    List<GroupMessage>? messages,
    bool? isLoading,
    String? error,
    List<Map<String, dynamic>>? debugMessages,
    QuotaType? quotaExceeded,
    bool clearQuotaExceeded = false,
    bool? hasMoreMessages,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      activeGroup: activeGroup ?? this.activeGroup,
      members: members ?? this.members,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      debugMessages: debugMessages ?? this.debugMessages,
      quotaExceeded: clearQuotaExceeded
          ? null
          : (quotaExceeded ?? this.quotaExceeded),
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
    );
  }
}

class GroupNotifier extends StateNotifier<GroupState> {
  final Ref _ref;
  final GroupService _groupService;
  bool _userInterrupted = false;

  GroupNotifier(this._ref, this._groupService) : super(const GroupState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final groups = await _groupService.getGroups();
      state = state.copyWith(groups: groups);
    } catch (e) {
      _glog('_init failed: $e');
    }
  }

  // ═══ Group CRUD ═══

  Future<GroupChat> createGroup({
    required String name,
    String description = '',
    int avatarColor = 0xFFE8F5E9,
    String? avatarIcon,
    String? avatarPath,
    String? groupPersona,
    String? openingLine,
    String? openingSpeakerAgentId,
    String speechMode = 'free',
    required List<GroupMember> members,
    bool isSimulatorMode = false,
    String? worldSetting,
    bool linkedMemory = false,
  }) async {
    _glog('createGroup START: name=$name members.count=${members.length}');
    for (final m in members) {
      _glog(
        '  member: agentId=${m.agentId} groupId=${m.groupId} role=${m.role} isPresent=${m.isPresent}',
      );
    }
    final group = GroupChat(
      name: name,
      description: description,
      avatarColor: avatarColor,
      avatarIcon: avatarIcon,
      avatarPath: avatarPath,
      groupPersona: groupPersona,
      openingLine: openingLine,
      openingSpeakerAgentId: openingSpeakerAgentId,
      speechMode: speechMode,
      isSimulatorMode: isSimulatorMode,
      worldSetting: worldSetting,
      linkedMemory: linkedMemory,
    );
    _glog('  created GroupChat id=${group.id}');
    await _groupService.createGroup(group, members);
    await loadGroups();
    _glog('  loadGroups returned ${state.groups.length} groups');
    if (isSimulatorMode) {
      await toggleSimulatorMode(group, true);
    }
    await loadGroup(group.id);
    _glog(
      'createGroup DONE: activeGroup=${state.activeGroup?.name}, members=${state.members.length}',
    );
    return await _groupService.getGroup(group.id) ?? group;
  }

  Future<void> updateGroup(GroupChat group) async {
    await _groupService.updateGroup(group);
    state = state.copyWith(
      activeGroup: group,
      groups: state.groups.map((g) => g.id == group.id ? group : g).toList(),
    );
  }

  Future<void> deleteGroup(String id) async {
    await _groupService.deleteGroup(id);
    state = state.copyWith(
      groups: state.groups.where((g) => g.id != id).toList(),
      activeGroup: state.activeGroup?.id == id ? null : state.activeGroup,
      messages: [],
      members: [],
    );
  }

  Future<void> loadGroups() async {
    try {
      final groups = await _groupService.getGroups();
      state = state.copyWith(groups: groups);
    } catch (e) {
      _glog('loadGroups failed: $e');
    }
  }

  // ═══ Load group ═══

  /// 群历史分页大小（与私聊一致：只加载最近一页，更早的向上滚动加载）
  static const int _groupPageSize = 100;

  Future<void> loadGroup(String groupId) async {
    try {
      _groupService.setActiveGroup(groupId);
      final group = await _groupService.getGroup(groupId);
      final members = await _groupService.getMembers(groupId);
      final totalCount = await DatabaseService.getGroupMessageCount(groupId);
      final messages = await _groupService.getMessages(
        groupId,
        limit: _groupPageSize,
      );
      state = state.copyWith(
        activeGroup: group,
        members: members,
        messages: messages,
        hasMoreMessages: totalCount > messages.length,
        error: null,
      );
      await _ensureOpeningMessage(group, members, messages);
    } catch (e) {
      _glog('loadGroup failed: $e');
      state = state.copyWith(error: '加载群聊失败: $e');
    }
  }

  /// 向上翻页：加载更早的一页群消息并前插
  Future<void> loadEarlierGroupMessages() async {
    final groupId = state.activeGroup?.id;
    if (groupId == null || !state.hasMoreMessages || _loadingEarlier) return;
    _loadingEarlier = true;
    try {
      int? oldestId;
      for (final m in state.messages) {
        if (m.id != null && (oldestId == null || m.id! < oldestId)) {
          oldestId = m.id;
        }
      }
      if (oldestId == null) return;
      final earlier = await _groupService.getMessages(
        groupId,
        limit: _groupPageSize,
        beforeId: oldestId,
      );
      if (earlier.isEmpty) {
        state = state.copyWith(hasMoreMessages: false);
        return;
      }
      // 加载期间可能已切走
      if (state.activeGroup?.id != groupId) return;
      final existingIds = state.messages
          .where((m) => m.id != null)
          .map((m) => m.id!)
          .toSet();
      final prepend = earlier
          .where((m) => !existingIds.contains(m.id))
          .toList();
      state = state.copyWith(
        messages: [...prepend, ...state.messages],
        hasMoreMessages: earlier.length >= _groupPageSize,
      );
    } finally {
      _loadingEarlier = false;
    }
  }

  bool _loadingEarlier = false;

  Future<void> _ensureOpeningMessage(
    GroupChat? group,
    List<GroupMember> members,
    List<GroupMessage> messages,
  ) async {
    if (group == null || messages.isNotEmpty) return;
    final opening = group.openingLine?.trim();
    if (opening == null || opening.isEmpty) return;
    final speakerId = group.openingSpeakerAgentId;
    if (speakerId == null ||
        !members.any((member) => member.agentId == speakerId)) {
      return;
    }
    await _sendOpeningMessage(group: group, agentId: speakerId);
    final refreshed = await _groupService.getMessages(group.id);
    state = state.copyWith(messages: refreshed);
  }

  Future<void> _sendOpeningMessage({
    required GroupChat group,
    required String agentId,
  }) async {
    final opening = group.openingLine?.trim();
    if (opening == null || opening.isEmpty) return;
    final agent = await DatabaseService.getAgent(agentId);
    if (agent == null) return;
    await _groupService.sendAgentMessage(
      groupId: group.id,
      agentId: agent.id,
      agentName: agent.name,
      content: opening,
    );
  }

  // ═══ Members ═══

  Future<void> addMember(GroupMember member) async {
    await _groupService.addMember(member);
    if (state.activeGroup?.id == member.groupId) {
      await loadGroup(member.groupId);
    }
  }

  Future<void> updateMember(GroupMember member) async {
    await _groupService.updateMember(member);
    if (state.activeGroup?.id == member.groupId) {
      await loadGroup(member.groupId);
    }
  }

  Future<void> removeMember(int memberId) async {
    await _groupService.removeMember(memberId);
    if (state.activeGroup != null) {
      await loadGroup(state.activeGroup!.id);
    }
  }

  Future<void> togglePresence(int memberId, bool present) async {
    await _groupService.togglePresence(memberId, present);
    if (state.activeGroup != null) {
      await loadGroup(state.activeGroup!.id);
    }
  }

  // ═══ Send user message + trigger agent replies (轮播模式) ═══

  Future<void> sendUserMessage(String groupId, String content) async {
    if (content.trim().isEmpty) return;
    if (state.isLoading) return;

    // 群聊不消耗真实回复配额（群聊不绑定单个 agent 的 realInfoEnabled）

    // 同步全局短期记忆轮数到 GroupService（群聊保留条数 = 基础轮数 × 群成员数量）
    _groupService.maxShortTermRounds = _ref
        .read(settingsProvider)
        .maxShortTermRounds;

    final msg = await _groupService.sendUserMessage(groupId, content);
    state = state.copyWith(messages: [...state.messages, msg], isLoading: true);

    _userInterrupted = false;
    await _runSpeakers(groupId);
  }

  /// 清除配额超限标记
  void clearQuotaExceeded() {
    state = state.copyWith(clearQuotaExceeded: true);
  }

  /// 并行模式：导演AI一次决定发言顺序，所有角色并行回复，逐条显示
  Future<void> _runSpeakers(String groupId) async {
    final group = await _groupService.getGroup(groupId);
    if (group == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final allMembers = await _groupService.getPresentMembers(groupId);
    if (allMembers.isEmpty) {
      _glog('No present members, bailing');
      state = state.copyWith(isLoading: false);
      return;
    }

    final memberAgents = <String, Agent>{};
    for (final m in allMembers) {
      final agent = await DatabaseService.getAgent(m.agentId);
      if (agent != null) memberAgents[m.agentId] = agent;
    }
    if (memberAgents.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    // linked_memory 群没有群域长期记忆（记忆都写入成员私聊），跳过在场记录
    if (!group.linkedMemory) {
      // 必须用独立实例：共享全局 memoryServiceProvider 会污染私聊上下文
      // （setAgentId(null) 后回私聊不 reload，导致私聊"失忆"）
      final memoryService = MemoryService();
      memoryService.setAgentId(null);
      memoryService.setGroupId(groupId);
      await _recordPresence(groupId, allMembers, memberAgents, memoryService);
    }

    // Phase 1: 导演AI一次决定发言顺序（一次API调用）
    final recentContext = await _groupService.getShortTerm(groupId, limit: 8);

    final contextMessages = recentContext.map((st) {
      var role = st['role'] as String;
      if (role == 'agent') role = 'assistant';
      return {
        'role': role,
        'content': st['content'] as String,
        'sender_name': st['sender_name'],
      };
    }).toList();

    final speakerIds = await _decideSpeakers(
      group: group,
      memberAgents: memberAgents,
      recentContext: recentContext,
    );

    if (speakerIds.isEmpty || _userInterrupted) {
      state = state.copyWith(isLoading: false);
      return;
    }

    // Phase 2: 并行生成所有角色回复
    final futures = <Future<GroupMessage?>>[];
    for (final id in speakerIds) {
      final agent = memberAgents[id];
      if (agent == null) continue;
      final member = allMembers.firstWhere((m) => m.agentId == id);
      futures.add(
        _generateSingleAgentReply(
          groupId,
          member,
          agent,
          previousMessages: contextMessages,
          worldSetting: group.worldSetting,
        ),
      );
    }

    if (futures.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    // Phase 3: 逐条显示——50ms debounce 批量更新
    // 回复落库后替换对应的本地打字临时消息（同 senderId 且 isStreaming），保证 id 与 DB 一致
    void mergeBatch(List<GroupMessage> batch) {
      final msgs = List<GroupMessage>.from(state.messages);
      for (final reply in batch) {
        final idx = msgs.indexWhere(
          (m) => m.isStreaming && m.senderId == reply.senderId,
        );
        if (idx == -1) {
          msgs.add(reply);
        } else {
          msgs[idx] = reply;
        }
      }
      state = state.copyWith(messages: msgs);
    }

    final pending = <GroupMessage>[];
    Timer? batchTimer;
    await for (final reply in Stream.fromFutures(futures)) {
      if (reply != null && !_userInterrupted) {
        pending.add(reply);
        batchTimer?.cancel();
        batchTimer = Timer(const Duration(milliseconds: 50), () {
          final batch = List<GroupMessage>.from(pending);
          pending.clear();
          if (!_userInterrupted) {
            mergeBatch(batch);
          }
        });
      }
    }
    batchTimer?.cancel();
    if (pending.isNotEmpty && !_userInterrupted) {
      mergeBatch(List<GroupMessage>.from(pending));
    }

    // Phase 4: 群聊 Memory AI（每 5 轮触发，await 确保完成后再结束）
    if (!_userInterrupted) {
      final auth = _ref.read(authProvider);
      if (auth.apiKey != null && auth.apiKey!.isNotEmpty) {
        final shouldRun = await _shouldRunGroupMemoryAi(groupId);
        if (shouldRun) {
          await _groupMemoryAi(
            groupId,
            speakerIds,
            memberAgents,
            auth.apiKey!,
            group.worldSetting ?? '',
            linkedMemory: group.linkedMemory,
          );
        }
      }
    }

    state = state.copyWith(isLoading: false);
    if (!_userInterrupted) {
      unawaited(_ref.read(authProvider.notifier).refreshUserProfile());
    }
  }

  /// 群聊 Memory AI：每 5 轮触发，逐角色管理短期上下文，使用未处理消息避免重复分析
  /// linkedMemory 群：记忆 AI 产出写入成员私聊长期/基础记忆（不设置 groupId）
  Future<void> _groupMemoryAi(
    String groupId,
    List<String> speakerIds,
    Map<String, Agent> memberAgents,
    String apiKey,
    String worldview, {
    bool linkedMemory = false,
  }) async {
    // 获取未处理的群聊短期记忆（去重：已处理的消息不再分析）
    final unprocessed = await DatabaseService.getUnprocessedGroupShortTerm(
      groupId,
    );
    if (unprocessed.isEmpty) return;

    final unprocessedIds = unprocessed.map((m) => m['id'] as int).toList();
    final uniqueSpeakers = speakerIds.toSet();
    var allSuccess = true;

    for (final id in uniqueSpeakers) {
      try {
        final agent = memberAgents[id];
        if (agent == null) continue;

        // 为每个并行 agent 创建独立 MemoryService 实例，避免 setAgentId 互相覆盖
        final memoryService = MemoryService();
        memoryService.setAgentId(id);
        // linked 群不设置 groupId —— 记忆直接写入该成员的私聊长期/基础记忆
        if (!linkedMemory) memoryService.setGroupId(groupId);

        // PlanService 也用独立实例：共享单例的 agentId 会被群/私聊并行链路互踩
        final planService = PlanService(
          notificationService: _ref.read(notificationServiceProvider),
        );
        planService.setAgentId(id);

        final existingLongTerm = await memoryService.getLongTermMemories();
        final existingBase = await memoryService.getBaseMemories();

        final success = await MemoryAiService.analyzeAndApply(
          memoryService: memoryService,
          planService: planService,
          profileService: _ref.read(userProfileServiceProvider),
          agentId: id,
          apiKey: apiKey,
          baseUrl: ServerConfig.baseUrl,
          thinkingMode: false,
          temperature: ChatRuntimePolicy.standard.temperature!,
          shortTerm: unprocessed,
          persona: agent.persona,
          existingLongTerm: existingLongTerm,
          existingBase: existingBase,
          existingProfile: const <ProfileEntry>[],
          enableProfile: false, // 群聊不触发画像 AI
          worldview: worldview,
        );
        if (!success) allSuccess = false;
      } catch (e) {
        _glog('Memory AI error for speaker $id: $e');
        allSuccess = false;
      }
    }

    // 所有 speaker 处理完后，标记消息为已处理
    // 只要有任一 speaker 失败则不标记，保留未处理状态供下次重试
    if (allSuccess) {
      await DatabaseService.markGroupShortTermProcessed(unprocessedIds);
    }
  }

  /// 群聊 Memory AI 每 5 轮触发一次
  Future<bool> _shouldRunGroupMemoryAi(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'group_memory_ai_rounds_$groupId';
    final rounds = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, rounds);
    return rounds % 5 == 0;
  }

  /// 导演AI — 一次决定本轮发言顺序（返回多发言人列表）
  Future<List<String>> _decideSpeakers({
    required GroupChat group,
    required Map<String, Agent> memberAgents,
    required List<Map<String, dynamic>> recentContext,
  }) async {
    if (memberAgents.isEmpty) return [];
    if (memberAgents.length == 1) return [memberAgents.keys.first];

    final selectedModel = _ref.read(settingsProvider).selectedModel;
    final chatModel = selectedModel.isEmpty
        ? ModelListService.defaultModel
        : selectedModel;
    // 所选模型不支持思考（thinking_status==0）时静默降级为非思考，
    // 避免服务器拒绝；不改动用户的思考模式设置
    final thinkingAllowed = ModelListService.supportsThinking(
      _ref.read(modelListProvider).models,
      chatModel,
    );
    final apiService = ApiService.fromConfig(
      model: chatModel,
      apiKey: _ref.read(authProvider).apiKey ?? '',
      baseUrl: ServerConfig.baseUrl,
      thinkingMode: group.isSimulatorMode
          ? ChatRuntimePolicy.simulator.thinkingMode && thinkingAllowed
          : ChatRuntimePolicy.standard.thinkingMode,
      temperature:
          (group.isSimulatorMode
              ? ChatRuntimePolicy.simulator.temperature
              : ChatRuntimePolicy.standard.temperature) ??
          1.3,
      clientAgentId: memberAgents.keys.first,
      requestKind: 'group_chat',
    );

    final characterList = StringBuffer();
    for (final entry in memberAgents.entries) {
      final a = entry.value;
      characterList.writeln(
        '- ${a.name} (id: ${a.id.substring(0, 8)}): ${a.description}',
      );
      characterList.writeln('  性别: ${a.gender.isNotEmpty ? a.gender : '未知'}');
      characterList.writeln(
        '  人设: ${a.persona.length > 100 ? a.persona.substring(0, 100) : a.persona}',
      );
      characterList.writeln();
    }

    final recentLines = StringBuffer();
    for (final m in recentContext) {
      final sender = m['sender_name'] as String? ?? m['role'] as String;
      final content = m['content'] as String;
      recentLines.writeln('[$sender]: $content');
    }

    final worldSetting = group.worldSetting ?? '';
    final worldSection = worldSetting.isNotEmpty
        ? '\n## 世界观\n$worldSetting\n'
        : '';

    final systemPrompt =
        '''你是群聊导演。根据当前对话进展和角色设定，决定接下来应该由哪些角色发言。

$worldSection
## 所有角色
$characterList

## 最近对话
$recentLines

## 规则
1. 选择最应该接话的角色——可能是在对话中被提到、情绪波动、或场景角色最适合发言的人
2. 按优先级排序——最应该接话的排在前面
3. 如果当前对话已经自然收尾或没有人适合说话，返回 "STOP"
4. 返回角色id列表，用逗号分隔。例如 "abc12345,def67890"
5. 每个角色最多出现一次
6. 你只负责选择发言顺序，不代替角色写台词，也不推进剧情

请只回复角色id列表（逗号分隔）或STOP，不要加任何解释。''';

    try {
      final response = await apiService.chatCompletion(
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '接下来应该由谁发言？按优先级列出角色id，用逗号分隔。'},
        ],
        tools: [],
      );

      final content = ApiService.parseContent(response)?.trim() ?? '';
      _glog('Director decision: "$content"');

      if (content.isEmpty || content.toUpperCase() == 'STOP') return [];

      final parts = content
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final matchedIds = <String>[];
      for (final part in parts) {
        String? matched;
        for (final entry in memberAgents.entries) {
          if (entry.key.startsWith(part) || entry.key.contains(part)) {
            matched = entry.key;
            break;
          }
        }
        if (matched == null) {
          for (final entry in memberAgents.entries) {
            if (entry.value.name == part) {
              matched = entry.key;
              break;
            }
          }
        }
        if (matched != null && !matchedIds.contains(matched)) {
          matchedIds.add(matched);
        }
      }

      if (matchedIds.isNotEmpty) return matchedIds;

      _glog('Director returned unmatched speakers: $content');
      for (final entry in memberAgents.entries) {
        final member = state.members.firstWhere(
          (m) => m.agentId == entry.key,
          orElse: () => GroupMember(
            agentId: entry.key,
            groupId: group.id,
            role: 'member',
          ),
        );
        if (member.role != 'moderator') return [entry.key];
      }
      return [memberAgents.keys.first];
    } catch (e) {
      _glog('Director error: $e');
      for (final entry in memberAgents.entries) {
        final member = state.members.firstWhere(
          (m) => m.agentId == entry.key,
          orElse: () => GroupMember(
            agentId: entry.key,
            groupId: group.id,
            role: 'member',
          ),
        );
        if (member.role != 'moderator') return [entry.key];
      }
      return memberAgents.keys.isNotEmpty ? [memberAgents.keys.first] : [];
    }
  }

  /// 记录当前在场人员为长期记忆
  Future<void> _recordPresence(
    String groupId,
    List<GroupMember> allMembers,
    Map<String, Agent> memberAgents,
    MemoryService memoryService,
  ) async {
    try {
      final presentNames = <String>[];
      for (final m in allMembers) {
        final agent = memberAgents[m.agentId];
        if (agent != null) presentNames.add(agent.name);
      }
      if (presentNames.isEmpty) return;

      // 获取已有的在场记忆
      final existing = await memoryService.getLongTermMemories();
      final presenceMem = existing
          .where(
            (m) => m.field == 'current_events' && m.content.contains('在场的角色'),
          )
          .toList();

      final newContent = '在场的角色: ${presentNames.join('、')}';

      if (presenceMem.isNotEmpty) {
        // 更新已有记录
        await memoryService.updateLongTermMemory(
          targetId: presenceMem.first.id,
          content: newContent,
        );
      } else {
        // 创建新记录
        await memoryService.createLongTermMemory(
          field: 'current_events',
          content: newContent,
        );
      }
      _glog('  Presence recorded: $newContent');
    } catch (e) {
      _glog('  Presence record error: $e');
    }
  }

  Future<GroupMessage?> _generateSingleAgentReply(
    String groupId,
    GroupMember member,
    Agent agent, {
    List<Map<String, dynamic>>? previousMessages,
    String? worldSetting,
  }) async {
    _glog(
      '    _generateSingleAgentReply: agent=${agent.name} groupId=$groupId',
    );
    final auth = _ref.read(authProvider);
    if (auth.apiKey == null || auth.apiKey!.isEmpty) {
      _glog('    SKIP: not logged in');
      return null;
    }

    final group = await _groupService.getGroup(groupId);
    if (group == null) {
      _glog('    SKIP: group not found');
      return null;
    }

    final persona = agent.persona
        .replaceAll('{{NAME}}', agent.name)
        .replaceAll('{{GENDER}}', agent.gender)
        .replaceAll('{{DESCRIPTION}}', agent.description);

    final worldview = worldSetting ?? agent.worldview;

    final allMembers = await _groupService.getMembers(groupId);
    final allAgents = await Future.wait(
      allMembers.map((m) async => await DatabaseService.getAgent(m.agentId)),
    );

    // 群聊不注入真实信息（不绑定单个 agent 的 realInfoEnabled）

    final baseSystemContent = await _groupService.buildGroupSystemPrompt(
      group: group,
      agent: agent,
      agentPersona: persona,
      allMembers: allMembers,
      agentDetails: allAgents.whereType<Agent>().toList(),
      worldSetting: worldview,
    );
    final systemContent =
        '''$baseSystemContent

## 回复长度
- 每次回复尽量控制在不超过 ${agent.maxResponseLength} 个字以内。
- 优先保证内容完整、自然，不要为了凑字数重复或截断句子。''';

    final tools = ApiService.getToolDefinitions(isGroupChat: true);

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemContent},
      ...(previousMessages ?? []).map(
        (m) => {
          'role': m['role'] as String,
          'content': m['content'] as String,
          'name': m['sender_name'],
        },
      ),
    ];

    _glog('    context msgs: ${apiMessages.length}');

    final selectedModel = _ref.read(settingsProvider).selectedModel;
    final chatModel = selectedModel.isEmpty
        ? ModelListService.defaultModel
        : selectedModel;
    // 所选模型不支持思考（thinking_status==0）时静默降级为非思考，
    // 避免服务器拒绝；不改动用户的思考模式设置
    final thinkingAllowed = ModelListService.supportsThinking(
      _ref.read(modelListProvider).models,
      chatModel,
    );
    final apiService = ApiService.fromConfig(
      model: chatModel,
      apiKey: _ref.read(authProvider).apiKey ?? '',
      baseUrl: ServerConfig.baseUrl,
      thinkingMode: group.isSimulatorMode
          ? ChatRuntimePolicy.simulator.thinkingMode && thinkingAllowed
          : ChatRuntimePolicy.standard.thinkingMode,
      temperature:
          (group.isSimulatorMode
              ? ChatRuntimePolicy.simulator.temperature
              : ChatRuntimePolicy.standard.temperature) ??
          1.3,
      clientAgentId: agent.id,
      requestKind: 'group_chat',
    );

    final startTime = DateTime.now();

    // 本地打字临时消息：发起调用前先插入，回调中按 50ms 节流更新
    _insertStreamingPlaceholder(groupId, agent);
    var latestPartial = '';
    Timer? streamThrottle;
    void flushPartial() {
      streamThrottle?.cancel();
      streamThrottle = null;
      if (_userInterrupted) return;
      if (state.activeGroup?.id != groupId) return;
      final msgs = List<GroupMessage>.from(state.messages);
      final idx = msgs.indexWhere(
        (m) => m.isStreaming && m.senderId == agent.id,
      );
      if (idx == -1) return;
      if (msgs[idx].content == latestPartial) return;
      msgs[idx] = msgs[idx].copyWith(content: latestPartial);
      state = state.copyWith(messages: msgs);
    }

    void onStreamText(String partial) {
      latestPartial = partial;
      streamThrottle ??= Timer(const Duration(milliseconds: 50), flushPartial);
    }

    try {
      final result = await _runGroupToolLoop(
        apiService: apiService,
        tools: tools,
        apiMessages: apiMessages,
        startTime: startTime,
        agentId: agent.id,
        agentName: agent.name,
        groupId: groupId,
        linkedMemory: group.linkedMemory,
        onStreamText: onStreamText,
      );

      if (result.content != null && result.content!.isNotEmpty) {
        final toolCallJson = result.toolLogs.isNotEmpty
            ? jsonEncode(
                result.toolLogs
                    .map(
                      (e) => {
                        'toolName': e.toolName,
                        'arguments': e.arguments,
                        'result': e.result,
                      },
                    )
                    .toList(),
              )
            : null;
        final agentMsg = await _groupService.sendAgentMessage(
          groupId: groupId,
          agentId: agent.id,
          agentName: agent.name,
          content: result.content!,
          toolCallData: toolCallJson,
        );
        // 临时消息由 Phase 3 用落库消息替换（保证 id 与 DB 一致）
        return agentMsg;
      } else {
        _glog('    No reply generated');
        _removeStreamingPlaceholder(groupId, agent.id);
        return null;
      }
    } on ApiException catch (e) {
      _glog('    ApiException: $e');
      _removeStreamingPlaceholder(groupId, agent.id);
      _addErrorToChat(groupId, agent.name, 'API error: $e');
      return null;
    } catch (e) {
      _glog('    Unexpected error: $e');
      _removeStreamingPlaceholder(groupId, agent.id);
      return null;
    } finally {
      streamThrottle?.cancel();
    }
  }

  /// 插入某 agent 的本地打字临时消息（仅当前活跃群；已存在则不重复插入）。
  void _insertStreamingPlaceholder(String groupId, Agent agent) {
    if (_userInterrupted) return;
    if (state.activeGroup?.id != groupId) return;
    final exists = state.messages.any(
      (m) => m.isStreaming && m.senderId == agent.id,
    );
    if (exists) return;
    state = state.copyWith(
      messages: [
        ...state.messages,
        GroupMessage(
          groupId: groupId,
          senderType: 'agent',
          senderId: agent.id,
          senderName: agent.name,
          content: '',
          isStreaming: true,
        ),
      ],
    );
  }

  /// 移除某 agent 的本地打字临时消息（失败/中断路径用）。
  void _removeStreamingPlaceholder(String groupId, String agentId) {
    if (state.activeGroup?.id != groupId) return;
    final msgs = state.messages
        .where((m) => !(m.isStreaming && m.senderId == agentId))
        .toList();
    if (msgs.length != state.messages.length) {
      state = state.copyWith(messages: msgs);
    }
  }

  void _addErrorToChat(String groupId, String agentName, String error) {
    _groupService.sendAgentMessage(
      groupId: groupId,
      agentId: '',
      agentName: agentName,
      content: '[Error: $error]',
    );
  }

  Future<_GroupToolResult> _runGroupToolLoop({
    required ApiService apiService,
    required List<Map<String, dynamic>> tools,
    required List<Map<String, dynamic>> apiMessages,
    required DateTime startTime,
    required String agentId,
    required String agentName,
    required String groupId,
    bool linkedMemory = false,
    void Function(String partialText)? onStreamText,
  }) async {
    // 为每个并行 agent 创建独立的 MemoryService 实例，避免并行回复时
    // 共享全局 memoryServiceProvider 导致 setAgentId 互相覆盖、记忆写入错误 agent
    final independentMemoryService = MemoryService();
    independentMemoryService.setAgentId(agentId);
    // linked 群不设置 groupId：remember 工具的 personal 记忆写入成员私聊记忆
    if (!linkedMemory) independentMemoryService.setGroupId(groupId);
    // PlanService 同样独立：共享单例的 setAgentId 会在群/私聊并行链路间互踩，
    // 导致计划消息记到错误 agent 头上
    final independentPlanService = PlanService(
      notificationService: _ref.read(notificationServiceProvider),
    );
    independentPlanService.setAgentId(agentId);
    ToolExecutor toolExecutor = ToolExecutor(
      memoryService: independentMemoryService,
      planService: independentPlanService,
      groupService: _groupService,
    );
    _groupService.setActiveGroup(groupId);

    const maxToolRounds = 5;
    var toolChoice = 'required';
    for (int round = 0; round < maxToolRounds; round++) {
      if (_userInterrupted) return const _GroupToolResult();

      final roundResult = await _runGroupStreamRound(
        apiService: apiService,
        apiMessages: apiMessages,
        tools: tools,
        toolChoice: toolChoice,
        onStreamText: onStreamText,
      );
      toolChoice = 'auto';
      if (_userInterrupted) return const _GroupToolResult();

      if (roundResult.finishReason == 'tool_calls' &&
          roundResult.toolCalls.isNotEmpty) {
        if (roundResult.assistantMessage != null) {
          apiMessages.add(roundResult.assistantMessage!);
        }

        String? chatContent;

        for (int i = 0; i < roundResult.toolCalls.length; i++) {
          final tc = roundResult.toolCalls[i];
          final name = tc['name'] as String;
          final args = tc['arguments'] as Map<String, dynamic>;
          final toolCallId = tc['id'] as String;

          _glog('Tool call: $name');

          final toolResult = await toolExecutor.execute(name, args);

          if (name == 'chatgroup') {
            chatContent = args['message'] as String? ?? '';
          }

          apiMessages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': toolResult,
          });
        }

        if (chatContent != null) {
          final logs = List<ToolExecutionLog>.from(toolExecutor.executionLogs);
          return _GroupToolResult(content: chatContent, toolLogs: logs);
        }

        if (_userInterrupted) return const _GroupToolResult();
        continue;
      }

      final textContent = roundResult.content;
      if (textContent != null && textContent.isNotEmpty) {
        final logs = List<ToolExecutionLog>.from(toolExecutor.executionLogs);
        return _GroupToolResult(content: textContent, toolLogs: logs);
      }
      return const _GroupToolResult();
    }

    return const _GroupToolResult();
  }

  /// 执行一轮群聊补全：完整响应返回后，本地生成的 chatgroup arguments
  /// 分片经 [extractStreamingMessage] 渐进提取文本上抛。
  Future<_GroupStreamRound> _runGroupStreamRound({
    required ApiService apiService,
    required List<Map<String, dynamic>> apiMessages,
    required List<Map<String, dynamic>> tools,
    required String toolChoice,
    void Function(String partialText)? onStreamText,
  }) async {
    final assembler = ToolCallDeltaAssembler();
    final plainContent = StringBuffer();
    String? finishReason;

    try {
      await for (final event in apiService.chatCompletionStream(
        messages: apiMessages,
        tools: tools,
        toolChoice: toolChoice,
      )) {
        if (_userInterrupted) break; // 停止消费本地渐进事件
        switch (event.type) {
          case ChatStreamEventType.content:
            final delta = event.contentDelta ?? '';
            if (delta.isNotEmpty) {
              plainContent.write(delta);
            }
          case ChatStreamEventType.toolCall:
            assembler.add(
              ToolCallDelta(
                index: event.toolCallIndex ?? 0,
                id: event.toolCallId,
                name: event.toolCallName,
                argumentsDelta: event.argumentsDelta,
              ),
            );
            final call = assembler.callAt(event.toolCallIndex ?? 0);
            // 仅 chatgroup 文本上抛；remember/forget/manage_character 等不可见
            if (call != null && call.name == 'chatgroup') {
              onStreamText?.call(extractStreamingMessage(call.arguments));
            }
          case ChatStreamEventType.finish:
            finishReason = event.finishReason;
          case ChatStreamEventType.usage:
          case ChatStreamEventType.cost:
          case ChatStreamEventType.done:
            break;
        }
      }
    } catch (e) {
      _glog('Group non-stream completion failed: $e');
      rethrow;
    }

    // 组装本轮结果
    final content = plainContent.toString();
    final toolCalls = <Map<String, dynamic>>[];
    final rawToolCalls = <Map<String, dynamic>>[];
    for (final call in assembler.calls) {
      Map<String, dynamic> args;
      try {
        final decoded = jsonDecode(
          call.arguments.isEmpty ? '{}' : call.arguments,
        );
        args = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        // 本地事件消费中断导致 JSON 不完整：尽力提取已收到的 message 文本
        args = <String, dynamic>{};
        if (call.name == 'chatgroup') {
          final partial = extractStreamingMessage(call.arguments);
          if (partial.isNotEmpty) args = {'message': partial};
        }
      }
      toolCalls.add({'id': call.id, 'name': call.name, 'arguments': args});
      rawToolCalls.add({
        'id': call.id,
        'type': 'function',
        'function': {'name': call.name, 'arguments': call.arguments},
      });
    }

    Map<String, dynamic>? assistantMessage;
    if (toolCalls.isNotEmpty) {
      assistantMessage = {
        'role': 'assistant',
        'content': content.isEmpty ? null : content,
        'tool_calls': rawToolCalls,
      };
    }
    // 中断/未显式 finish 时按已收到的内容推断
    finishReason ??= toolCalls.isNotEmpty
        ? 'tool_calls'
        : (content.isNotEmpty ? 'stop' : null);

    return _GroupStreamRound(
      finishReason: finishReason,
      toolCalls: toolCalls,
      content: content.isEmpty ? null : content,
      assistantMessage: assistantMessage,
    );
  }

  // ═══ Interrupt ═══

  void interruptAgents() {
    _userInterrupted = true;
    // 定格/移除所有本地打字临时消息
    final msgs = state.messages.where((m) => !m.isStreaming).toList();
    if (msgs.length != state.messages.length) {
      state = state.copyWith(messages: msgs);
    }
  }

  // ═══ Simulator Mode ═══

  static const String narratorPersonaTemplate = '''你是一个小说故事的旁白/叙述者。你的核心工作是：
1. 用 chatgroup 输出场景叙述，推进剧情
2. 用 manage_character 创建 NPC 角色——让故事世界有真实的人物互动

世界观设定：{{WORLD_SETTING}}

## 你必须主动创建 NPC（最重要的一条）
当故事场景中需要出现其他人物时，你必须使用 manage_character 工具来创建他们，而非仅仅在叙述中用文字带过。
创建的角色会作为 AI 智能体加入群聊，自行发言互动——这是让故事世界鲜活起来的核心机制。
示例场景：
- user 走进一间酒馆 → 创建酒馆老板
- user 在旅途中遇到陌生人 → 创建那个旅人
- 剧情需要反派或对手 → 创建那个反派
- 群众、路人、商贩让世界真实 → 大胆创建他们

如果你只是用 chatgroup 文字描述一个 NPC 却没有用 manage_character 创建他，
那你没有完成你的职责——文字描述 ≠ 角色创建。

## 关于 user 的角色
user 是故事主角的扮演者。user 输入的文字 = 主角的言行本身。
你创建的 NPC 围绕主角展开故事——丰富冒险、提供信息、制造冲突——但永远不取代主角。
user 自己掌控主角的一切行动，你不指挥、不替代、不复制。

## 创建守则
1. 积极创建：每个新场景中需要出现的 NPC，立即用 manage_character(action: "add") 创建
2. 不抢主角：不创建与 user 主角定位相同的角色。user 是英雄，NPC 就是酒馆老板、路人、反派——不是"另一个英雄"
3. 及时清理：NPC 离开场景后，用 manage_character(action: "remove") 移除
4. 创建 NPC 时，persona 字段必须包含角色的输出格式指令：
   - 以角色的身份用第一人称说话
   - 用 () 表达动作、表情、心理活动
   - 不使用第三人称描述自己
   - 不说叙述者的环境描写或场景切换
5. 创建 NPC 后必须立即用 chatgroup 输出该角色的登场描写——ta 在哪里、在做什么、与主角/场景的关系。这是角色的初始定义，必须一次到位
6. 创建前检查已有成员——已存在的角色绝不重复创建

## 发言守则
1. 用 chatgroup 输出场景叙述：环境描写、氛围营造、时间推移
2. 只在剧情转折、新场景开始、重要事件发生时发言——不每轮都发言
3. 只叙述已发生和正在发生的事——不描述"将要"
4. **每次 chatgroup 输出控制在 150 字以内**，精炼高效，必须一次输出完成，不要分多次发送同一个场景
5. 工具调用在 1-2 轮内完成，不要多轮请求
6. 叙述精炼，像优秀小说的叙述段落''';

  Future<String?> toggleSimulatorMode(GroupChat group, bool enabled) async {
    if (enabled) {
      final narrator = Agent(
        name: '旁白',
        gender: '其他',
        description: '群聊旁白叙述者',
        persona: narratorPersonaTemplate.replaceAll(
          '{{WORLD_SETTING}}',
          group.worldSetting ?? '（未设定）',
        ),
        sourceGroupId: group.id,
        isSimCharacter: true,
        isActive: true,
      );
      await DatabaseService.insertAgent(narrator);

      final member = GroupMember(
        agentId: narrator.id,
        groupId: group.id,
        role: 'moderator',
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await DatabaseService.insertGroupMember(member);

      await _groupService.updateGroup(
        group.copyWith(
          isSimulatorMode: true,
          openingSpeakerAgentId: narrator.id,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (state.activeGroup?.id == group.id) {
        state = state.copyWith(
          activeGroup: state.activeGroup!.copyWith(isSimulatorMode: true),
        );
        await loadGroup(group.id);
      }
      return narrator.id;
    } else {
      final members = await _groupService.getMembers(group.id);
      for (final m in members) {
        try {
          final agent = await DatabaseService.getAgent(m.agentId);
          if (agent != null &&
              agent.isSimCharacter &&
              agent.sourceGroupId == group.id) {
            await DatabaseService.deleteGroupMember(m.id!);
            await DatabaseService.deleteAgent(agent.id);
          }
        } catch (_) {}
      }
      unawaited(ProactiveCareAlarmScheduler.sync());
      await _groupService.updateGroup(
        group.copyWith(
          isSimulatorMode: false,
          worldSetting: null,
          clearOpeningSpeakerAgentId: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (state.activeGroup?.id == group.id) {
        state = state.copyWith(
          activeGroup: state.activeGroup!.copyWith(
            isSimulatorMode: false,
            worldSetting: null,
          ),
        );
        await loadGroup(group.id);
      }
      return null;
    }
  }

  Future<void> updateWorldSetting(GroupChat group, String setting) async {
    await _groupService.updateGroup(
      group.copyWith(
        worldSetting: setting,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (state.activeGroup?.id == group.id) {
      state = state.copyWith(
        activeGroup: state.activeGroup!.copyWith(worldSetting: setting),
      );
    }
  }

  bool get userInterrupted => _userInterrupted;

  Future<void> clearMessages(String groupId) async {
    await DatabaseService.clearGroupMessages(groupId);
    await _groupService.clearShortTerm(groupId);
    state = state.copyWith(messages: []);
  }

  Future<void> deleteMessageFrom(int index) async {
    final msgs = state.messages;
    if (index < 0 || index >= msgs.length) return;
    final toDelete = msgs.sublist(index);
    for (final msg in toDelete) {
      if (msg.id != null) {
        await DatabaseService.deleteGroupMessage(msg.id!);
      }
    }
    state = state.copyWith(messages: msgs.sublist(0, index));
  }

  /// 重新生成最近一轮群聊回复：移除最后一条用户消息之后的所有智能体回复并重新触发发言。
  /// 注意：群聊短期记忆中旧的智能体回复不会被清理，可能对重新生成结果有轻微影响。
  Future<void> regenerateLastReplies(String groupId) async {
    if (state.isLoading) return;
    final msgs = state.messages;
    if (msgs.isEmpty) return;

    // 找到最后一条用户消息
    int lastUserIdx = -1;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isUser) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx < 0) return;

    // 删除该用户消息之后的所有智能体回复（DB + state）
    final toDelete = msgs.sublist(lastUserIdx + 1);
    for (final msg in toDelete) {
      if (msg.id != null) {
        await DatabaseService.deleteGroupMessage(msg.id!);
      }
    }
    state = state.copyWith(messages: msgs.sublist(0, lastUserIdx + 1));

    // 重新触发发言流程
    _groupService.maxShortTermRounds = _ref
        .read(settingsProvider)
        .maxShortTermRounds;
    state = state.copyWith(isLoading: true);
    _userInterrupted = false;
    await _runSpeakers(groupId);
  }
}

class _GroupToolResult {
  final String? content;
  final List<ToolExecutionLog> toolLogs;
  const _GroupToolResult({this.content, this.toolLogs = const []});
}

/// 一轮群聊补全的本地渐进事件组装结果。
class _GroupStreamRound {
  final String? finishReason;
  final List<Map<String, dynamic>> toolCalls;
  final String? content;
  final Map<String, dynamic>? assistantMessage;
  const _GroupStreamRound({
    this.finishReason,
    this.toolCalls = const [],
    this.content,
    this.assistantMessage,
  });
}

void _glog(String msg) {
  debugPrint('[GroupProvider] $msg');
}

final groupProvider = StateNotifierProvider<GroupNotifier, GroupState>((ref) {
  return GroupNotifier(ref, ref.read(groupServiceProvider));
});
