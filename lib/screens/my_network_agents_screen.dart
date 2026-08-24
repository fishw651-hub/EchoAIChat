import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/app_event_provider.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/network_reject_reason.dart';
import 'network_market_screen.dart';
import 'network_upload_screen.dart';

/// 我的网络智能体管理页面
/// 列出当前用户已上传的网络智能体，支持编辑、下架，顶部可新建上传，底部可浏览网络市场
class MyNetworkAgentsScreen extends ConsumerStatefulWidget {
  const MyNetworkAgentsScreen({super.key});

  @override
  ConsumerState<MyNetworkAgentsScreen> createState() =>
      _MyNetworkAgentsScreenState();
}

class _MyNetworkAgentsScreenState extends ConsumerState<MyNetworkAgentsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _errorMsg;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _initAfterAuth();
  }

  Future<void> _initAfterAuth() async {
    await ref.read(authProvider.notifier).ready;
    if (!mounted) return;
    NetworkService().setToken(ref.read(authProvider).jwtToken);
    _loadItems();
  }

  Future<void> _loadItems({bool silent = false}) async {
    final revision = ++_loadRevision;
    if (!silent) {
      setState(() {
        _loading = true;
        _errorMsg = null;
      });
    }
    try {
      final list = await NetworkService().listMyAgentUploads();
      if (mounted && revision == _loadRevision) {
        setState(() {
          _items = list;
          _loading = false;
          _errorMsg = null;
        });
      }
    } catch (e) {
      if (mounted && revision == _loadRevision && !silent) {
        setState(() {
          _errorMsg = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    ref.listen<int>(
      appEventProvider.select((state) => state.myUploadsRevision),
      (previous, next) {
        if (previous != next) _loadItems(silent: true);
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('myNetworkAgents')),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: l10n.get('uploadAgent'),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const NetworkUploadScreen(type: 'agent'),
                ),
              );
              _loadItems();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
          ? _buildError(scheme, l10n)
          : _items.isEmpty
          ? _buildEmpty(scheme, l10n)
          : RefreshIndicator(
              onRefresh: _loadItems,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _buildTile(_items[i], scheme, l10n),
              ),
            ),
      bottomNavigationBar: _loading || _errorMsg != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const NetworkMarketScreen(initialType: 'agent'),
                    ),
                  ),
                  icon: const Icon(Icons.explore, size: 18),
                  label: Text(l10n.get('browseMarket')),
                ),
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════
  //  状态视图
  // ═══════════════════════════════════════════

  Widget _buildError(ColorScheme scheme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMsg ?? l10n.get('loadFailed'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadItems, child: Text(l10n.get('retry'))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_queue, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              l10n.get('emptyAgentUploads'),
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NetworkUploadScreen(type: 'agent'),
                  ),
                );
                _loadItems();
              },
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: Text(l10n.get('uploadAgent')),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  列表项
  // ═══════════════════════════════════════════

  Widget _buildTile(
    Map<String, dynamic> item,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final id = (item['id'] as num?)?.toInt();
    final name = item['name'] as String? ?? l10n.get('unnamed');
    final description = item['description'] as String? ?? '';
    final status = item['status'] as String? ?? 'pending';
    final downloadCount = (item['download_count'] as num?)?.toInt() ?? 0;
    final rejectReason = item['reject_reason'] as String? ?? '';
    final avatarColor = (item['avatar_color'] as num?)?.toInt() ?? 0xFF607D8B;
    final avatarPath = item['avatar_path'] as String?;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () async {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  NetworkUploadScreen(type: 'agent', existingData: item),
            ),
          );
          _loadItems();
        },
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) {
                      if (v == 'edit' && id != null) {
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NetworkUploadScreen(
                              type: 'agent',
                              existingData: item,
                            ),
                          ),
                        ).then((_) => _loadItems());
                      } else if (v == 'takedown' && id != null) {
                        _confirmTakeDown(id, name, l10n);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit, size: 18),
                            const SizedBox(width: 8),
                            Text(l10n.get('edit')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'takedown',
                        child: Row(
                          children: [
                            Icon(
                              Icons.visibility_off,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.get('takeDown'),
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatusChip(status, scheme, l10n),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.download,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$downloadCount',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (status == 'rejected' && rejectReason.isNotEmpty) ...[
                const SizedBox(height: 10),
                NetworkRejectReason(
                  label: l10n.get('rejectReasonLabel'),
                  reason: rejectReason,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    String status,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final (label, color) = switch (status) {
      'approved' => (l10n.get('statusApproved'), scheme.primary),
      'rejected' => (l10n.get('statusRejected'), scheme.error),
      'taken_down' => (l10n.get('statusTakenDown'), scheme.onSurfaceVariant),
      _ => (l10n.get('statusPending'), scheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
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
            name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _confirmTakeDown(int id, String name, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('takeDown')),
        content: Text(l10n.get('takeDownConfirmContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await NetworkService().takeDownAgent(id);
                _loadItems();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${l10n.get('takeDown')}: $name')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${l10n.get('takeDownFailed')}: $e'),
                    ),
                  );
                }
              }
            },
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }
}

String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${ServerConfig.baseUrl}$raw';
  return '${ServerConfig.baseUrl}/$raw';
}
