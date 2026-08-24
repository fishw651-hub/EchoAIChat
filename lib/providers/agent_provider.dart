import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/proactive_care_alarm.dart';
import 'agent_folder_provider.dart';

/// 将服务器返回的智能体资料合并到本地记录。
///
/// 本地 UUID 是 SQLite 主键，云端资料刷新时必须保留它，否则后续
/// `updateAgent` 会按一个新生成的 UUID 更新 0 行。
Agent mergeCloudAgent(Map<String, dynamic> json, Agent? existing) {
  return Agent(
    id: existing?.id ?? (json['client_id'] as String?),
    name: json['name'] as String? ?? '',
    gender: json['gender'] as String? ?? '',
    description: json['description'] as String? ?? '',
    persona: json['persona'] as String? ?? '',
    openingLine: json['opening_line'] as String?,
    avatarColor: json['avatar_color'] as int? ?? 0xFFE8F5E9,
    avatarPath: json['avatar_path'] as String?,
    chatBackground: json['chat_background'] as String?,
    worldview: json['worldview'] as String? ?? '',
    isSimCharacter: json['is_sim_character'] as bool? ?? false,
    isGroupOnly: json['is_group_only'] as bool? ?? false,
    realInfoEnabled: json['real_info_enabled'] as bool? ?? false,
    proactiveCareEnabled: json['proactive_care_enabled'] as bool? ?? false,
    proactiveCareDailyLimit: json['proactive_care_daily_limit'] as int? ?? 1,
    proactiveCareMinIntervalHours:
        json['proactive_care_min_interval_hours'] as int? ?? 3,
    maxResponseLength:
        (json['max_response_length'] as num?)?.toInt() ??
        Agent.defaultResponseLength,
    isActive: existing?.isActive ?? false,
    networkId: existing?.networkId,
    networkUploaderId: existing?.networkUploaderId,
    networkSource: existing?.networkSource ?? 'none',
    networkVersion: existing?.networkVersion,
    createdAt: existing?.createdAt,
  );
}

class AgentNotifier extends StateNotifier<AgentState> {
  static Future<void> Function(Agent agent)? onAgentSaved;

  final Ref _ref;

  AgentNotifier(this._ref) : super(const AgentState()) {
    _init();
  }

  Future<void> _init() async {
    final agents = await DatabaseService.getAgents();
    final active = agents.where((a) => a.isActive).firstOrNull;
    if (active != null) {
      state = state.copyWith(agents: agents, currentAgent: active);
    } else if (agents.isNotEmpty) {
      await setActiveAgent(agents.first.id);
    }
  }

  List<Agent> get agents => state.agents;
  Agent? get currentAgent => state.currentAgent;

  Future<Agent> createAgent({
    required String name,
    String gender = '',
    String description = '',
    required String persona,
    String? openingLine,
    int avatarColor = 0xFFE8F5E9,
    String worldview = '',
    bool realInfoEnabled = false,
    bool proactiveCareEnabled = false,
    int proactiveCareDailyLimit = 1,
    int proactiveCareMinIntervalHours = 3,
    int maxResponseLength = Agent.defaultResponseLength,
  }) async {
    final agent = Agent(
      name: name,
      gender: gender,
      description: description,
      persona: persona,
      openingLine: openingLine,
      avatarColor: avatarColor,
      worldview: worldview,
      isActive: true,
      realInfoEnabled: realInfoEnabled,
      proactiveCareEnabled: proactiveCareEnabled,
      proactiveCareDailyLimit: proactiveCareDailyLimit,
      proactiveCareMinIntervalHours: proactiveCareMinIntervalHours,
      maxResponseLength: maxResponseLength,
    );
    await DatabaseService.insertAgent(agent);
    await DatabaseService.setActiveAgent(agent.id);
    state = state.copyWith(
      agents: [...state.agents, agent],
      currentAgent: agent,
    );
    await _notifyAgentSaved(agent);
    unawaited(ProactiveCareAlarmScheduler.sync());
    return agent;
  }

  Future<void> updateAgent(Agent agent) async {
    await DatabaseService.updateAgent(agent);
    final agents = state.agents
        .map((a) => a.id == agent.id ? agent : a)
        .toList();
    final current = agent.id == state.currentAgent?.id
        ? agent
        : state.currentAgent;
    state = state.copyWith(agents: agents, currentAgent: current);
    await _notifyAgentSaved(agent);
    unawaited(ProactiveCareAlarmScheduler.sync());
  }

  Future<void> _notifyAgentSaved(Agent agent) async {
    final callback = onAgentSaved;
    if (callback == null) return;
    try {
      await callback(agent);
    } catch (error) {
      debugPrint('[Agent] server registration deferred: $error');
    }
  }

  Future<void> deleteAgent(String id) async {
    await DatabaseService.deleteAgent(id);
    final agents = state.agents.where((a) => a.id != id).toList();
    if (state.currentAgent?.id == id) {
      if (agents.isNotEmpty) {
        await DatabaseService.setActiveAgent(agents.first.id);
        state = state.copyWith(agents: agents, currentAgent: agents.first);
      } else {
        state = AgentState(agents: agents, currentAgent: null);
      }
    } else {
      state = state.copyWith(agents: agents);
    }
    // DB 删除会级联清掉 agent_folder_members 映射，这里同步刷新编组状态，
    // 调用方无需再自行 refresh agentFolderProvider
    unawaited(_ref.read(agentFolderProvider.notifier).refresh());
    unawaited(ProactiveCareAlarmScheduler.sync());
  }

  /// 导入外部智能体（分享码兑换等）：只插入并刷新列表，不设为当前智能体
  Future<void> importAgent(Agent agent) async {
    await DatabaseService.insertAgent(agent);
    await refresh();
    unawaited(ProactiveCareAlarmScheduler.sync());
  }

  Future<void> setActiveAgent(String id) async {
    await DatabaseService.setActiveAgent(id);
    final newActive = state.agents.where((a) => a.id == id).firstOrNull;
    if (newActive == null) {
      // state 中找不到该 id，从 DB 刷新避免状态不一致
      await refresh();
      return;
    }
    state = state.copyWith(currentAgent: newActive);
  }

  Future<void> refresh() async {
    final agents = await DatabaseService.getAgents();
    final active = agents.where((a) => a.isActive).firstOrNull;
    state = state.copyWith(
      agents: agents,
      currentAgent: active ?? state.currentAgent,
    );
  }

  /// 将所有本地智能体上传到云端
  Future<void> syncToServer(AuthService svc) async {
    final agents = await DatabaseService.getAgents();
    for (final agent in agents) {
      await svc.saveAgent(
        clientId: agent.id,
        name: agent.name,
        gender: agent.gender,
        description: agent.description,
        persona: agent.persona,
        openingLine: agent.openingLine,
        avatarColor: agent.avatarColor,
        avatarPath: agent.avatarPath,
        chatBackground: agent.chatBackground,
        worldview: agent.worldview,
        isSimCharacter: agent.isSimCharacter,
        maxResponseLength: agent.maxResponseLength,
        realInfoEnabled: agent.realInfoEnabled,
        proactiveCareEnabled: agent.proactiveCareEnabled,
        proactiveCareDailyLimit: agent.proactiveCareDailyLimit,
        proactiveCareMinIntervalHours: agent.proactiveCareMinIntervalHours,
      );
    }
  }

  /// 从云端下载智能体并合并到本地
  Future<void> syncFromServer(AuthService svc) async {
    final cloudList = await svc.fetchMyAgents();
    final localAgents = await DatabaseService.getAgents();
    final localByName = <String, Agent>{};
    for (final local in localAgents) {
      localByName.putIfAbsent(local.name, () => local);
    }

    for (final json in cloudList) {
      final cloudName = json['name'] as String? ?? '';
      if (cloudName.isEmpty) continue;

      final existing = localByName[cloudName];
      final agent = mergeCloudAgent(json, existing);

      if (existing != null) {
        await DatabaseService.updateAgent(agent);
      } else {
        await DatabaseService.insertAgent(agent);
        if (localAgents.isEmpty) {
          await DatabaseService.setActiveAgent(agent.id);
        }
      }
      localByName[cloudName] = agent;
    }

    await refresh();
  }
}

class AgentState {
  final List<Agent> agents;
  final Agent? currentAgent;

  const AgentState({this.agents = const [], this.currentAgent});

  AgentState copyWith({List<Agent>? agents, Agent? currentAgent}) {
    return AgentState(
      agents: agents ?? this.agents,
      currentAgent: currentAgent ?? this.currentAgent,
    );
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>(
  (ref) => AgentNotifier(ref),
);
