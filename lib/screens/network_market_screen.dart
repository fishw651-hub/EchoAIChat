import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../services/agent_export_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'network_group_detail_screen.dart';

/// 网络市场列表页（智能体 / 群聊）
class NetworkMarketScreen extends ConsumerStatefulWidget {
  final String initialType; // 'agent' or 'group'
  const NetworkMarketScreen({super.key, this.initialType = 'agent'});

  @override
  ConsumerState<NetworkMarketScreen> createState() =>
      _NetworkMarketScreenState();
}

class _NetworkMarketScreenState extends ConsumerState<NetworkMarketScreen> {
  late String _type = widget.initialType;
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  List<String> _presetTags = [];
  List<String> _selectedTags = [];
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 20;
  String _sort = 'newest';
  bool _loading = false;
  bool _loadingMore = false;
  String? _errorMsg;
  int? _downloadingId; // 正在下载的网络智能体 ID

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchCtrl.addListener(() => setState(() {}));
    _initAfterAuth();
  }

  Future<void> _initAfterAuth() async {
    await ref.read(authProvider.notifier).ready;
    if (!mounted) return;
    NetworkService().setToken(ref.read(authProvider).jwtToken);
    _loadPresetTags();
    _loadItems(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadPresetTags() async {
    try {
      final tags = await NetworkService().getPresetTags();
      if (mounted) setState(() => _presetTags = tags);
    } catch (_) {
      // 静默失败：标签加载失败不阻塞列表
    }
  }

  /// 下载网络智能体并切换为当前聊天智能体
  Future<void> _downloadAndReplace(int id) async {
    // 全局阻塞：任意一项正在下载时拒绝新下载，避免状态竞争
    if (_downloadingId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _downloadingId = id);
    try {
      final downloadedAgent = await AgentExportService.findDownloadedAgent(id);
      if (downloadedAgent != null) {
        await ref.read(agentProvider.notifier).refresh();
        await ref
            .read(agentProvider.notifier)
            .setActiveAgent(downloadedAgent.id);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
          (route) => route.isFirst,
        );
        return;
      }

      final data = await NetworkService().downloadAgent(id);
      final agent = await AgentExportService.deserializeDownloaded(data);
      await ref.read(agentProvider.notifier).refresh();
      await ref.read(agentProvider.notifier).setActiveAgent(agent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.getP('switchedToAgent', {'name': agent.name})),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('downloadFailed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _loadItems({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _errorMsg = null;
      if (reset) _items = [];
    });
    try {
      final q = _searchCtrl.text.trim().isEmpty
          ? null
          : _searchCtrl.text.trim();
      final tags = _selectedTags.isEmpty ? null : _selectedTags;
      final result = _type == 'agent'
          ? await NetworkService().listAgents(
              q: q,
              tags: tags,
              page: _page,
              pageSize: _pageSize,
              sort: _sort,
            )
          : await NetworkService().listGroups(
              q: q,
              tags: tags,
              page: _page,
              pageSize: _pageSize,
              sort: _sort,
            );
      final list = (result['list'] as List? ?? []).cast<Map<String, dynamic>>();
      final total = (result['total'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {
          if (reset) {
            _items = list;
          } else {
            _items.addAll(list);
          }
          _total = total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = e.toString();
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      _page++;
      final q = _searchCtrl.text.trim().isEmpty
          ? null
          : _searchCtrl.text.trim();
      final tags = _selectedTags.isEmpty ? null : _selectedTags;
      final result = _type == 'agent'
          ? await NetworkService().listAgents(
              q: q,
              tags: tags,
              page: _page,
              pageSize: _pageSize,
              sort: _sort,
            )
          : await NetworkService().listGroups(
              q: q,
              tags: tags,
              page: _page,
              pageSize: _pageSize,
              sort: _sort,
            );
      final list = (result['list'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _items.addAll(list);
          _loadingMore = false;
        });
      }
    } catch (_) {
      _page--;
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _loadItems(reset: true);
  }

  void _switchType() {
    setState(() {
      _type = _type == 'agent' ? 'group' : 'agent';
      _selectedTags = [];
    });
    _loadItems(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _type == 'agent'
              ? l10n.get('networkMarketAgent')
              : l10n.get('networkMarketGroup'),
        ),
        actions: [
          IconButton(
            icon: Icon(_type == 'agent' ? Icons.groups : Icons.person),
            tooltip: _type == 'agent'
                ? l10n.get('switchToGroup')
                : l10n.get('switchToAgent'),
            onPressed: _switchType,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(scheme),
          if (_presetTags.isNotEmpty) _buildTagChips(scheme),
          _buildSortBar(scheme),
          Expanded(child: _buildList(scheme)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: _type == 'agent'
              ? l10n.get('searchAgentHint')
              : l10n.get('searchGroupHint'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _loadItems(reset: true);
                  },
                )
              : null,
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadItems(reset: true),
      ),
    );
  }

  Widget _buildTagChips(ColorScheme scheme) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _presetTags.length,
        itemBuilder: (_, i) {
          final tag = _presetTags[i];
          final selected = _selectedTags.contains(tag);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(tag),
              selected: selected,
              onSelected: (_) => _toggleTag(tag),
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontSize: 12,
              ),
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide(color: scheme.outlineVariant),
              shape: const StadiumBorder(),
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortBar(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _sortChip('newest', l10n.get('sortNewest'), scheme),
          const SizedBox(width: 8),
          _sortChip('popular', l10n.get('sortPopular'), scheme),
          const Spacer(),
          Text(
            l10n.getP('totalCount', {'n': '$_total'}),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String value, String label, ColorScheme scheme) {
    final selected = _sort == value;
    return InkWell(
      onTap: () {
        if (!selected) {
          setState(() => _sort = value);
          _loadItems(reset: true);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMsg != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMsg!,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _loadItems(reset: true),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.get('retry')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.get('emptyContent'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == _items.length) return _buildFooter(scheme);
        final item = _items[i];
        return _MarketTile(
          item: item,
          presetTags: _presetTags.toSet(),
          isLoading: _downloadingId == (item['id'] as num?)?.toInt(),
          onTap: () {
            final id = (item['id'] as num?)?.toInt();
            if (id == null) return;
            if (_type == 'agent') {
              _downloadAndReplace(id);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NetworkGroupDetailScreen(groupId: id),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_items.length >= _total) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            l10n.get('noMoreData'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

/// 市场列表项
class _MarketTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final Set<String> presetTags;
  final VoidCallback onTap;
  final bool isLoading;

  const _MarketTile({
    required this.item,
    required this.presetTags,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final name = item['name'] as String? ?? l10n.get('unnamed');
    final description = item['description'] as String? ?? '';
    final uploader = item['uploader_name'] as String? ?? l10n.get('anonymous');
    final downloadCount = (item['download_count'] as num?)?.toInt() ?? 0;
    final avatarColor = (item['avatar_color'] as num?)?.toInt() ?? 0xFF607D8B;
    final avatarPath = item['avatar_path'] as String?;
    final tags = (item['tags'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAvatar(avatarPath, avatarColor, name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          size: 20,
                        ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 26,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (_, i) {
                      final tag = tags[i];
                      final isPreset = presetTags.contains(tag);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isPreset
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 11,
                            color: isPreset
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    uploader,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.download_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$downloadCount',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? avatarPath, int avatarColor, String name) {
    final url = _resolveAvatarUrl(avatarPath);
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackAvatar(avatarColor, name),
        ),
      );
    }
    return _fallbackAvatar(avatarColor, name);
  }

  Widget _fallbackAvatar(int avatarColor, String name) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 50,
        height: 50,
        color: Color(avatarColor),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 解析服务端返回的 avatar_path 为完整 URL
/// - 完整 URL（http/https）原样返回
/// - 相对路径（/uploads/...）拼接 baseUrl
/// - 空字符串/null 返回 null
String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${ServerConfig.baseUrl}$raw';
  return '${ServerConfig.baseUrl}/$raw';
}
