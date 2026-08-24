import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../providers/group_provider.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../models/group_message.dart';
import '../models/group_chat.dart';
import '../services/tool_executor.dart';
import '../services/quota_service.dart';
import '../services/sync_websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import '../utils/range_select.dart';
import '../widgets/agent_avatar.dart';
import '../widgets/user_avatar.dart';
import '../widgets/echo_visual_surface.dart';
import '../widgets/network_content_intro_card.dart';
import '../services/network_content_intro_store.dart';
import '../services/network_copy_policy.dart';
import '../widgets/time_divider.dart';
import 'account_screen.dart';
import 'subscription_center_screen.dart';
import 'group_manage_screen.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _multiSelectMode = false;
  final Set<int> _selectedIndices = {};
  // 多选模式下当前可见的消息 index（visibility_detector 上报，>50% 可见）
  final Set<int> _visibleIndices = {};

  // ── 多端同步：聊天锁 ──
  bool _syncBlockedByOther = false;
  bool _wasLoading = false;
  LockCallback? _prevLockCallback;
  bool _networkIntroDismissed = false;
  String? _networkIntroIdentity;

  @override
  void initState() {
    super.initState();
    // 注册聊天锁回调（接管全局回调，dispose 时还原）
    _prevLockCallback = SyncWebSocketService.instance.onLockChange;
    SyncWebSocketService.instance.onLockChange = _onSyncLockChange;
    // 滚动到顶部附近时加载更早的群历史（分页加载）
    _scrollCtrl.addListener(_onScrollLoadEarlier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(groupProvider.notifier).loadGroup(widget.groupId);
      } catch (e) {
        debugPrint('[GroupChat] loadGroup failed: $e');
      }
      _inputFocus.unfocus();
      _scrollAfter(500);
    });
  }

  // 滚动接近顶部时触发向上翻页；防重入由 provider 侧守卫
  void _onScrollLoadEarlier() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >= 120) return;
    final groupState = ref.read(groupProvider);
    if (!groupState.hasMoreMessages || groupState.isLoading) return;
    ref.read(groupProvider.notifier).loadEarlierGroupMessages();
  }

  void _onSyncLockChange(
    bool lockedByOther,
    String? deviceName,
    String? status,
  ) {
    if (!mounted) return;
    _syncBlockedByOther = lockedByOther;
    if (lockedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('syncChatConflict')),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }

  @override
  void dispose() {
    // 还原全局回调
    SyncWebSocketService.instance.onLockChange = _prevLockCallback;
    // 退出时释放当前会话锁
    SyncWebSocketService.instance.releaseLock(groupId: widget.groupId);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // 同步冲突拦截
    if (_syncBlockedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('syncChatConflict')),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }
    final inputText = _inputCtrl.text;
    final text = inputText.trim();
    if (text.isEmpty) return;
    final acquired = await SyncWebSocketService.instance.acquireLock(
      groupId: widget.groupId,
      status: 'waiting',
    );
    if (!mounted) {
      if (acquired) {
        await SyncWebSocketService.instance.releaseLock(
          groupId: widget.groupId,
        );
      }
      return;
    }
    if (!acquired) {
      if (!_syncBlockedByOther) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).get('syncChatConflict')),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
      return;
    }
    if (_inputCtrl.text == inputText) {
      _inputCtrl.clear();
    }
    _inputFocus.unfocus();
    await ref
        .read(groupProvider.notifier)
        .sendUserMessage(widget.groupId, text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollAfter(200));
  }

  void _scrollAfter(int ms) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _interrupt() {
    ref.read(groupProvider.notifier).interruptAgents();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).get('agentInterrupted')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showMessageActions(GroupMessage msg, int index, Offset position) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget btn(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color ?? scheme.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: (color ?? scheme.onSurface).withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    showMenu(
      context: context,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 8,
                children: [
                  btn(Icons.copy, l10n.get('copyText'), () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.get('copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }),
                  if (msg.isAgent) ...[
                    btn(Icons.refresh, l10n.get('regenerate'), () {
                      ref
                          .read(groupProvider.notifier)
                          .regenerateLastReplies(widget.groupId);
                    }),
                    if (msg.toolCallData != null || msg.toolLogs != null)
                      btn(Icons.code, l10n.get('viewToolCalls'), () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showToolLogsForGroupMessage(context, msg);
                        });
                      }),
                  ],
                  if (_multiSelectMode)
                    btn(
                      Icons.playlist_add_check_rounded,
                      l10n.get('selectToHere'),
                      () => _selectRangeTo(index),
                      color: scheme.primary,
                    )
                  else
                    btn(
                      Icons.checklist,
                      l10n.get('multiSelect'),
                      () => _enterMultiSelect(index),
                      color: scheme.primary,
                    ),
                  btn(
                    Icons.delete,
                    l10n.get('deleteMessage'),
                    () => ref
                        .read(groupProvider.notifier)
                        .deleteMessageFrom(index),
                    color: scheme.error,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showToolLogsForGroupMessage(BuildContext context, GroupMessage msg) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final logs = msg.toolLogs ?? [];
    if (logs.isEmpty) {
      try {
        final data = jsonDecode(msg.toolCallData ?? '[]') as List;
        for (final e in data) {
          logs.add(
            ToolExecutionLog(
              toolName: e['toolName'] as String,
              arguments: Map<String, dynamic>.from(e['arguments'] as Map),
              result: e['result'] as String,
            ),
          );
        }
      } catch (_) {}
    }
    if (logs.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.get('toolCalls'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log = logs[i];
              final formattedArgs = const JsonEncoder.withIndent(
                '  ',
              ).convert(log.arguments);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.toolName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedArgs,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      log.result,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('close')),
          ),
        ],
      ),
    );
  }

  void _showGroupMemoryPanel({
    String? initialAgentId,
    String? initialAgentName,
  }) async {
    final l10n = AppLocalizations.of(context);
    final groupService = ref.read(groupServiceProvider);
    final groupId = widget.groupId;
    final members = ref.read(groupProvider).members;
    final agentList = ref.read(agentProvider).agents;

    final agents = members.map((m) {
      final a = agentList.where((x) => x.id == m.agentId).firstOrNull;
      final fallback = m.agentId.length > 6
          ? m.agentId.substring(0, 6)
          : m.agentId;
      return (id: m.agentId, name: a?.name ?? fallback);
    }).toList();

    if (agents.isEmpty) return;

    String selId = initialAgentId ?? agents.first.id;
    String selName = initialAgentName ?? agents.first.name;

    List<dynamic> personalMems = [];
    List<dynamic> sharedMems = [];
    bool memsLoading = true;

    Future<void> loadMems() async {
      memsLoading = true;
      final p = await groupService.getAgentGroupLongTermMemories(
        selId,
        groupId,
      );
      final s = await groupService.getSharedMemories(groupId);
      personalMems = p;
      sharedMems = s;
      memsLoading = false;
    }

    await loadMems();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      children: [
                        Text(
                          '$selName ${l10n.get("memoryManagementTitle")}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: agents
                                .map(
                                  (a) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(
                                        a.name,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      selected: selId == a.id,
                                      onSelected: (_) async {
                                        selId = a.id;
                                        selName = a.name;
                                        setSheetState(() {
                                          memsLoading = true;
                                        });
                                        final p = await groupService
                                            .getAgentGroupLongTermMemories(
                                              selId,
                                              groupId,
                                            );
                                        final s = await groupService
                                            .getSharedMemories(groupId);
                                        setSheetState(() {
                                          personalMems = p;
                                          sharedMems = s;
                                          memsLoading = false;
                                        });
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  TabBar(
                    tabs: [
                      Tab(
                        text:
                            '${l10n.get("longTermTab")} (${memsLoading ? '...' : personalMems.length})',
                      ),
                      Tab(
                        text:
                            '${l10n.get("sharedMemories")} (${memsLoading ? '...' : sharedMems.length})',
                      ),
                    ],
                  ),
                  Expanded(
                    child: memsLoading
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TabBarView(
                            children: [
                              personalMems.isEmpty
                                  ? Center(
                                      child: Text(l10n.get('noLongTermMemory')),
                                    )
                                  : ListView.builder(
                                      itemCount: personalMems.length,
                                      itemBuilder: (_, i) => ListTile(
                                        dense: true,
                                        title: Text(
                                          personalMems[i].toPromptLine(),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),
                              sharedMems.isEmpty
                                  ? Center(
                                      child: Text(l10n.get('noBaseMemory')),
                                    )
                                  : ListView.builder(
                                      itemCount: sharedMems.length,
                                      itemBuilder: (_, i) => ListTile(
                                        dense: true,
                                        title: Text(
                                          sharedMems[i].toPromptLine(),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAgentMemories(GroupMessage msg) {
    if (msg.senderId == null) return;
    _showGroupMemoryPanel(
      initialAgentId: msg.senderId,
      initialAgentName: msg.senderName,
    );
  }

  void _openMemoryPanel() {
    _showGroupMemoryPanel();
  }

  void _enterMultiSelect(int index) => setState(() {
    _multiSelectMode = true;
    _selectedIndices.add(index);
  });

  /// 微信式"选到这里"：以最早选中的消息为锚点，批量选中到本条
  void _selectRangeTo(int index) => setState(() {
    _selectedIndices.addAll(selectRangeTo(_selectedIndices, index));
  });

  /// 多选大滑动后，锚点（最早选中消息）是否已滚出可视区
  bool get _showSelectToHereButton {
    if (!_multiSelectMode ||
        _selectedIndices.isEmpty ||
        _visibleIndices.isEmpty) {
      return false;
    }
    final anchor = _selectedIndices.reduce((a, b) => a < b ? a : b);
    final first = _visibleIndices.reduce((a, b) => a < b ? a : b);
    final last = _visibleIndices.reduce((a, b) => a > b ? a : b);
    return anchor < first - 1 || anchor > last + 1;
  }

  /// 点击浮动"选到这里"：从锚点批量选中到当前可视区边缘
  void _selectRangeToVisibleEdge() {
    final anchor = _selectedIndices.reduce((a, b) => a < b ? a : b);
    final first = _visibleIndices.reduce((a, b) => a < b ? a : b);
    final last = _visibleIndices.reduce((a, b) => a > b ? a : b);
    final target = anchor < first ? first : last;
    setState(() {
      _selectedIndices.addAll(selectRangeTo(_selectedIndices, target));
    });
  }

  void _exitMultiSelect() => setState(() {
    _multiSelectMode = false;
    _selectedIndices.clear();
    _visibleIndices.clear();
  });

  void _toggleSelect(int index) => setState(() {
    if (_selectedIndices.contains(index)) {
      _selectedIndices.remove(index);
      if (_selectedIndices.isEmpty) _multiSelectMode = false;
    } else {
      _selectedIndices.add(index);
    }
  });

  void _copySelected() {
    final state = ref.read(groupProvider);
    final lines = _selectedIndices.toList()..sort();
    final buf = StringBuffer();
    for (final i in lines) {
      if (i < state.messages.length) {
        final msg = state.messages[i];
        buf.writeln(
          '${msg.senderName ?? (msg.isUser ? 'User' : 'Agent')}: ${msg.content}',
        );
      }
    }
    if (buf.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: buf.toString()));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制 ${lines.length} 条'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _deleteSelected() {
    final minIdx = _selectedIndices.reduce((a, b) => a < b ? a : b);
    _selectedIndices.clear();
    ref.read(groupProvider.notifier).deleteMessageFrom(minIdx);
    _exitMultiSelect();
  }

  void _showQuotaExceededDialog(QuotaType quota) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scheme = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.workspace_premium, color: scheme.primary, size: 32),
          title: Text(
            quota == QuotaType.ocr
                ? l10n.get('chatHistoryRecognition')
                : l10n.get('realReplyConversation'),
          ),
          content: Text(
            quota == QuotaType.ocr
                ? l10n.get('quotaOcrExceededMsg')
                : l10n.get('quotaRealReplyExceededMsg'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(groupProvider.notifier).clearQuotaExceeded();
              },
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(groupProvider.notifier).clearQuotaExceeded();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionCenterScreen(),
                  ),
                );
              },
              child: Text(l10n.get('goToSubscribe')),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupProvider);

    ref.listen<GroupState>(groupProvider, (prev, next) {
      if (next.messages.length > (prev?.messages.length ?? 0) &&
          !next.isLoading) {
        _scrollAfter(100);
      }
      if (next.quotaExceeded != null && (prev?.quotaExceeded == null)) {
        _showQuotaExceededDialog(next.quotaExceeded!);
      }
      // 同步锁：isLoading 从 true → false 表示所有 AI 回复完成，释放锁
      if (_wasLoading && !next.isLoading) {
        SyncWebSocketService.instance.releaseLock(groupId: widget.groupId);
        _syncBlockedByOther = false;
      }
      _wasLoading = next.isLoading;
    });

    final group = state.activeGroup;
    _syncNetworkIntroVisibility(group);
    final networkIntroGroup = _shouldShowNetworkIntro(group) ? group : null;
    final messages = state.messages;
    final members = state.members;
    final l10n = AppLocalizations.of(context);

    final agents = ref.watch(agentProvider.select((s) => s.agents));
    final memberNames = members
        .map((m) {
          final agent = agents.where((a) => a.id == m.agentId).firstOrNull;
          return agent?.name;
        })
        .whereType<String>()
        .toList();
    final presentNames = members
        .where((m) => m.isPresent)
        .map((m) {
          final agent = agents.where((a) => a.id == m.agentId).firstOrNull;
          final fallback = m.agentId.length > 6
              ? m.agentId.substring(0, 6)
              : m.agentId;
          return agent?.name ?? fallback;
        })
        .join(', ');

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: _multiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMultiSelect,
              )
            : null,
        title: _multiSelectMode
            ? Text(
                '已选 ${_selectedIndices.length} 条',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group?.name ?? l10n.get('groupChat'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    presentNames.isNotEmpty
                        ? presentNames
                        : l10n.get('noMembers'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
        actions: _multiSelectMode
            ? null
            : [
                if (state.isLoading)
                  IconButton(
                    icon: Icon(
                      Icons.stop_circle,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: l10n.get('stopGenerating'),
                    onPressed: _interrupt,
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    if (v == 'memory') {
                      _openMemoryPanel();
                    } else if (v == 'manage') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupManageScreen(groupId: widget.groupId),
                        ),
                      );
                    } else if (v == 'global') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AccountScreen(),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'memory',
                      child: Row(
                        children: [
                          Icon(Icons.storage, size: 20),
                          SizedBox(width: 8),
                          Text('记忆管理'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.group, size: 20),
                          SizedBox(width: 8),
                          Text('群聊管理'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'global',
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 20),
                          SizedBox(width: 8),
                          Text('账户管理'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: GestureDetector(
        onTap: () => _inputFocus.unfocus(),
        child: Column(
          children: [
            if (networkIntroGroup case final introGroup?)
              NetworkContentIntroCard.group(
                group: introGroup,
                memberNames: memberNames,
                onDismiss: () => _dismissNetworkIntro(introGroup),
              ),
            Expanded(
              child: messages.isEmpty
                  ? Center(child: Text(l10n.get('startGroupChat')))
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final msg = messages[i];
                            final name = _getAgentName(msg);
                            final color = _getAgentColor(msg);
                            final bubble = _GroupBubble(
                              message: msg,
                              agentName: name,
                              agentColor: color,
                              multiSelectMode: _multiSelectMode,
                              isSelected: _selectedIndices.contains(i),
                              onLongPress: (pos) =>
                                  _showMessageActions(msg, i, pos),
                              onToggle: () => _toggleSelect(i),
                              onAvatarTap: msg.isAgent
                                  ? () => _showAgentMemories(msg)
                                  : null,
                            );
                            // 微信式时间分割线：首条或间隔超过阈值时显示
                            final msgTime = DateTime.fromMillisecondsSinceEpoch(
                              msg.timestamp,
                            );
                            final prevTime = i > 0
                                ? DateTime.fromMillisecondsSinceEpoch(
                                    messages[i - 1].timestamp,
                                  )
                                : null;
                            Widget item = bubble;
                            if (shouldShowTimeDivider(msgTime, prevTime)) {
                              item = Column(
                                children: [
                                  TimeDivider(time: msgTime),
                                  bubble,
                                ],
                              );
                            }
                            // 多选模式下上报可见性，用于"选到这里"浮动按钮
                            if (_multiSelectMode) {
                              item = VisibilityDetector(
                                key: ValueKey('vis_$i'),
                                onVisibilityChanged: (info) {
                                  final visible = info.visibleFraction > 0.5;
                                  if (visible == _visibleIndices.contains(i)) {
                                    return;
                                  }
                                  setState(() {
                                    if (visible) {
                                      _visibleIndices.add(i);
                                    } else {
                                      _visibleIndices.remove(i);
                                    }
                                  });
                                },
                                child: item,
                              );
                            }
                            return item;
                          },
                        ),
                        // 多选大滑动后浮动"选到这里"按钮
                        if (_showSelectToHereButton)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: FilledButton.tonalIcon(
                              onPressed: _selectRangeToVisibleEdge,
                              icon: const Icon(
                                Icons.playlist_add_check_rounded,
                                size: 18,
                              ),
                              label: Text(l10n.get('selectToHere')),
                            ),
                          ),
                      ],
                    ),
            ),
            if (!_multiSelectMode && state.isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.get('agentsReplying'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (!_multiSelectMode && state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  state.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_multiSelectMode) _buildMultiSelectBar(),
            if (!_multiSelectMode) _buildInputArea(l10n),
          ],
        ),
      ),
    );
  }

  bool _shouldShowNetworkIntro(GroupChat? group) =>
      group?.networkSource == NetworkCopySource.downloaded &&
      group?.networkId != null &&
      !_networkIntroDismissed;

  void _syncNetworkIntroVisibility(GroupChat? group) {
    final identity =
        group?.networkSource == NetworkCopySource.downloaded &&
            group?.networkId != null
        ? '${group!.networkId}:${group.networkVersion}'
        : null;
    if (identity == _networkIntroIdentity) return;
    _networkIntroIdentity = identity;
    _networkIntroDismissed = identity == null;
    if (group == null || group.networkId == null || identity == null) return;
    NetworkContentIntroStore.isDismissed(
      type: 'group',
      networkId: group.networkId!,
      version: group.networkVersion,
    ).then((dismissed) {
      if (mounted && _networkIntroIdentity == identity) {
        setState(() => _networkIntroDismissed = dismissed);
      }
    });
  }

  Future<void> _dismissNetworkIntro(GroupChat group) async {
    setState(() => _networkIntroDismissed = true);
    if (group.networkId == null) return;
    await NetworkContentIntroStore.dismiss(
      type: 'group',
      networkId: group.networkId!,
      version: group.networkVersion,
    );
  }

  Widget _buildMultiSelectBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: _exitMultiSelect,
            ),
            const SizedBox(width: 4),
            Text(
              '${_selectedIndices.length} 条',
              style: const TextStyle(fontSize: 13),
            ),
            const Spacer(),
            IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: _copySelected,
            ),
            IconButton(
              tooltip: '删除',
              icon: Icon(Icons.delete, size: 20, color: scheme.error),
              onPressed: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final isFocused = _inputFocus.hasFocus;
    final hasText = _inputCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: AnimatedContainer(
          duration: AppTheme.durFast,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isFocused
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: isFocused
                    ? scheme.primary.withValues(alpha: 0.1)
                    : scheme.shadow.withValues(alpha: 0.06),
                blurRadius: isFocused ? 14 : 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    focusNode: _inputFocus,
                    controller: _inputCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.get('typeMessage'),
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TweenAnimationBuilder<double>(
                key: ValueKey(_inputCtrl.text.hashCode),
                tween: Tween(begin: 0.85, end: 1.0),
                duration: AppTheme.durFast,
                curve: Curves.easeOutBack,
                builder: (ctx, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: AnimatedContainer(
                  duration: AppTheme.durFast,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasText
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _send,
                    child: Icon(
                      Icons.send_rounded,
                      color: hasText ? Colors.white : scheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAgentName(GroupMessage msg) {
    if (msg.isUser) return 'You';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return msg.senderName!;
    }
    final agents = ref.read(agentProvider).agents;
    final agent = agents.where((a) => a.id == msg.senderId).firstOrNull;
    return agent?.name ?? 'AI';
  }

  int _getAgentColor(GroupMessage msg) {
    if (msg.senderId != null) {
      final agents = ref.read(agentProvider).agents;
      final agent = agents.where((a) => a.id == msg.senderId).firstOrNull;
      if (agent != null) return agent.avatarColor;
    }
    return 0xFFCFD8DC;
  }
}

class _GroupBubble extends StatelessWidget {
  final GroupMessage message;
  final String agentName;
  final int agentColor;
  final bool multiSelectMode;
  final bool isSelected;
  final void Function(Offset position)? onLongPress;
  final VoidCallback? onToggle;
  final VoidCallback? onAvatarTap;

  const _GroupBubble({
    required this.message,
    required this.agentName,
    required this.agentColor,
    this.multiSelectMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onToggle,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final timeStr = DateFormat(
      'HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final onBubbleColor = isUser ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (multiSelectMode && !isUser)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!isUser)
            GestureDetector(onTap: onAvatarTap, child: _agentAvatar()),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPressStart: onLongPress != null
                  ? (d) {
                      HapticFeedback.lightImpact();
                      onLongPress!(d.globalPosition);
                    }
                  : null,
              onTap: multiSelectMode ? onToggle : null,
              child: EchoBubbleSurface(
                isUser: isUser,
                isSelected: isSelected,
                maxWidth: ResponsiveLayout.bubbleMaxWidth(context),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser)
                      Text(
                        agentName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (!isUser) const SizedBox(height: 2),
                    Text(
                      message.isStreaming
                          ? '${message.content}▌'
                          : message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: onBubbleColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: onBubbleColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (multiSelectMode && isUser)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!multiSelectMode && isUser)
            Consumer(
              builder: (context, ref, _) {
                final avatar = ref.watch(authProvider).user?.avatar;
                if (avatar != null && avatar.isNotEmpty) {
                  return UserAvatar(avatar: avatar, radius: 16);
                }
                return Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: scheme.onPrimary, size: 18),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _agentAvatar() {
    return AgentAvatar(
      name: agentName,
      avatarColor: agentColor,
      size: 32,
      radius: 16,
      fontSize: 12,
      showShadow: false,
    );
  }
}
