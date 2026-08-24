import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/memory_provider.dart';
import '../providers/chat_provider.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../widgets/profile_mindmap_widget.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/echo_visual_surface.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.get('memoryManagementTitle')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              AppTheme.space3,
              0,
              AppTheme.space3,
              AppTheme.space2,
            ),
            padding: const EdgeInsets.all(AppTheme.space1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: AppTheme.brMd,
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.48),
                width: 0.5,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.get('shortTermTab')),
                Tab(text: l10n.get('longTermTab')),
                Tab(text: l10n.get('baseMemoryTab')),
                Tab(text: l10n.get('userProfileTab')),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _ShortTermTab(),
          const _LongTermTab(),
          const _BaseMemoryTab(),
          const ProfileMindMapWidget(),
        ],
      ),
    );
  }
}

// ─── Short-term Memory Tab ──────────────────

class _ShortTermTab extends ConsumerWidget {
  const _ShortTermTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryService = ref.read(memoryServiceProvider);
    final messages = memoryService.shortTermMessages;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        EchoPanel(
          margin: const EdgeInsets.all(AppTheme.space4),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.getP('currentRounds', {'n': messages.length.toString()}),
                style: const TextStyle(fontSize: 16),
              ),
              TextButton.icon(
                onPressed: () {
                  ref.read(chatProvider.notifier).clearChat();
                },
                icon: const Icon(Icons.delete),
                label: Text(l10n.get('clearAll')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final msg = messages[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    msg.role == 'user' ? 'U' : 'A',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(
                  '${msg.id} [${msg.role}]',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  msg.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Long-term Memory Tab ──────────────────

class _LongTermTab extends ConsumerWidget {
  const _LongTermTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(longTermProvider);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            AppTheme.space2,
            AppTheme.space4,
            AppTheme.space1,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTheme.space1,
              children: [
                TextButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.get('manualAdd')),
                ),
                TextButton.icon(
                  onPressed: () => _confirmClear(context, ref),
                  icon: const Icon(Icons.delete_forever),
                  label: Text(l10n.get('clearAllMemory')),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: state.memories.isEmpty
              ? Center(child: Text(l10n.get('noLongTermMemory')))
              : ListView.builder(
                  itemCount: state.memories.length,
                  itemBuilder: (_, i) {
                    final m = state.memories[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(
                          '${m.id} [${m.field}]',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(m.content),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showEditDialog(context, ref, m),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete,
                                size: 20,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              onPressed: () {
                                ref
                                    .read(longTermProvider.notifier)
                                    .deleteMemory(m.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            l10n.getP('totalLongTermMemories', {
              'n': state.memories.length.toString(),
            }),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final contentController = TextEditingController();
    String selectedField = 'time';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.get('addLongTermMemory')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedField,
                decoration: InputDecoration(labelText: l10n.get('field')),
                items: LongTermMemory.validFields.map((f) {
                  return DropdownMenuItem(value: f, child: Text(f));
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedField = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(labelText: l10n.get('content')),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                contentController.dispose();
                Navigator.pop(ctx);
              },
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (contentController.text.trim().isNotEmpty) {
                  ref
                      .read(longTermProvider.notifier)
                      .addMemory(
                        field: selectedField,
                        content: contentController.text.trim(),
                      );
                  contentController.dispose();
                  Navigator.pop(ctx);
                }
              },
              child: Text(l10n.get('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, LongTermMemory m) {
    final l10n = AppLocalizations.of(context);
    final contentController = TextEditingController(text: m.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.getP('editMemoryTitle', {'id': m.id, 'field': m.field}),
        ),
        content: TextField(
          controller: contentController,
          decoration: InputDecoration(labelText: l10n.get('content')),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () {
              contentController.dispose();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final updated = m.copyWith(
                content: contentController.text.trim(),
              );
              ref.read(longTermProvider.notifier).updateMemory(updated);
              contentController.dispose();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmClearAllTitle')),
        content: Text(l10n.get('confirmClearAllContent')),
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
            onPressed: () {
              ref.read(longTermProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('confirmClearAction')),
          ),
        ],
      ),
    );
  }
}

// ─── Base Memory Tab ──────────────────

class _BaseMemoryTab extends ConsumerWidget {
  const _BaseMemoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(baseProvider);
    final settings = state.memories.where((m) => m.isSetting).toList();
    final events = state.memories.where((m) => m.isEvent).toList();
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            AppTheme.space2,
            AppTheme.space4,
            AppTheme.space1,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTheme.space1,
              children: [
                TextButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.get('addSetting')),
                ),
                TextButton.icon(
                  onPressed: () => _confirmClearEvents(context, ref),
                  icon: const Icon(Icons.delete_forever),
                  label: Text(l10n.get('clearEvents')),
                ),
                TextButton.icon(
                  onPressed: () => _confirmClearAll(context, ref),
                  icon: const Icon(Icons.delete_forever),
                  label: Text(l10n.get('resetAll')),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (settings.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Text(
                    l10n.get('settingItemsLabel'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                ...settings.map(
                  (m) => Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    child: ListTile(
                      title: Text(
                        m.id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(m.content),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showEditDialog(context, ref, m),
                      ),
                    ),
                  ),
                ),
              ],
              if (events.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Text(
                    l10n.get('eventItemsLabel'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                ...events.map(
                  (m) => Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListTile(
                      title: Text(
                        m.id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(m.content),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () {
                          ref.read(baseProvider.notifier).deleteMemory(m.id);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            l10n.getP('baseMemoryCount', {
              'settings': settings.length.toString(),
              'events': events.length.toString(),
            }),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('addBaseSetting')),
        content: TextField(
          controller: contentController,
          decoration: InputDecoration(labelText: l10n.get('settingContent')),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () {
              contentController.dispose();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (contentController.text.trim().isNotEmpty) {
                await ref
                    .read(baseProvider.notifier)
                    .createSetting(contentController.text.trim());
                contentController.dispose();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, BaseMemory m) {
    final l10n = AppLocalizations.of(context);
    final contentController = TextEditingController(text: m.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.getP('editBaseItem', {'id': m.id})),
        content: TextField(
          controller: contentController,
          decoration: InputDecoration(labelText: l10n.get('content')),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () {
              contentController.dispose();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final updated = BaseMemory(
                id: m.id,
                type: m.type,
                content: contentController.text.trim(),
                createdAt: m.createdAt,
              );
              ref.read(baseProvider.notifier).updateMemory(updated);
              contentController.dispose();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }

  void _confirmClearEvents(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmClearEventsTitle')),
        content: Text(l10n.get('confirmClearEventsContent')),
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
            onPressed: () {
              ref.read(baseProvider.notifier).clearEvents();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('confirmClearAction')),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmResetAllTitle')),
        content: Text(l10n.get('confirmResetAllContent')),
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
            onPressed: () {
              ref.read(baseProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('confirmResetAction')),
          ),
        ],
      ),
    );
  }
}
