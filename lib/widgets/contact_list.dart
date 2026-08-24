import 'dart:convert';

import 'package:flutter/material.dart';import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../models/group_member.dart';
import '../providers/agent_provider.dart';
import '../providers/agent_folder_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/conversation_list_provider.dart';
import '../providers/group_provider.dart';
import '../providers/home_tab_provider.dart';
import '../services/agent_export_service.dart';
import '../services/agent_share_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_avatar.dart';
import '../widgets/echo_conversation_tile.dart';
import '../widgets/message_action_sheet.dart';
import '../screens/agent_create_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';

class ContactListWidget extends ConsumerStatefulWidget {
  const ContactListWidget({super.key});

  @override
  ConsumerState<ContactListWidget> createState() => _ContactListWidgetState();
}

/// 列表条目：编组节头 / 未编组节头 / 智能体
sealed class _ContactEntry {
  const _ContactEntry();
}

class _FolderHeaderEntry extends _ContactEntry {
  final AgentFolder folder;
  const _FolderHeaderEntry(this.folder);
}

class _UncategorizedHeaderEntry extends _ContactEntry {
  const _UncategorizedHeaderEntry();
}

class _AgentEntry extends _ContactEntry {
  final dynamic agent;
  const _AgentEntry(this.agent);
}

class _ContactListWidgetState extends ConsumerState<ContactListWidget> {
  bool _selectionMode = false;
  final Set<String> _selected = {};
  // 气泡操作菜单当前挂着的智能体 id：气泡打开期间再次长按该项 → 进入多选
  String? _menuAgentId;

  @override
  void dispose() {
    // 组件销毁时复位全局多选标记，避免 HomeScreen 一直隐藏子页分段控件
    ref.read(contactSelectionModeProvider.notifier).state = false;
    super.dispose();
  }

  /// 最新消息时间戳由 conversationLastMessageProvider 统一维护，
  /// 编辑/删除/新建/导入后触发刷新即可
  Future<void> _refreshLastMessages() {
    return ref.read(conversationLastMessageProvider.notifier).refresh();
  }

  List<dynamic> _sortedAgents(ConversationLastMessageState lastMessages) {
    final agents = ref
        .read(agentProvider)
        .agents
        .where((a) => !a.isSimCharacter && !a.isGroupOnly)
        .toList();
    agents.sort((a, b) {
      final ta = lastAgentMessageTimestamp(lastMessages, a.id);
      final tb = lastAgentMessageTimestamp(lastMessages, b.id);
      if (ta == 0 && tb == 0) return b.createdAt.compareTo(a.createdAt);
      return tb.compareTo(ta);
    });
    return agents;
  }

  // ═══ 多选模式 ═══

  void _syncSelectionProvider() {
    ref.read(contactSelectionModeProvider.notifier).state = _selectionMode;
  }

  void _enterSelection(String agentId) {
    setState(() {
      _selectionMode = true;
      _selected.add(agentId);
    });
    _syncSelectionProvider();
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
    _syncSelectionProvider();
  }

  void _toggleSelection(String agentId) {
    setState(() {
      if (_selected.contains(agentId)) {
        _selected.remove(agentId);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(agentId);
      }
    });
    _syncSelectionProvider();
  }

  // ═══ 单智能体长按气泡菜单（第一段长按） ═══

  void _showAgentActions(dynamic agent, Offset position) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    _menuAgentId = agent.id as String;
    MessageActionSheet.showAt(context, position, [
      MessageActionItem(
        icon: Icons.chat_bubble_outline_rounded,
        label: l10n.get('switchAgent'),
        color: scheme.primary,
        onTap: () => _openChat(agent),
      ),
      MessageActionItem(
        icon: Icons.edit_outlined,
        label: l10n.get('edit'),
        color: scheme.primary,
        onTap: () => _editAgent(agent),
      ),
      MessageActionItem(
        icon: Icons.delete_outline,
        label: l10n.get('delete'),
        color: scheme.error,
        onTap: () => _deleteAgent(agent),
      ),
      MessageActionItem(
        icon: Icons.select_all_rounded,
        label: l10n.get('multiSelect'),
        color: scheme.primary,
        onTap: () => _enterSelection(agent.id as String),
      ),
    ]).whenComplete(() => _menuAgentId = null);
  }

  /// 长按处理（两段式）：多选模式内 → 切换选中；气泡已打开 → 进多选；
  /// 否则 → 弹出单智能体气泡菜单
  void _handleLongPress(dynamic agent, LongPressStartDetails details) {
    if (_selectionMode) {
      _toggleSelection(agent.id as String);
    } else if (_menuAgentId == agent.id) {
      _enterSelection(agent.id as String);
    } else {
      _showAgentActions(agent, details.globalPosition);
    }
  }

  Future<void> _editAgent(dynamic agent) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: agent)),
    );
    ref.read(agentProvider.notifier).refresh();
    _refreshLastMessages();
  }

  Future<void> _deleteAgent(dynamic agent) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirmDeleteAgentTitle')),
        content: Text(
          l10n.getP('confirmDeleteNamed', {'name': agent.name as String}),
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
    if (ok != true) return;
    // 编组映射刷新由 agentProvider.deleteAgent 内部编排
    await ref.read(agentProvider.notifier).deleteAgent(agent.id as String);
    _refreshLastMessages();
  }

  Future<void> _openChat(dynamic agent) async {
    await ref.read(agentProvider.notifier).setActiveAgent(agent.id);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
    }
  }

  // ═══ 底栏操作：加入编组 / 编辑 / 删除 ═══

  Future<void> _showAddToFolderDialog() async {
    final l10n = AppLocalizations.of(context);
    final folders = ref.read(agentFolderProvider).folders;
    String? chosen = folders.isNotEmpty ? folders.first.id : '__new__';
    final nameCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(l10n.get('selectFolder')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...folders.map(
                (f) => ListTile(
                  dense: true,
                  title: Text(f.name),
                  trailing: chosen == f.id
                      ? Icon(
                          Icons.check,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => setDlgState(() => chosen = f.id),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l10n.get('newFolder')),
                trailing: chosen == '__new__'
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => setDlgState(() => chosen = '__new__'),
              ),
              if (chosen == '__new__')
                TextField(
                  controller: nameCtrl,
                  autofocus: folders.isEmpty,
                  decoration: InputDecoration(
                    hintText: l10n.get('folderNameHint'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (chosen == '__new__' && nameCtrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(l10n.get('confirm')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(agentFolderProvider.notifier);
    String folderId;
    if (chosen == '__new__') {
      folderId = await notifier.createFolder(nameCtrl.text.trim());
    } else {
      folderId = chosen!;
    }
    await notifier.addAgentsToFolder(folderId, _selected.toList());
    _exitSelection();
  }

  Future<void> _editSelected() async {
    if (_selected.length != 1) return;
    final agent = ref
        .read(agentProvider)
        .agents
        .where((a) => a.id == _selected.first)
        .firstOrNull;
    if (agent == null) return;
    _exitSelection();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: agent)),
    );
    ref.read(agentProvider.notifier).refresh();
    _refreshLastMessages();
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('deleteAgentTitle')),
        content: Text(
          l10n.getP('confirmDeleteSelected', {
            'count': '${_selected.length}',
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
    if (ok != true) return;
    for (final id in _selected.toList()) {
      await ref.read(agentProvider.notifier).deleteAgent(id);
    }
    _exitSelection();
    _refreshLastMessages();
  }

  // ═══ 编组 ⋯ 菜单操作 ═══

  Future<void> _createGroupFromFolder(AgentFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final memberships = ref.read(agentFolderProvider).memberships;
    final memberAgents = ref
        .read(agentProvider)
        .agents
        .where(
          (a) =>
              memberships[a.id] == folder.id &&
              !a.isSimCharacter &&
              !a.isGroupOnly,
        )
        .toList();
    if (memberAgents.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('folderEmpty'))));
      return;
    }

    final nameCtrl = TextEditingController(text: folder.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('createGroup')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.get('groupNameHint'),
              ),
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              l10n.getP('linkedGroupHint', {
                'count': '${memberAgents.length}',
              }),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(l10n.get('create')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final members = memberAgents
        .map((a) => GroupMember(groupId: '', agentId: a.id, role: 'member'))
        .toList();
    await ref
        .read(groupProvider.notifier)
        .createGroup(
          name: nameCtrl.text.trim(),
          members: members,
          linkedMemory: true,
        );
    if (!mounted) return;
    final gid = ref.read(groupProvider).activeGroup?.id;
    if (gid != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: gid)),
      );
    }
  }

  Future<void> _renameFolder(AgentFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: folder.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('renameFolder')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.get('folderNameHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(agentFolderProvider.notifier)
        .renameFolder(folder.id, nameCtrl.text.trim());
  }

  Future<void> _dissolveFolder(AgentFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('dissolveFolder')),
        content: Text(
          l10n.getP('confirmDissolveFolder', {'name': folder.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(agentFolderProvider.notifier).dissolveFolder(folder.id);
  }

  void _showShareRedeemDialog() {
    final jwt = ref.read(authProvider).jwtToken;
    showDialog(
      context: context,
      builder: (_) => _AgentRedeemDialog(
        jwt: jwt,
        importAgent: (agent) =>
            ref.read(agentProvider.notifier).importAgent(agent),
        onImported: (name) async {
          await _refreshLastMessages();
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.getP('agentImported', {'name': name}))),
          );
        },
      ),
    );
  }

  // ═══ 构建 ═══
  List<_ContactEntry> _buildEntries(
    List<dynamic> sortedAgents,
    AgentFolderState folderState,
  ) {
    final entries = <_ContactEntry>[];
    final memberships = folderState.memberships;
    for (final folder in folderState.folders) {
      entries.add(_FolderHeaderEntry(folder));
      for (final a in sortedAgents) {
        if (memberships[a.id] == folder.id) entries.add(_AgentEntry(a));
      }
    }
    final unfoldered = sortedAgents
        .where((a) => memberships[a.id] == null)
        .toList();
    if (folderState.folders.isNotEmpty && unfoldered.isNotEmpty) {
      entries.add(const _UncategorizedHeaderEntry());
    }
    entries.addAll(unfoldered.map((a) => _AgentEntry(a)));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final folderState = ref.watch(agentFolderProvider);
    final lastMessages = ref.watch(conversationLastMessageProvider);
    final agents = state.agents
        .where((a) => !a.isSimCharacter && !a.isGroupOnly)
        .toList();
    final sortedAgents = lastMessages.loaded
        ? _sortedAgents(lastMessages)
        : agents;
    final entries = _buildEntries(sortedAgents, folderState);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              ),
              title: Text(
                l10n.getP('selectedAgentCount', {'count': '${_selected.length}'}),
              ),
            )
          : AppBar(
              title: Text(l10n.get('agentSection')),
              actions: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.ios_share),
                  tooltip: l10n.get('agentShare'),
                  onPressed: _showShareRedeemDialog,
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AgentCreateScreen(),
                      ),
                    );
                    ref.read(agentProvider.notifier).refresh();
                    _refreshLastMessages();
                  },
                ),
              ],
            ),
      body: agents.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 64,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    l10n.get('noAgents'),
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
                          builder: (_) => const AgentCreateScreen(),
                        ),
                      );
                      ref.read(agentProvider.notifier).refresh();
                      _refreshLastMessages();
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.get('createAgent')),
                  ),
                ],
              ),
            )
          : ListView.separated(
              // 底部预留：悬浮导航栏(约108) + 子页分段控件(40) + 间距(12)，避免遮挡末项
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppTheme.space2),
              itemBuilder: (_, i) {
                final entry = entries[i];
                return switch (entry) {
                  _FolderHeaderEntry(folder: final f) => _FolderHeader(
                    folder: f,
                    onCreateGroup: () => _createGroupFromFolder(f),
                    onRename: () => _renameFolder(f),
                    onDissolve: () => _dissolveFolder(f),
                  ),
                  _UncategorizedHeaderEntry() => const _UncategorizedHeader(),
                  _AgentEntry(agent: final a) => _AgentTile(
                    agent: a,
                    selectionMode: _selectionMode,
                    selected: _selected.contains(a.id),
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelection(a.id);
                      } else {
                        _openChat(a);
                      }
                    },
                    onLongPressStart: (details) =>
                        _handleLongPress(a, details),
                  ),
                };
              },
            ),
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space2,
                  vertical: AppTheme.space1,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : _showAddToFolderDialog,
                      icon: const Icon(Icons.folder_outlined),
                      label: Text(l10n.get('addToFolder')),
                    ),
                    TextButton.icon(
                      onPressed: _selected.length == 1 ? _editSelected : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(l10n.get('edit')),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty ? null : _deleteSelected,
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      label: Text(
                        l10n.get('delete'),
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _FolderHeader extends StatelessWidget {
  final AgentFolder folder;
  final VoidCallback onCreateGroup;
  final VoidCallback onRename;
  final VoidCallback onDissolve;

  const _FolderHeader({
    required this.folder,
    required this.onCreateGroup,
    required this.onRename,
    required this.onDissolve,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 2),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              '${folder.name} · '
              '${l10n.getP('folderMemberCount', {'count': '${folder.memberCount}'})}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
            onSelected: (v) {
              switch (v) {
                case 'group':
                  onCreateGroup();
                case 'rename':
                  onRename();
                case 'dissolve':
                  onDissolve();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'group',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text(l10n.get('createGroup')),
                ),
              ),
              PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: Text(l10n.get('renameFolder')),
                ),
              ),
              PopupMenuItem(
                value: 'dissolve',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_delete_outlined,
                      color: scheme.error),
                  title: Text(
                    l10n.get('dissolveFolder'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UncategorizedHeader extends StatelessWidget {
  const _UncategorizedHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 2),
      child: Text(
        AppLocalizations.of(context).get('uncategorized'),
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  final dynamic agent;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onLongPressStart;

  const _AgentTile({
    required this.agent,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPressStart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: onLongPressStart,
      child: Row(
        children: [
          if (selectionMode) ...[
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: AppTheme.space2),
          ],
          Expanded(
            child: EchoConversationTile(
              onTap: onTap,
              avatar: AgentAvatar(
                name: agent.name,
                avatarColor: agent.avatarColor,
                avatarPath: agent.avatarPath,
                size: 48,
                radius: 10,
                fontSize: 19,
              ),
              title: agent.name,
              preview: agent.description.isNotEmpty
                  ? agent.description
                  : AppLocalizations.of(context).get('tapToStartChat'),
              timestamp: DateTime.fromMillisecondsSinceEpoch(agent.createdAt),
            ),
          ),
        ],
      ),
    );
  }
}

/// 智能体分享兑换对话框：输入 6 位码 → 预览 → 确认导入
class _AgentRedeemDialog extends StatefulWidget {
  final String? jwt;
  final Future<void> Function(Agent agent) importAgent;
  final Future<void> Function(String name) onImported;

  const _AgentRedeemDialog({
    this.jwt,
    required this.importAgent,
    required this.onImported,
  });

  @override
  State<_AgentRedeemDialog> createState() => _AgentRedeemDialogState();
}

class _AgentRedeemDialogState extends State<_AgentRedeemDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _importing = false;
  String? _error;
  SharedAgentSnapshot? _snapshot;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final l10n = AppLocalizations.of(context);
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = l10n.get('invalidShareCode'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot =
          await AgentShareService(token: widget.jwt).redeemShare(code);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmImport() async {
    final snapshot = _snapshot;
    if (snapshot == null || _importing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _importing = true);
    try {
      // 复用导出服务的导入路径：头像 base64 落盘到应用文档目录
      final agent =
          await AgentExportService.importAgent(snapshot.toExportData());
      await widget.importAgent(agent);
      await widget.onImported(agent.name);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = '${l10n.get('agentImportFailed')}: $e';
      });
    }
  }

  Widget _buildPreviewAvatar(ColorScheme scheme) {
    final avatar = _snapshot?.avatar;
    if (avatar != null && avatar.startsWith('data:image/')) {
      final parts = avatar.split(';base64,');
      if (parts.length == 2) {
        try {
          return CircleAvatar(
            radius: 28,
            backgroundImage: MemoryImage(base64Decode(parts[1])),
          );
        } catch (_) {
          // base64 损坏时降级为颜色头像
        }
      }
    }
    final name = _snapshot?.name.trim() ?? '';
    return CircleAvatar(
      radius: 28,
      backgroundColor: Color(_snapshot?.avatarColor ?? 0xFFE8F5E9),
      child: Text(
        name.isNotEmpty ? name.characters.first : '?',
        style: TextStyle(fontSize: 22, color: scheme.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final snapshot = _snapshot;
    return AlertDialog(
      title: Text(l10n.get('agentShare')),
      content: SizedBox(
        width: 320,
        child: snapshot == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: l10n.get('enterShareCode'),
                      hintText: l10n.get('shareCodeHint'),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _redeem(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPreviewAvatar(scheme),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (snapshot.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.description,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.get('cancel')),
        ),
        if (snapshot == null)
          FilledButton(
            onPressed: _loading ? null : _redeem,
            child: Text(l10n.get('redeem')),
          )
        else
          FilledButton(
            onPressed: _importing ? null : _confirmImport,
            child: Text(
              _importing
                  ? l10n.get('importing')
                  : l10n.get('confirmImport'),
            ),
          ),
      ],
    );
  }
}
