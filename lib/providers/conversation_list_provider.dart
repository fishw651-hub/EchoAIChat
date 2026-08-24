import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent.dart';
import '../models/group_chat.dart';
import '../services/database_service.dart';

/// 会话列表条目：一个智能体私聊或一个群聊 + 其最新消息
class ConversationItem {
  const ConversationItem({
    required this.isGroup,
    this.agent,
    this.group,
    required this.lastMessage,
    required this.timestamp,
  });

  final bool isGroup;
  final Agent? agent;
  final GroupChat? group;
  final Map<String, dynamic> lastMessage;
  final int timestamp;
}

/// 纯组装逻辑：agents + groups + 最新消息聚合 → 按时间倒序的会话条目。
/// 无消息时回退到 createdAt；maxItems 非空时排序后截断。
List<ConversationItem> buildConversationItems({
  required List<Agent> agents,
  required List<GroupChat> groups,
  required Map<String, Map<String, dynamic>> lastByAgent,
  required Map<String, Map<String, dynamic>> lastByGroup,
  int? maxItems,
}) {
  final items = <ConversationItem>[];
  for (final agent in agents) {
    final message = lastByAgent[agent.id] ?? const <String, dynamic>{};
    items.add(
      ConversationItem(
        isGroup: false,
        agent: agent,
        lastMessage: message,
        timestamp: (message['timestamp'] as num?)?.toInt() ?? agent.createdAt,
      ),
    );
  }
  for (final group in groups) {
    final message = lastByGroup[group.id] ?? const <String, dynamic>{};
    items.add(
      ConversationItem(
        isGroup: true,
        group: group,
        lastMessage: message,
        timestamp: (message['timestamp'] as num?)?.toInt() ?? group.createdAt,
      ),
    );
  }
  items.sort((first, second) => second.timestamp.compareTo(first.timestamp));
  if (maxItems != null && items.length > maxItems) {
    return items.sublist(0, maxItems);
  }
  return items;
}

class ConversationLastMessageState {
  /// key = agentId，value = 该智能体最新一条私聊消息行
  final Map<String, Map<String, dynamic>> lastByAgent;

  /// key = groupId，value = 该群最新一条群消息行
  final Map<String, Map<String, dynamic>> lastByGroup;

  /// 首次加载是否已完成（未完成时 UI 显示 loading）
  final bool loaded;

  const ConversationLastMessageState({
    this.lastByAgent = const {},
    this.lastByGroup = const {},
    this.loaded = false,
  });
}

/// 会话最新消息聚合（私聊 + 群聊）。
///
/// 首页"最近回响"、智能体列表、群聊列表的"最后一条消息"数据统一从这里取，
/// UI 层不再直接查询 DatabaseService。聚合查询两次 SQL 取全部会话，
/// 替代逐会话 2N 次往返。
///
/// 刷新时机由调用方触发（消息落库、智能体/群聊增删改后调用 `refresh()`）。
class ConversationLastMessageNotifier
    extends StateNotifier<ConversationLastMessageState> {
  ConversationLastMessageNotifier()
    : super(const ConversationLastMessageState()) {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final lastByAgent = await DatabaseService.getLastChatMessagesByAgent();
      final lastByGroup = await DatabaseService.getLastGroupMessagesByGroup();
      if (!mounted) return;
      state = ConversationLastMessageState(
        lastByAgent: lastByAgent,
        lastByGroup: lastByGroup,
        loaded: true,
      );
    } catch (_) {
      // fail-open：查询失败也结束 loading，列表按无最新消息渲染
      if (mounted) {
        state = ConversationLastMessageState(
          lastByAgent: state.lastByAgent,
          lastByGroup: state.lastByGroup,
          loaded: true,
        );
      }
    }
  }
}

final conversationLastMessageProvider =
    StateNotifierProvider<
      ConversationLastMessageNotifier,
      ConversationLastMessageState
    >((ref) => ConversationLastMessageNotifier());

/// 智能体 id → 最新私聊消息时间戳（毫秒），无消息为 0。
/// 智能体列表按此排序。
int lastAgentMessageTimestamp(
  ConversationLastMessageState state,
  String agentId,
) {
  return (state.lastByAgent[agentId]?['timestamp'] as num?)?.toInt() ?? 0;
}

/// 群 id → 最新群消息时间戳（毫秒），无消息为 0。群聊列表按此排序。
int lastGroupMessageTimestamp(
  ConversationLastMessageState state,
  String groupId,
) {
  return (state.lastByGroup[groupId]?['timestamp'] as num?)?.toInt() ?? 0;
}
