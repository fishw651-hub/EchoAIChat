import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../services/draft_service.dart';
import 'network_upload_screen.dart';

/// 草稿箱页面
///
/// 展示本地保存的上传草稿，支持继续编辑和删除。
/// Tab 分为：全部 / 智能体 / 群聊。
class DraftBoxScreen extends ConsumerStatefulWidget {
  final String? initialType; // 'agent' or 'group'，默认 null 显示全部
  const DraftBoxScreen({super.key, this.initialType});

  @override
  ConsumerState<DraftBoxScreen> createState() => _DraftBoxScreenState();
}

class _DraftBoxScreenState extends ConsumerState<DraftBoxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final DraftService _draftService = DraftService();
  List<Map<String, dynamic>> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    int initialIndex = 0;
    if (widget.initialType == 'agent') {
      initialIndex = 1;
    } else if (widget.initialType == 'group') {
      initialIndex = 2;
    }
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadDrafts();
    });
    _loadDrafts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    setState(() => _loading = true);
    try {
      final type = switch (_tabController.index) {
        1 => 'agent',
        2 => 'group',
        _ => null,
      };
      final drafts = await _draftService.listDrafts(type: type);
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmClearAll() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: scheme.error, size: 32),
        title: Text(l10n.get('clearDraftBox')),
        content: Text(l10n.get('clearDraftsConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError),
            onPressed: () async {
              await _draftService.deleteDrafts(
                _drafts.map((d) => d['id'] as String),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadDrafts();
            },
            child: Text(l10n.get('clear')),
          ),
        ],
      ),
    );
  }

  String _formatTime(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${t.month}-${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('draftBox')),
        actions: [
          if (_drafts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.get('clear'),
              onPressed: _confirmClearAll,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.get('all')),
            Tab(text: l10n.get('agent')),
            Tab(text: l10n.get('group')),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadDrafts,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _drafts.length,
                    itemBuilder: (_, i) =>
                        _buildDraftTile(_drafts[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.drafts_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(l10n.get('noDraftsYet'),
              style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(l10n.get('noDraftsHint'),
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildDraftTile(Map<String, dynamic> draft) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final id = draft['id'] as String;
    final type = (draft['type'] as String?) ?? 'agent';
    final name = (draft['name'] as String?) ?? l10n.get('unnamedDraft');
    final coverColor =
        (draft['cover_color'] as num?)?.toInt() ?? 0xFFE8F5E9;
    final updatedAt = (draft['updated_at'] as num?)?.toInt() ?? 0;
    final isGroup = type == 'group';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(coverColor),
          child: Icon(
            isGroup ? Icons.group : Icons.person,
            color: scheme.onSurface,
            size: 20,
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatTime(updatedAt)} · ${isGroup ? l10n.get('group') : l10n.get('agent')}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NetworkUploadScreen(
                      type: type,
                      draftId: id,
                    ),
                  ),
                );
                if (mounted) _loadDrafts();
              },
              child: Text(l10n.get('continueEdit')),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: l10n.get('delete'),
              onPressed: () async {
                await _draftService.deleteDraft(id);
                _loadDrafts();
              },
            ),
          ],
        ),
      ),
    );
  }
}
