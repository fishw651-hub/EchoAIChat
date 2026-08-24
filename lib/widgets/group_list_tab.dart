import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/conversation_list_provider.dart';
import '../providers/group_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/group_avatar.dart';
import '../widgets/echo_conversation_tile.dart';
import '../widgets/message_action_sheet.dart';
import '../screens/group_chat_screen.dart';
import '../screens/group_create_screen.dart';
import '../screens/group_manage_screen.dart';

class GroupListTabWidget extends ConsumerStatefulWidget {
  const GroupListTabWidget({super.key});

  @override
  ConsumerState<GroupListTabWidget> createState() => _GroupListTabWidgetState();
}

class _GroupListTabWidgetState extends ConsumerState<GroupListTabWidget> {
  /// 最新消息时间戳由 conversationLastMessageProvider 统一维护（fail-open，
  /// 查询失败按无最新消息渲染），创建/删除群后触发刷新即可
  Future<void> _refreshLastMessages() {
    return ref.read(conversationLastMessageProvider.notifier).refresh();
  }

  List<dynamic> _sortedGroups(ConversationLastMessageState lastMessages) {
    // 必须用 toList() 创建可变副本，否则当 provider 返回 const [] 时
    // 调用 sort() 会抛 "Cannot modify a constant list"
    final groups = ref.read(groupProvider).groups.toList();
    groups.sort((a, b) {
      final ta = lastGroupMessageTimestamp(lastMessages, a.id);
      final tb = lastGroupMessageTimestamp(lastMessages, b.id);
      if (ta == 0 && tb == 0) return b.createdAt.compareTo(a.createdAt);
      return tb.compareTo(ta);
    });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupProvider);
    final lastMessages = ref.watch(conversationLastMessageProvider);
    final groups = state.groups;
    final sortedGroups = lastMessages.loaded
        ? _sortedGroups(lastMessages)
        : groups;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('groupChats')),
        actions: [
          IconButton.filledTonal(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
              );
              ref.read(groupProvider.notifier).loadGroups();
              _refreshLastMessages();
            },
          ),
        ],
      ),
      body: groups.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 64,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    l10n.get('noGroups'),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space6),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GroupCreateScreen(),
                        ),
                      );
                      ref.read(groupProvider.notifier).loadGroups();
                      _refreshLastMessages();
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.get('createGroup')),
                  ),
                ],
              ),
            )
          : ListView.separated(
              // 底部预留：悬浮导航栏(约108) + 子页分段控件(40) + 间距(12)，避免遮挡末项
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
              itemCount: sortedGroups.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppTheme.space2),
              itemBuilder: (_, i) {
                final group = sortedGroups[i];
                return _GroupTile(
                  group: group,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupChatScreen(groupId: group.id),
                    ),
                  ),
                  onLongPressStart: (details) {
                    MessageActionSheet.showAt(context, details.globalPosition, [
                      MessageActionItem(
                        icon: Icons.login,
                        label: l10n.get('enter'),
                        color: scheme.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatScreen(groupId: group.id),
                          ),
                        ),
                      ),
                      MessageActionItem(
                        icon: Icons.edit_outlined,
                        label: l10n.get('edit'),
                        color: scheme.onSurface,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                GroupManageScreen(groupId: group.id),
                          ),
                        ),
                      ),
                      MessageActionItem(
                        icon: Icons.delete_outline,
                        label: l10n.get('delete'),
                        color: scheme.error,
                        onTap: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(l10n.get('deleteGroupTitle')),
                              content: Text(
                                l10n.getP('confirmDeleteNamed', {
                                  'name': group.name,
                                }),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l10n.get('cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l10n.get('delete')),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ref
                                .read(groupProvider.notifier)
                                .deleteGroup(group.id);
                            _refreshLastMessages();
                          }
                        },
                      ),
                    ]);
                  },
                );
              },
            ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final dynamic group;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onLongPressStart;
  const _GroupTile({
    required this.group,
    required this.onTap,
    required this.onLongPressStart,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: onLongPressStart,
      child: EchoConversationTile(
        onTap: onTap,
        avatar: GroupAvatar(
          avatarColor: group.avatarColor,
          avatarIcon: group.avatarIcon,
          avatarPath: group.avatarPath,
          size: 48,
          radius: 10,
          iconSize: 22,
        ),
        title: group.name,
        preview: group.description?.isNotEmpty == true
            ? group.description!
            : AppLocalizations.of(context).get('tapToEnterGroup'),
        timestamp: DateTime.fromMillisecondsSinceEpoch(group.createdAt),
      ),
    );
  }
}
