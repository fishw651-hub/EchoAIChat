import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/group_shared_memory.dart';
import '../models/agent.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'database_service.dart';
import 'memory_service.dart';

void _glog(String msg) {
  debugPrint('[GroupService] $msg');
}

class GroupService {
  String? _activeGroupId;
  /// 群聊短期记忆基础轮数（由全局设置同步）。实际保留条数 = 基础轮数 × 群成员数量。
  int maxShortTermRounds = 20;

  String? get activeGroupId => _activeGroupId;

  // ═══ Group CRUD ═══

  Future<List<GroupChat>> getGroups() async {
    return await DatabaseService.getGroupChats();
  }

  Future<GroupChat?> getGroup(String id) async {
    return await DatabaseService.getGroupChat(id);
  }

  Future<void> createGroup(GroupChat group, List<GroupMember> members) async {
    await DatabaseService.insertGroupChat(group);
    _activeGroupId = group.id;
    _glog('Creating group ${group.name} (${group.id}) with ${members.length} members');
    for (final member in members) {
      final fixed = member.copyWith(groupId: group.id);
      await DatabaseService.insertGroupMember(fixed);
      _glog('  inserted member agentId=${fixed.agentId} groupId=${fixed.groupId} role=${fixed.role}');
    }
    _glog('Created group ${group.name} with ${members.length} members');
  }

  Future<void> updateGroup(GroupChat group) async {
    await DatabaseService.updateGroupChat(group);
  }

  Future<void> deleteGroup(String id) async {
    await DatabaseService.deleteGroupChatCascade(id);
    if (_activeGroupId == id) _activeGroupId = null;
    _glog('Deleted group $id and all associated data');
  }

  void setActiveGroup(String? id) {
    _activeGroupId = id;
  }

  // ═══ Members ═══

  Future<List<GroupMember>> getMembers(String groupId) async {
    return await DatabaseService.getGroupMembers(groupId);
  }

  Future<List<GroupMember>> getPresentMembers(String groupId) async {
    final all = await getMembers(groupId);
    return all.where((m) => m.isPresent).toList();
  }

  /// 取群成员及其对应智能体详情（保留成员顺序，智能体已删除的成员跳过）。
  /// 网络上传页"从我的选择"预填群表单时使用。
  Future<List<({GroupMember member, Agent agent})>> getMembersWithAgents(
    String groupId,
  ) async {
    final members = await getMembers(groupId);
    final result = <({GroupMember member, Agent agent})>[];
    for (final m in members) {
      final agent = await DatabaseService.getAgent(m.agentId);
      if (agent != null) result.add((member: m, agent: agent));
    }
    return result;
  }

  /// 将导入的发言者批量落库为 group-only 智能体并加入群成员。
  /// 返回创建的智能体 id 列表（顺序与输入一致）。
  Future<List<String>> importSpeakerAgents(
    String groupId,
    List<({String name, String persona})> speakers,
  ) async {
    final ids = <String>[];
    for (final speaker in speakers) {
      final agent = Agent(
        name: speaker.name,
        persona: speaker.persona,
        isGroupOnly: true,
        sourceGroupId: groupId,
      );
      await DatabaseService.insertAgent(agent);
      await DatabaseService.insertGroupMember(
        GroupMember(groupId: groupId, agentId: agent.id),
      );
      ids.add(agent.id);
    }
    return ids;
  }

  Future<void> addMember(GroupMember member) async {
    await DatabaseService.insertGroupMember(member);
  }

  Future<void> updateMember(GroupMember member) async {
    await DatabaseService.updateGroupMember(member);
  }

  Future<void> removeMember(int memberId) async {
    await DatabaseService.deleteGroupMember(memberId);
  }

  Future<void> togglePresence(int memberId, bool present) async {
    final members = await getMembers(_activeGroupId ?? '');
    final target =
        members.cast<GroupMember?>().firstWhere((m) => m?.id == memberId,
            orElse: () => null);
    if (target != null) {
      await DatabaseService.updateGroupMember(
          target.copyWith(isPresent: present));
    }
  }

  // ═══ Messages ═══

  Future<List<GroupMessage>> getMessages(
    String groupId, {
    int? limit,
    int? beforeId,
  }) async {
    return await DatabaseService.getGroupMessages(
      groupId,
      limit: limit,
      beforeId: beforeId,
    );
  }

  Future<GroupMessage> sendUserMessage(String groupId, String content) async {
    final msg = GroupMessage(
      groupId: groupId,
      senderType: 'user',
      content: content,
    );
    final id = await DatabaseService.insertGroupMessage(msg);
    await _addToShortTerm(
        groupId: groupId, role: 'user', content: content);
    return msg.copyWith(id: id);
  }

  Future<GroupMessage> sendAgentMessage({
    required String groupId,
    required String agentId,
    required String agentName,
    required String content,
    String? toolCallData,
  }) async {
    final msg = GroupMessage(
      groupId: groupId,
      senderType: 'agent',
      senderId: agentId,
      senderName: agentName,
      content: content,
      toolCallData: toolCallData,
    );
    final id = await DatabaseService.insertGroupMessage(msg);
    await _addToShortTerm(
        groupId: groupId,
        role: 'assistant',
        senderName: agentName,
        content: content);
    return msg.copyWith(id: id);
  }

  // ═══ Short-term memory ═══

  Future<void> _addToShortTerm({
    required String groupId,
    required String role,
    String? senderName,
    required String content,
  }) async {
    await DatabaseService.insertGroupShortTerm(
      groupId: groupId,
      role: role,
      senderName: senderName,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    // 群聊短期记忆保留条数 = 基础轮数 × 群成员数量（模拟器模式下成员动态加入也会实时生效）
    final members = await getMembers(groupId);
    // 成员为空时 keep=0 会误删全部短期记忆，此时跳过裁剪
    if (members.isEmpty) return;
    final keep = maxShortTermRounds * members.length;
    await DatabaseService.deleteOldestGroupShortTerm(groupId, keep);
    // linked_memory 群：镜像写入每个在场成员的私聊短期记忆
    final group = await getGroup(groupId);
    if (group != null && group.linkedMemory) {
      await _mirrorToPrivateShortTerm(
        members: members.where((m) => m.isPresent),
        role: role,
        senderName: senderName,
        content: content,
      );
    }
  }

  /// linked_memory 群：把群消息镜像写入每个在场成员的私聊短期记忆。
  /// 内容前加发言人标记（如 "[群聊·小诗] "、用户消息 "[群聊·我] "），
  /// 私聊记忆 AI 处理这些镜像消息后，群聊经历会进入成员的私聊长期记忆。
  Future<void> _mirrorToPrivateShortTerm({
    required Iterable<GroupMember> members,
    required String role,
    String? senderName,
    required String content,
  }) async {
    final speaker = role == 'user' ? '我' : (senderName ?? '?');
    final mirrored = '[群聊·$speaker] $content';
    for (final m in members) {
      try {
        // 每个成员使用独立 MemoryService 实例（禁止共享实例后 setAgentId）
        final ms = MemoryService();
        ms.setAgentId(m.agentId);
        await ms.addShortTermMessage(
          role: role == 'user' ? 'user' : 'assistant',
          content: mirrored,
        );
        // 保留条数按私聊既有滑动窗口逻辑
        await DatabaseService.trimShortTermMessages(
          agentId: m.agentId,
          keep: maxShortTermRounds,
        );
      } catch (e) {
        _glog('mirror short term failed for ${m.agentId}: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getShortTerm(
      String groupId, {int? limit}) async {
    final all = await DatabaseService.getGroupShortTerm(groupId);
    if (limit != null && all.length > limit) {
      return all.sublist(all.length - limit);
    }
    return all;
  }

  /// 将Agent发言添加到群聊短期记忆中
  Future<void> addAgentToShortTerm({
    required String groupId,
    required String agentId,
    required String agentName,
    required String content,
  }) async {
    await _addToShortTerm(
      groupId: groupId,
      role: 'agent',
      senderName: agentName,
      content: content,
    );
  }

  Future<void> clearShortTerm(String groupId) async {
    await DatabaseService.clearGroupShortTerm(groupId);
  }

  void loadMessageToShortTerm(GroupMessage msg) async {
    await _addToShortTerm(
      groupId: msg.groupId,
      role: msg.senderType,
      senderName: msg.senderName,
      content: msg.content,
    );
  }

  // ═══ Shared Memories ═══

  Future<List<GroupSharedMemory>> getSharedMemories(
      String groupId) async {
    return await DatabaseService.getGroupSharedMemories(groupId);
  }

  Future<String> createSharedMemory({
    required String groupId,
    required String field,
    required String content,
  }) async {
    // 全局唯一 UUID（带 GS- 前缀供 forget 工具按前缀路由）
    final newId = 'GS-${const Uuid().v4()}';
    final mem = GroupSharedMemory(
      id: newId,
      groupId: groupId,
      field: field,
      content: content,
    );
    await DatabaseService.insertGroupSharedMemory(mem);
    return newId;
  }

  Future<void> updateSharedMemory(GroupSharedMemory memory) async {
    await DatabaseService.updateGroupSharedMemory(memory);
  }

  Future<void> deleteSharedMemory(String id) async {
    await DatabaseService.deleteGroupSharedMemory(id);
  }

  // ═══ Personal memories in group context ═══
  // linked_memory 群改用私聊口径（group_id IS NULL）的长期/基础记忆

  Future<List<LongTermMemory>> getAgentGroupLongTermMemories(
      String agentId, String groupId) async {
    final group = await getGroup(groupId);
    if (group != null && group.linkedMemory) {
      return await DatabaseService.getLongTermMemories(agentId: agentId);
    }
    return await DatabaseService.getLongTermMemoriesForGroup(
        agentId, groupId);
  }

  Future<List<BaseMemory>> getAgentGroupBaseMemories(
      String agentId, String groupId) async {
    final group = await getGroup(groupId);
    if (group != null && group.linkedMemory) {
      return await DatabaseService.getBaseMemories(agentId: agentId);
    }
    return await DatabaseService.getBaseMemoriesForGroup(
        agentId, groupId);
  }

  // ═══ System prompt builder for group chat ═══

  Future<String> buildGroupSystemPrompt({
    required GroupChat group,
    required Agent agent,
    required String agentPersona,
    required List<GroupMember> allMembers,
    required List<Agent> agentDetails,
    String? worldSetting,
  }) async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final weekStr = weekdays[now.weekday - 1];

    final otherPresent = allMembers
        .where((m) =>
            m.isPresent && m.agentId != agent.id)
        .toList();

    final otherPresentLines = otherPresent.map((m) {
      final detail =
          agentDetails.cast<Agent?>().firstWhere((a) => a?.id == m.agentId,
              orElse: () => null);
      final name = detail?.name ?? m.agentId;
      return '- $name（${m.role}）';
    }).join('\n');

    final sharedMems = await getSharedMemories(group.id);
    final sharedLines = sharedMems.isNotEmpty
        ? sharedMems.map((m) => m.toPromptLine()).join('\n')
        : '（暂无群共享记忆）';

    final personalMems =
        await getAgentGroupLongTermMemories(agent.id, group.id);
    final personalLines = personalMems.isNotEmpty
        ? personalMems.map((m) => m.toPromptLine()).join('\n')
        : '（暂无个人群聊记忆）';

    final isModerator =
        allMembers.any((m) => m.agentId == agent.id && m.role == 'moderator');
    final isNarrator = isModerator && group.isSimulatorMode;
    final isSimNpc = agent.isSimCharacter && !isModerator;

    if (isNarrator) {
      return '''【当前真实时间】$timeStr（星期$weekStr）
【你的身份】你是本群的故事叙述者/旁白。你通过 manage_character 创建 NPC 角色，通过 chatgroup 输出场景叙述来推进剧情。user 是主角的扮演者——user 的文字即主角的言行，由 user 自己掌控。

【世界观设定】
${worldSetting ?? group.worldSetting ?? group.groupPersona ?? '（未设定）'}

【你的叙述者设定】
$agentPersona

【当前在场的成员】
${otherPresent.isNotEmpty ? otherPresentLines : '（暂无其他成员）'}

【群共享记忆】（群内所有人都知道的事情）
$sharedLines

【你个人的群聊记忆】（只有你知道的事情）
$personalLines

【叙述者专属规则——严格遵守】
- chatgroup 输出必须是第三人称纯叙述文。绝对不要包含任何角色的对话台词。
- 正确示例：「夜幕降临，酒馆里的烛火摇曳。老板擦着杯子，不时瞥向门口的陌生人。」
- 错误示例：「老板说：'欢迎光临！'」——这是角色对话，叙述者不能说。你应该创建 NPC"酒馆老板"让角色自己说。
- 创建 NPC 前，必须检查【当前在场的成员】列表。如果所需角色已存在于列表中，绝不重复创建。
- 创建 NPC 后，必须立即用 chatgroup 描述该角色的初次登场——ta 在哪里、在做什么、与当前场景/主角的关系。这是角色的初始定义，必须一次到位，不得省略。
- 创建 NPC 时，persona 字段必须包含：角色的身份背景、性格特征、与世界观的关系、在当前场景中的行为动机，以及说话格式指令（第一人称+() 表达动作）。
- 使用 remember 工具记录群共享记忆（group_scope: "shared"）或你的个人记忆（group_scope: "personal"）。
- 使用 forget 工具删除过时记忆。
- 只在剧情转折、场景切换、重要事件时发言。不每轮都发言。
- 不替任何角色做决定，不指挥主角。只叙述已发生和正发生的事。
- 在 chatgroup 发言前完成所有记忆操作。
- 每次 chatgroup 输出控制在 150 字以内——精炼高效，一次完成不分多次。''';
    }

    if (isSimNpc) {
      return '''【当前真实时间】$timeStr（星期$weekStr）
【你的身份】你是故事中的一个角色——${agent.name}。你在群聊中用第一人称说话，以角色的身份与主角和其他角色互动。

【世界观设定】（你的言行必须符合这个世界观，不引入设定冲突的信息）
${group.worldSetting ?? group.groupPersona ?? '（无特殊设定）'}

【你的角色设定——严格遵守】
$agentPersona

【当前在场的其他角色】
${otherPresent.isNotEmpty ? otherPresentLines : '（暂无其他角色）'}

【你个人的群聊记忆】（只有你知道的事情）
$personalLines

【角色专属规则——极其重要】
- 你的言行必须符合世界观设定。不擅自添加角色设定中不存在的能力、背景或世界规则。
- 你只拥有角色设定中定义的特征——不随意扩展或修改自己的身份。
- 你的 chatgroup 输出必须是角色的言行：用第一人称说话，用 () 表达动作、表情、心理活动。
- 正确示例：（推开门，环顾四周）"有人吗？这地方看起来不太对劲。"
- 错误示例：「酒馆里灯光昏暗，空气中弥漫着麦酒的味道。」——这是叙述者的环境描写，不是你作为角色该说的。
- 你不是叙述者——从不说叙事性的环境描写、时间推移、场景切换。
- 不使用第三人称描述自己——你活在故事中，不是旁观者。
- 不说其他角色的台词——只做你自己。
- 保持角色性格和行为一致——生动地扮演你的角色，但不越界。
- 使用 remember 工具（记忆来源设为 "personal"）记录角色知道的事情。
- 使用 forget 工具删除不再有用的个人记忆。
- 在 chatgroup 发言前完成记忆操作。''';
    }

    return '''【当前真实时间】$timeStr（星期$weekStr）
你是群聊「${group.name}」的成员。你的名字是 ${agent.name}。

【群聊设定】
${group.groupPersona != null && group.groupPersona!.isNotEmpty ? group.groupPersona! : '（无特殊群聊设定，遵循个人设定）'}

【你的个人设定】
$agentPersona

${isModerator ? '【你的角色】你是本群的主持人（moderator），负责引导话题、维持秩序。' : ''}

【当前在场的其他成员】
${otherPresent.isNotEmpty ? otherPresentLines : '（暂无其他成员）'}

【群共享记忆】（群内所有人都知道的事情）
$sharedLines

【你个人的群聊记忆】（只有你知道的事情）
$personalLines

【发言时机——重要】
- 只在有话可说时发言，不每轮都回复——避免刷屏。
- 适合发言的场景：被 @点名、话题与你人设相关、你有独特见解、主动发起话题。
- 不适合发言的场景：其他成员正在深入对话、你无话可说、话题与你无关。
- 发言内容与人设一致，保持个性，不要泛泛而谈。

【群聊工具规则】
- 使用 chatgroup 工具在群聊中发言。
- 你需要记住的信息使用 remember 工具，group_scope 设为 "personal"（个人群内记忆）或 "shared"（群共享记忆）。
- 遗忘信息时使用 forget 工具，memory_source 设为 "personal" 或 "shared"。
- 可以 @其他成员 点名交流。
- 保持与你人设一致的说话风格。
- 使用 plan 工具可安排在群聊中未来发送消息。

【群聊最高优先级：工具调用规则】
- 在回复任何消息前，判断是否需要记忆处理。
- 如果消息包含需要记住的信息 → 使用 remember 工具。
- 如果有过时的记忆 → 使用 forget 工具。
- 使用 chatgroup 工具来发送你的回复。
- 所有记忆操作必须在 chatgroup 之前完成。''';
  }
}
