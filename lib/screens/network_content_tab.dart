import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/agent_provider.dart';
import '../providers/app_event_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/home_tab_provider.dart';
import '../services/agent_export_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'draft_box_screen.dart';
import 'network_group_detail_screen.dart';
import 'network_upload_screen.dart';

/// Ocean 主题 4 Tab 架构中"发现"Tab 的内容页面
///
/// 当前类型（网络智能体/网络群聊）默认由 [discoveryTabTypeProvider] 控制，
/// 通过 HomeScreen 的子页分段控件切换（移动端浮于底部导航栏上方，
/// 桌面端位于内容区顶部）；移动端 6 页 PageView 中两个发现子页分别传入
/// [fixedType] 固定类型，此时忽略 provider 变化、各自独立保活；
/// 右上角提供上传与草稿箱入口；
/// 主体复用 network_market_screen 的列表逻辑（拉取、分页、下载并切换）。
class NetworkContentTab extends ConsumerStatefulWidget {
  const NetworkContentTab({super.key, this.fixedType});

  /// 固定列表类型（'agent'/'group'）。非空时不再跟随
  /// [discoveryTabTypeProvider]，用于移动端 PageView 的独立子页。
  final String? fixedType;

  @override
  ConsumerState<NetworkContentTab> createState() => _NetworkContentTabState();
}

class _NetworkContentTabState extends ConsumerState<NetworkContentTab> {
  /// 当前列表类型：'agent' 网络智能体 / 'group' 网络群聊
  /// （fixedType 优先，否则跟随导航栏切换）
  String get _type =>
      widget.fixedType ??
      (ref.read(discoveryTabTypeProvider) ? 'group' : 'agent');
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 20;
  bool _loading = false;
  bool _loadingMore = false;
  bool _refreshingExistingItems = false;
  String? _errorMsg;
  int? _downloadingId;
  int _loadRevision = 0;

  String? _lastToken;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 等 AuthNotifier 异步加载完成后再设置 token 并加载，避免首次空 token 触发 401
    _initAfterAuth();
  }

  Future<void> _initAfterAuth() async {
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.ready;
    if (!mounted) return;
    final token = ref.read(authProvider).jwtToken;
    _lastToken = token;
    NetworkService().setToken(token);
    _loadItems(reset: true);
  }

  @override
  void dispose() {
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

  Future<void> _loadItems({
    bool reset = false,
    bool preserveItems = false,
    bool forceRefresh = false,
  }) async {
    final revision = ++_loadRevision;
    final requestType = _type;
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _refreshingExistingItems = preserveItems && _items.isNotEmpty;
      _errorMsg = null;
      if (reset && !preserveItems) _items = [];
    });
    try {
      final result = requestType == 'agent'
          ? await NetworkService().listAgents(
              page: _page,
              pageSize: _pageSize,
              sort: 'newest',
              forceRefresh: forceRefresh,
            )
          : await NetworkService().listGroups(
              page: _page,
              pageSize: _pageSize,
              sort: 'newest',
              forceRefresh: forceRefresh,
            );
      final list = (result['list'] as List? ?? []).cast<Map<String, dynamic>>();
      final total = (result['total'] as num?)?.toInt() ?? 0;
      if (mounted && revision == _loadRevision && requestType == _type) {
        setState(() {
          if (reset) {
            _items = list;
          } else {
            _items.addAll(list);
          }
          _total = total;
          _loading = false;
          _refreshingExistingItems = false;
        });
      }
    } catch (e) {
      if (mounted && revision == _loadRevision && requestType == _type) {
        setState(() {
          _loading = false;
          _refreshingExistingItems = false;
          if (!preserveItems || _items.isEmpty) _errorMsg = e.toString();
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    final revision = _loadRevision;
    final requestType = _type;
    try {
      _page++;
      final result = requestType == 'agent'
          ? await NetworkService().listAgents(
              page: _page,
              pageSize: _pageSize,
              sort: 'newest',
            )
          : await NetworkService().listGroups(
              page: _page,
              pageSize: _pageSize,
              sort: 'newest',
            );
      final list = (result['list'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted && revision == _loadRevision && requestType == _type) {
        setState(() {
          _items.addAll(list);
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (revision == _loadRevision) _page--;
      if (mounted && revision == _loadRevision) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 下载网络智能体并切换为当前聊天智能体
  Future<void> _downloadAndReplace(int id) async {
    if (_downloadingId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _downloadingId = id);
    try {
      final downloadedAgent = await AgentExportService.findDownloadedAgent(id);
      if (downloadedAgent != null &&
          AgentExportService.hasCompleteDownloadedContent(downloadedAgent)) {
        await ref.read(agentProvider.notifier).refresh();
        await ref
            .read(agentProvider.notifier)
            .setActiveAgent(downloadedAgent.id);
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
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
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    // 监听导航栏的类型切换：重新拉取对应列表（fixedType 子页忽略，类型恒定）
    if (widget.fixedType == null) {
      ref.listen<bool>(discoveryTabTypeProvider, (prev, next) {
        if (prev != next) _loadItems(reset: true);
      });
      // watch 保证切换类型时上传/草稿箱入口等用到 _type 的地方随之重建
      ref.watch(discoveryTabTypeProvider);
    }

    ref.listen<int>(
      appEventProvider.select((state) => state.networkAgentRevision),
      (previous, next) {
        if (previous != next && _type == 'agent') {
          _loadItems(reset: true, preserveItems: true, forceRefresh: true);
        }
      },
    );
    ref.listen<int>(
      appEventProvider.select((state) => state.networkGroupRevision),
      (previous, next) {
        if (previous != next && _type == 'group') {
          _loadItems(reset: true, preserveItems: true, forceRefresh: true);
        }
      },
    );

    // 监听登录状态变化：登录/登出/token 刷新后同步 token 并重新加载
    ref.listen<AuthState>(authProvider, (prev, next) {
      final newToken = next.jwtToken;
      if (newToken != _lastToken) {
        _lastToken = newToken;
        NetworkService().setToken(newToken);
        _loadItems(reset: true);
      }
    });

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // 顶部 AppBar 区域
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space3,
                  AppTheme.space2,
                  AppTheme.space3,
                  AppTheme.space3,
                ),
                child: Row(
                  children: [
                    Text(
                      l10n.get('tabDiscovery'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    // 右上：上传按钮
                    _iconButton(
                      icon: Icons.cloud_upload_outlined,
                      tip: l10n.get('syncUpload'),
                      scheme: scheme,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NetworkUploadScreen(type: _type),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: AppTheme.space2),
                    // 右上：草稿箱按钮
                    _iconButton(
                      icon: Icons.drafts_outlined,
                      tip: l10n.get('draftBox'),
                      scheme: scheme,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DraftBoxScreen(initialType: _type),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 主体列表
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildList(scheme)),
                if (_refreshingExistingItems)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tip,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppTheme.brLg,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          boxShadow: AppTheme.primaryShadowSm(scheme),
        ),
        child: Icon(icon, size: 20, color: scheme.primary),
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
            const SizedBox(height: AppTheme.space3),
            Text(
              _errorMsg!,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.space4),
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
      return RefreshIndicator(
        onRefresh: () => _loadItems(reset: true),
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: AppTheme.space3),
                  Text(
                    l10n.get('emptyContent'),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadItems(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space3,
          AppTheme.space1,
          AppTheme.space3,
          // 底部预留：悬浮导航栏(约108) + 子页分段控件(40) + 间距(12)
          160,
        ),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.space2),
        itemBuilder: (_, i) {
          if (i == _items.length) return _buildFooter(scheme);
          final item = _items[i];
          return _MarketTile(
            item: item,
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
      ),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.space4),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_items.length >= _total) {
      return Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Center(
          child: Text(
            l10n.get('noMoreData'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox(height: AppTheme.space4);
  }
}

/// 市场列表项（与 network_market_screen 风格一致）
class _MarketTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool isLoading;

  const _MarketTile({
    required this.item,
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
          padding: const EdgeInsets.all(AppTheme.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAvatar(avatarPath, avatarColor, name),
                  const SizedBox(width: AppTheme.space3),
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
                const SizedBox(height: AppTheme.space2),
                SizedBox(
                  height: 26,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (_, i) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tags[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.space2),
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
                  const SizedBox(width: AppTheme.space3),
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
String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${ServerConfig.baseUrl}$raw';
  return '${ServerConfig.baseUrl}/$raw';
}
