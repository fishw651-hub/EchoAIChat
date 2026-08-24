import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/group_provider.dart';
import '../services/group_export_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'group_chat_screen.dart';

/// 网络群聊详情页
class NetworkGroupDetailScreen extends ConsumerStatefulWidget {
  final int groupId;
  const NetworkGroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<NetworkGroupDetailScreen> createState() =>
      _NetworkGroupDetailScreenState();
}

class _NetworkGroupDetailScreenState
    extends ConsumerState<NetworkGroupDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _downloading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initAfterAuth();
  }

  Future<void> _initAfterAuth() async {
    await ref.read(authProvider.notifier).ready;
    if (!mounted) return;
    NetworkService().setToken(ref.read(authProvider).jwtToken);
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final data = await NetworkService().getGroupDetail(widget.groupId);
      if (mounted) {
        setState(() {
          _detail = data;
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

  Future<void> _download() async {
    if (_downloading) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _downloading = true);
    try {
      final data = await NetworkService().downloadGroup(widget.groupId);
      final groupId = await GroupExportService().deserializeDownloaded(data);
      await ref.read(groupProvider.notifier).loadGroups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.get('addedToMyGroups')),
          duration: const Duration(seconds: 2),
        ),
      );
      _showEnterGroupDialog(
          groupId, _detail?['name'] as String? ?? l10n.get('group'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('downloadFailed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showEnterGroupDialog(String groupId, String name) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('downloadSuccess')),
        content: Text(l10n.getP('enterGroupWithName', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('laterDismiss')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => GroupChatScreen(groupId: groupId)),
              );
            },
            child: Text(l10n.get('enterGroup')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('groupDetail'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? _buildError(scheme)
              : _buildContent(scheme),
      bottomNavigationBar: _detail == null ? null : _buildBottomBar(scheme),
    );
  }

  Widget _buildError(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off,
              size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(_errorMsg!,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadDetail,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.get('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    final d = _detail!;
    final l10n = AppLocalizations.of(context);
    final name = d['name'] as String? ?? l10n.get('unnamed');
    final description = d['description'] as String? ?? '';
    final groupPersona = d['group_persona'] as String? ?? '';
    final worldSetting = d['world_setting'] as String? ?? '';
    final speechMode = d['speech_mode'] as String? ?? 'free';
    final isSimulatorMode = (d['is_simulator_mode'] as bool?) ?? false;
    final avatarColor = (d['avatar_color'] as num?)?.toInt() ?? 0xFF607D8B;
    final avatarPath = d['avatar_path'] as String?;
    final uploader = d['uploader_name'] as String? ?? l10n.get('anonymous');
    final downloadCount = (d['download_count'] as num?)?.toInt() ?? 0;
    final version = (d['version'] as num?)?.toInt() ?? 1;
    final tags =
        (d['tags'] as List? ?? []).map((e) => e.toString()).toList();
    final members =
        (d['members'] as List? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Center(child: _buildBigAvatar(avatarPath, avatarColor, name)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _metaChip(Icons.person_outline, uploader, scheme),
              _metaChip(Icons.download_outlined, '$downloadCount', scheme),
              _metaChip(Icons.history, 'v$version', scheme),
            ],
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: tags
                  .map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (description.isNotEmpty) ...[
          _sectionTitle(l10n.get('descriptionText'), scheme),
          _card(description, scheme),
        ],
        if (groupPersona.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(l10n.get('groupPersonaSection'), scheme),
          _card(groupPersona, scheme),
        ],
        if (worldSetting.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(l10n.get('worldSettingSection'), scheme),
          _card(worldSetting, scheme),
        ],
        const SizedBox(height: 16),
        _sectionTitle(l10n.get('settings'), scheme),
        _card(_buildSettingsText(speechMode, isSimulatorMode), scheme),
        const SizedBox(height: 16),
        _sectionTitle(l10n.getP('membersCount', {'n': '${members.length}'}), scheme),
        const SizedBox(height: 8),
        ...members.map((m) => _buildMemberTile(m, scheme)),
      ],
    );
  }

  String _buildSettingsText(String speechMode, bool isSimulatorMode) {
    final l10n = AppLocalizations.of(context);
    final modeText = speechMode == 'director'
        ? l10n.get('directorMode')
        : l10n.get('freeMode');
    final simText = isSimulatorMode
        ? l10n.get('turnedOn')
        : l10n.get('turnedOff');
    return '${l10n.get('speechMode')}：$modeText\n${l10n.get('simulatorMode')}：$simText';
  }

  Widget _buildMemberTile(Map<String, dynamic> m, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    final name = m['name'] as String? ?? l10n.get('member');
    final gender = m['gender'] as String? ?? '';
    final description = m['description'] as String? ?? '';
    final persona = m['persona'] as String? ?? '';
    final avatarColor = (m['avatar_color'] as num?)?.toInt() ?? 0xFF607D8B;
    final avatar = m['avatar'] as String?;
    final role = m['role'] as String? ?? 'member';
    final roleText = role == 'director'
        ? l10n.get('director')
        : (role == 'narrator' ? l10n.get('narrator') : l10n.get('member'));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMemberAvatar(avatar, avatarColor, name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(roleText,
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onPrimaryContainer)),
                    ),
                    if (gender.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(gender,
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                if (persona.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(persona,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(String? avatar, int avatarColor, String name) {
    final url = _resolveAvatarUrl(avatar);
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 44,
          height: 44,
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
        width: 44,
        height: 44,
        color: Color(avatarColor),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildBigAvatar(
      String? avatarPath, int avatarColor, String name) {
    final url = _resolveAvatarUrl(avatarPath);
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          url,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackBigAvatar(avatarColor, name),
        ),
      );
    }
    return _fallbackBigAvatar(avatarColor, name);
  }

  Widget _fallbackBigAvatar(int avatarColor, String name) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 80,
        height: 80,
        color: Color(avatarColor),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface)),
    );
  }

  Widget _card(String text, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 14, height: 1.6, color: scheme.onSurface),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85))),
      ],
    );
  }

  Widget _buildBottomBar(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
              top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        child: FilledButton.icon(
          onPressed: _downloading ? null : _download,
          icon: _downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download),
          label: Text(_downloading ? l10n.get('downloading') : l10n.get('download')),
        ),
      ),
    );
  }
}

/// 解析服务端 avatar_path 为完整 URL
String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${ServerConfig.baseUrl}$raw';
  return '${ServerConfig.baseUrl}/$raw';
}
