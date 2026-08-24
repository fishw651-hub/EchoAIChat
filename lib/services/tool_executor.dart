import 'dart:async';

import 'memory_service.dart';
import 'plan_service.dart';
import 'group_service.dart';
import 'database_service.dart';
import 'proactive_care_alarm.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/group_shared_memory.dart';
import '../models/agent.dart';
import '../models/group_member.dart';
import 'package:flutter/foundation.dart';

void _tlog(String msg) {
  debugPrint('[AIchat][Tool] $msg');
}

class ToolExecutor {
  final MemoryService memoryService;
  final PlanService planService;
  final GroupService? groupService;
  final VoidCallback? onAgentsChanged;
  final List<ToolExecutionLog> executionLogs = [];

  void clearLogs() => executionLogs.clear();

  ToolExecutor({
    required this.memoryService,
    required this.planService,
    this.groupService,
    this.onAgentsChanged,
  });

  Future<String> execute(
    String toolName,
    Map<String, dynamic> arguments, {
    String? agentId,
  }) async {
    String result;
    _tlog('▼ EXECUTE $toolName');
    _tlog('  args: $arguments');
    switch (toolName) {
      case 'remember':
        result = await _handleRemember(arguments);
        break;
      case 'forget':
        result = await _handleForget(arguments);
        break;
      case 'chat':
        result = await _handleChat(arguments);
        break;
      case 'chatgroup':
        result = await _handleChatgroup(arguments);
        break;
      case 'plan':
        result = await _handlePlan(arguments, agentId: agentId);
        break;
      case 'manage_character':
        result = await _handleManageCharacter(arguments);
        break;
      default:
        result = '未知工具: $toolName';
    }
    _tlog('  result: $result');
    executionLogs.add(
      ToolExecutionLog(
        toolName: toolName,
        arguments: arguments,
        result: result,
      ),
    );
    return result;
  }

  /// remember 工具：创建/更新长期记忆，或向基础记忆追加事件
  Future<String> _handleRemember(Map<String, dynamic> args) async {
    final memoryType = args['memory_type'] as String;
    final action = args['action'] as String;
    final targetId = args['target_id'] as String?;
    final field = args['field'] as String?;
    final content = args['content'] as String?;
    final groupScope = args['group_scope'] as String?;

    if (content == null || content.isEmpty) {
      return '错误: 缺少 content 参数';
    }

    if (groupScope == 'shared' && groupService != null) {
      if (action == 'create') {
        final newId = await groupService!.createSharedMemory(
          groupId: groupService!.activeGroupId ?? '',
          field: field ?? 'status',
          content: content,
        );
        return '已创建群共享记忆 $newId [$field]: $content';
      } else if (action == 'update') {
        if (targetId == null) {
          return '错误: update 操作需要 target_id';
        }
        final mems = await groupService!.getSharedMemories(
          groupService!.activeGroupId ?? '',
        );
        final existing = mems.cast<GroupSharedMemory?>().firstWhere(
          (m) => m?.id == targetId,
          orElse: () => null,
        );
        if (existing != null) {
          await groupService!.updateSharedMemory(
            existing.copyWith(content: content, field: field ?? existing.field),
          );
          return '已更新群共享记忆 $targetId: $content';
        }
        return '错误: 未找到群共享记忆 $targetId';
      }
      return '错误: 无效的 action';
    }

    if (memoryType == 'long_term') {
      if (action == 'create') {
        if (field == null || !LongTermMemory.validFields.contains(field)) {
          return '错误: field 必须是 ${LongTermMemory.validFields.join(", ")} 之一';
        }
        final newId = await memoryService.createLongTermMemory(
          field: field,
          content: content,
        );
        return '已创建 $newId [$field]: $content';
      } else if (action == 'update') {
        if (targetId == null) {
          return '错误: update 操作需要 target_id';
        }
        await memoryService.updateLongTermMemory(
          targetId: targetId,
          content: content,
          field: field,
        );
        return '已更新 $targetId: $content';
      }
    } else if (memoryType == 'base') {
      if (action == 'create') {
        final newId = await memoryService.createBaseMemory(
          type: 'event',
          content: content,
        );
        return '已创建基础事件 $newId: $content';
      }
    }
    return '错误: 无效的 memory_type 或 action';
  }

  /// forget 工具：删除长期记忆条目或基础事件条目
  Future<String> _handleForget(Map<String, dynamic> args) async {
    final targetIds = args['target_ids'] as List<dynamic>?;
    if (targetIds == null || targetIds.isEmpty) {
      return '错误: target_ids 为空';
    }

    final memorySource = args['memory_source'] as String?;
    if (memorySource == 'shared' && groupService != null) {
      final deleted = <String>[];
      for (final id in targetIds) {
        final idStr = id.toString();
        if (idStr.startsWith('GS')) {
          await groupService!.deleteSharedMemory(idStr);
          deleted.add(idStr);
        }
      }
      return deleted.isNotEmpty
          ? '已删除群共享记忆 ${deleted.join(", ")}'
          : '无有效群共享记忆ID可删除';
    }

    final deleted = <String>[];
    final errors = <String>[];

    for (final id in targetIds) {
      final idStr = id.toString();
      if (idStr.startsWith('L')) {
        await memoryService.deleteLongTermMemory(idStr);
        deleted.add(idStr);
      } else if (idStr.startsWith('B')) {
        final all = await memoryService.getBaseMemories();
        final target = all.cast<BaseMemory?>().firstWhere(
          (m) => m?.id == idStr,
          orElse: () => null,
        );
        if (target == null) {
          errors.add('未找到 $idStr');
        } else if (target.isSetting) {
          errors.add('$idStr 是设定条目，不可通过 AI 遗忘');
        } else {
          await memoryService.deleteBaseMemory(idStr);
          deleted.add(idStr);
        }
      } else {
        errors.add('无效序号格式: $idStr');
      }
    }

    final resultParts = <String>[];
    if (deleted.isNotEmpty) resultParts.add('已删除 ${deleted.join(", ")}');
    if (errors.isNotEmpty) resultParts.add('错误: ${errors.join("; ")}');
    return resultParts.join('；');
  }

  // chat 工具不在此执行，由 chat_provider 在调用后直接 display
  // 该方法的返回值仅作为 tool role 的消息
  Future<String> _handleChat(Map<String, dynamic> args) async {
    final message = args['message'] as String? ?? '';
    return 'chat 工具已收到消息: $message';
  }

  Future<String> _handleChatgroup(Map<String, dynamic> args) async {
    final message = args['message'] as String? ?? '';
    return 'chatgroup 工具已收到消息: $message';
  }

  /// plan 工具：安排未来消息
  Future<String> _handlePlan(
    Map<String, dynamic> args, {
    String? agentId,
  }) async {
    final sendTime = args['send_time'] as String;
    final message = args['message'] as String;
    try {
      final scheduledTime = PlanService.parseSendTime(sendTime);
      await planService.scheduleMessage(
        scheduledTime: scheduledTime,
        message: message,
        agentId: agentId,
      );
      return '已计划在 $sendTime 发送消息: "$message"';
    } catch (e) {
      return '计划失败: $e';
    }
  }

  Future<String> _handleManageCharacter(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? '';
    final name = args['name'] as String? ?? '';

    if (action == 'add') {
      final gender = args['gender'] as String? ?? '其他';
      final description = args['description'] as String? ?? '';
      final persona = args['persona'] as String? ?? '';
      if (persona.isEmpty) return '错误: add 操作需要 persona';

      final gid = groupService?.activeGroupId;
      if (gid == null || gid.isEmpty) return '错误: 未在群聊上下文中';

      final allAgents = await DatabaseService.getAgents();
      final dup = allAgents
          .where(
            (a) =>
                a.name.trim().toLowerCase() == name.trim().toLowerCase() &&
                a.sourceGroupId == gid &&
                a.isSimCharacter,
          )
          .firstOrNull;
      if (dup != null) return '角色 "$name" 已存在于本群，创建失败。如需重建请先移除旧角色或换一个名字。';

      final agent = Agent(
        name: name,
        gender: gender,
        description: description,
        persona: persona,
        sourceGroupId: gid,
        isSimCharacter: true,
        isActive: true,
      );
      await DatabaseService.insertAgent(agent);
      final member = GroupMember(
        agentId: agent.id,
        groupId: gid,
        role: 'member',
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await DatabaseService.insertGroupMember(member);
      onAgentsChanged?.call();
      return '已创建角色 "$name" 并加入群聊';
    } else if (action == 'remove') {
      final target = args['target'] as String? ?? name;
      final gid = groupService?.activeGroupId;
      if (gid == null || gid.isEmpty) return '错误: 未在群聊上下文中';

      final members = await DatabaseService.getGroupMembers(gid);
      for (final m in members) {
        final agent = await DatabaseService.getAgent(m.agentId);
        if (agent != null &&
            agent.isSimCharacter &&
            (agent.name == target || agent.id == target)) {
          await DatabaseService.deleteGroupMember(m.id!);
          await DatabaseService.deleteAgent(agent.id);
          unawaited(ProactiveCareAlarmScheduler.sync());
          onAgentsChanged?.call();
          return '已移除角色 "$target"';
        }
      }
      return '未找到角色 "$target"';
    }
    return '错误: 无效的 action';
  }
}

/// 工具执行日志条目
class ToolExecutionLog {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String result;
  final DateTime timestamp;

  ToolExecutionLog({
    required this.toolName,
    required this.arguments,
    required this.result,
  }) : timestamp = DateTime.now();
}
