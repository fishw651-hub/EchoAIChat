import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart' as pp;

import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/group_provider.dart';
import '../screens/account_screen.dart';
import '../screens/agent_create_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/group_create_screen.dart';
import '../screens/group_manage_screen.dart';
import '../screens/my_network_agents_screen.dart';
import '../screens/settings_screen.dart';
import '../services/agent_export_service.dart';
import 'agent_avatar.dart';
import 'group_avatar.dart';
import 'user_avatar.dart';

/// 桌面端聊天页侧边栏：当前智能体信息 + 智能体/群聊列表 + 设置/账户入口。
/// 行为与原 chat_screen 内联实现完全一致，仅做结构拆分。
class ChatDesktopSidebar extends ConsumerWidget {
  /// 点击列表项切换当前智能体
  final void Function(Agent agent, Agent? current) onSwitchAgent;

  const ChatDesktopSidebar({super.key, required this.onSwitchAgent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final agentState = ref.watch(agentProvider);
    final current = agentState.currentAgent;
    final agents = agentState.agents;
    final groupState = ref.watch(groupProvider);
    final groups = groupState.groups;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: current == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AgentCreateScreen(agent: current),
                          ),
                        ),
                  child: _agentAvatar(context, current),
                ),
                const SizedBox(height: 8),
                Text(
                  current?.name ?? l10n.get('noAgentSelected'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (current?.description.isNotEmpty == true)
                  Text(
                    current!.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AgentCreateScreen(),
                          ),
                        ),
                        child: Text(
                          l10n.get('createNewAgent'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyNetworkAgentsScreen(),
                          ),
                        ),
                        child: Text(
                          l10n.get('createNetworkAgent'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final a in agents.where(
                  (a) => !a.isSimCharacter && !a.isGroupOnly,
                ))
                  _agentListTile(context, ref, a, current, l10n),
                const Divider(indent: 16, endIndent: 16),
                if (groups.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GroupCreateScreen(),
                          ),
                        );
                        ref.read(groupProvider.notifier).loadGroups();
                      },
                      child: Text(
                        l10n.get('createGroup'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  for (final g in groups) _groupListTile(context, ref, g, l10n),
                ] else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GroupCreateScreen(),
                          ),
                        );
                        ref.read(groupProvider.notifier).loadGroups();
                      },
                      child: Text(
                        l10n.get('createGroup'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings, size: 20),
            title: Text(
              l10n.get('settings'),
              style: const TextStyle(fontSize: 13),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          _accountTile(context, ref, l10n),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _agentAvatar(
    BuildContext context,
    Agent? agent, {
    double radius = 28,
    double fontSize = 24,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return AgentAvatar(
      name: agent?.name,
      avatarColor:
          agent?.avatarColor ?? scheme.surfaceContainerHighest.toARGB32(),
      avatarPath: agent?.avatarPath,
      size: radius * 2,
      radius: radius,
      fontSize: fontSize,
    );
  }

  Widget _agentListTile(
    BuildContext context,
    WidgetRef ref,
    Agent a,
    Agent? current,
    AppLocalizations l10n,
  ) {
    final isCurrent = a.id == current?.id;
    return Tooltip(
      key: ValueKey('agent_${a.id}'),
      message: a.description.isNotEmpty ? a.description : a.name,
      child: ListTile(
        dense: true,
        leading: _agentAvatar(context, a, radius: 16, fontSize: 12),
        title: Text(
          a.name,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        selected: isCurrent,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => onSwitchAgent(a, current),
        onLongPress: () => _showAgentMenu(context, ref, a, isCurrent, l10n),
      ),
    );
  }

  void _showAgentMenu(
    BuildContext context,
    WidgetRef ref,
    Agent a,
    bool isCurrent,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.get('edit')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AgentCreateScreen(agent: a),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: Text(l10n.get('export')),
              onTap: () {
                Navigator.pop(ctx);
                _exportAgent(context, a);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                l10n.get('delete'),
                style: const TextStyle(color: Colors.red),
              ),
              enabled: !isCurrent,
              onTap: isCurrent
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _confirmDeleteAgent(context, ref, a);
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _exportAgent(BuildContext context, Agent a) async {
    final l10n = AppLocalizations.of(context);
    try {
      final data = await AgentExportService.exportAgent(a);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await pp.getApplicationDocumentsDirectory();
      final fileName = '${a.name}_export.agent.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getP('agentExported', {'path': '${dir.path}/$fileName'}),
            ),
          ),
        );
      }
    } catch (e) {
      final errMsg = '${l10n.get('agentExportFailed')}: $e';
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errMsg)));
      }
    }
  }

  void _confirmDeleteAgent(BuildContext context, WidgetRef ref, Agent a) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
          size: 32,
        ),
        title: Text(l10n.get('confirmDeleteAgentTitle')),
        content: Text(
          l10n.getP('confirmDeleteAgentContent', {
            'name': a.name,
            'activeNote': '',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(agentProvider.notifier).deleteAgent(a.id);
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  Widget _groupListTile(
    BuildContext context,
    WidgetRef ref,
    GroupChat group,
    AppLocalizations l10n,
  ) {
    return Tooltip(
      key: ValueKey('group_${group.id}'),
      message: group.description.isNotEmpty ? group.description : group.name,
      child: ListTile(
        dense: true,
        leading: GroupAvatar(
          avatarColor: group.avatarColor,
          avatarIcon: group.avatarIcon,
          avatarPath: group.avatarPath,
          size: 32,
          radius: 8,
          iconSize: 18,
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
        ),
        onLongPress: () => _showGroupMenu(context, ref, group, l10n),
      ),
    );
  }

  void _showGroupMenu(
    BuildContext context,
    WidgetRef ref,
    GroupChat group,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: scheme.primary),
              title: Text(l10n.get('enterGroupChat')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupChatScreen(groupId: group.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.get('editGroup')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManageScreen(groupId: group.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: scheme.error),
              title: Text(
                l10n.get('delete'),
                style: TextStyle(color: scheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteGroup(context, ref, group);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context, WidgetRef ref, GroupChat group) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmDelete')),
        content: Text(
          l10n.getP('deleteGroupConfirmDetail', {'name': group.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () async {
              await ref.read(groupProvider.notifier).deleteGroup(group.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  /// 侧边栏账户入口 — 左侧头像，右上昵称，右下余额
  Widget _accountTile(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final scheme = Theme.of(context).colorScheme;

    if (!auth.isLoggedIn || user == null) {
      return ListTile(
        dense: true,
        leading: Icon(
          Icons.login,
          size: 20,
          color: scheme.primary,
        ),
        title: Text(
          l10n.get('login'),
          style: TextStyle(fontSize: 13, color: scheme.primary),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountScreen()),
          );
        },
      );
    }

    return ListTile(
      dense: true,
      leading: UserAvatar(
        avatar: user.avatar,
        radius: 14,
        backgroundColor: scheme.primaryContainer,
        fallback: Text(
          user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: RichText(
        text: TextSpan(
          text: '¥${user.totalAvailable.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 11,
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: l10n.getP('quotaFreeSub', {
                'daily': user.dailyQuotaLeft.toStringAsFixed(1),
                'sub': user.subscriptionQuotaLeft.toStringAsFixed(1),
              }),
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountScreen()),
        );
      },
    );
  }
}
