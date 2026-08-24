import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../providers/agent_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/conversation_list_provider.dart';
import '../providers/group_provider.dart';
import '../screens/agent_create_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/group_manage_screen.dart';
import '../theme/app_theme.dart';
import 'agent_avatar.dart';
import 'echo_conversation_tile.dart';
import 'group_avatar.dart';
import 'message_action_sheet.dart';

class ConversationListWidget extends ConsumerStatefulWidget {
  const ConversationListWidget({super.key});

  @override
  ConsumerState<ConversationListWidget> createState() =>
      _ConversationListState();
}

class _ConversationListState extends ConsumerState<ConversationListWidget> {
  /// 首页"最近回响"最多展示的会话条数（按时间倒序取前几条）
  static const int _maxRecentItems = 5;

  void _refreshLastMessages() {
    ref.read(conversationLastMessageProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref
        .watch(agentProvider)
        .agents
        .where((agent) => !agent.isSimCharacter && !agent.isGroupOnly)
        .toList();
    final groups = ref.watch(groupProvider).groups;
    final lastMessages = ref.watch(conversationLastMessageProvider);
    ref.watch(chatProvider.select((state) => state.messages.length));
    ref.listen(chatProvider.select((state) => state.messages.length), (_, _) {
      _refreshLastMessages();
    });
    // 后台续输出落库（切走后原智能体的回复跑完写库）不改 messages，
    // 靠 saveRevision 计数通知列表刷新最新消息预览
    ref.listen(chatProvider.select((state) => state.saveRevision), (_, _) {
      _refreshLastMessages();
    });
    // 智能体/群聊增删改（如删除智能体）时重建列表，否则列表会残留已删项
    ref.listen(agentProvider.select((state) => state.agents), (_, _) {
      _refreshLastMessages();
    });
    ref.listen(groupProvider.select((state) => state.groups), (_, _) {
      _refreshLastMessages();
    });

    if (!lastMessages.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = buildConversationItems(
      agents: agents,
      groups: groups,
      lastByAgent: lastMessages.lastByAgent,
      lastByGroup: lastMessages.lastByGroup,
      maxItems: _maxRecentItems,
    );
    if (items.isEmpty) return _buildEmptyState(context);

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space4),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: AppTheme.brXl,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.48),
            width: 0.5,
          ),
          boxShadow: AppTheme.shadowSm,
        ),
        child: ClipRRect(
          borderRadius: AppTheme.brXl,
          child: ListView.builder(
            // 底部预留：悬浮导航栏(约108) + 间距(12)，避免滚动到底时末项被遮挡
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(
              context,
              items[index],
              showDivider: index < items.length - 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AgentCreateScreen()),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.18),
                      scheme.tertiary.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 40,
                        color: scheme.primary,
                      ),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: scheme.tertiary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.space5),
              Text(
                l10n.get('noConversations'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.space2),
              Text(
                l10n.get('createAgentFirstEcho'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ConversationItem item, {
    bool showDivider = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final hasMessage = item.lastMessage.isNotEmpty;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    if (!item.isGroup) {
      final agent = item.agent!;
      final content = (item.lastMessage['content'] as String?) ?? '';
      final preview = content.isNotEmpty
          ? content
          : agent.openingLine?.isNotEmpty == true
          ? agent.openingLine!
          : l10n.get('tapToStartChat');
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) =>
            _showAgentMenu(context, agent, details.globalPosition),
        child: EchoConversationTile(
          avatar: AgentAvatar(
            name: agent.name,
            avatarColor: agent.avatarColor,
            avatarPath: agent.avatarPath,
            size: 48,
            radius: AppTheme.radiusMd,
            fontSize: 20,
          ),
          title: agent.name,
          preview: preview,
          timestamp: hasMessage ? timestamp : null,
          showDivider: showDivider,
          onTap: () => _openAgent(context, agent),
        ),
      );
    }

    final group = item.group!;
    final sender = (item.lastMessage['sender_name'] as String?) ?? '';
    final content = (item.lastMessage['content'] as String?) ?? '';
    final preview = content.isEmpty
        ? l10n.get('tapToEnterGroup')
        : sender.isEmpty
        ? content
        : l10n.getP('senderMessagePreview', {
            'sender': sender,
            'content': content,
          });
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) =>
          _showGroupMenu(context, group, details.globalPosition),
      child: EchoConversationTile(
        avatar: GroupAvatar(
          avatarColor: group.avatarColor,
          avatarIcon: group.avatarIcon,
          avatarPath: group.avatarPath,
          size: 48,
          radius: AppTheme.radiusMd,
          iconSize: 22,
        ),
        title: group.name,
        preview: preview,
        timestamp: hasMessage ? timestamp : null,
        showDivider: showDivider,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
        ),
      ),
    );
  }

  Future<void> _openAgent(BuildContext context, Agent agent) async {
    await ref.read(agentProvider.notifier).setActiveAgent(agent.id);
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
    }
  }

  void _showAgentMenu(BuildContext context, Agent agent, Offset position) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    MessageActionSheet.showAt(context, position, [
      MessageActionItem(
        icon: Icons.chat_bubble_outline_rounded,
        label: l10n.get('enterChat'),
        color: scheme.primary,
        onTap: () => _openAgent(context, agent),
      ),
      MessageActionItem(
        icon: Icons.edit_outlined,
        label: l10n.get('editAgent'),
        color: scheme.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: agent)),
        ),
      ),
      MessageActionItem(
        icon: Icons.delete_outline,
        label: l10n.get('delete'),
        color: scheme.error,
        onTap: () async {
          if (await _confirmDelete(context, agent.name) == true) {
            await ref.read(agentProvider.notifier).deleteAgent(agent.id);
          }
        },
      ),
    ]);
  }

  void _showGroupMenu(BuildContext context, GroupChat group, Offset position) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    MessageActionSheet.showAt(context, position, [
      MessageActionItem(
        icon: Icons.login_rounded,
        label: l10n.get('enterGroup'),
        color: scheme.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
        ),
      ),
      MessageActionItem(
        icon: Icons.edit_outlined,
        label: l10n.get('manageGroup'),
        color: scheme.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupManageScreen(groupId: group.id),
          ),
        ),
      ),
      MessageActionItem(
        icon: Icons.delete_outline,
        label: l10n.get('delete'),
        color: scheme.error,
        onTap: () async {
          if (await _confirmDelete(context, group.name) == true) {
            await ref.read(groupProvider.notifier).deleteGroup(group.id);
          }
        },
      ),
    ]);
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.get('confirmDelete')),
        content: Text(l10n.getP('confirmDeleteGeneric', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }
}
