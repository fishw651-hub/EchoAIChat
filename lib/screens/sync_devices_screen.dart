import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../models/sync_policy.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../services/auth_service.dart';
import '../services/device_id_service.dart';
import '../services/sync_service.dart';
import '../services/sync_scope.dart';
import '../theme/app_theme.dart';
import '../utils/sync_status.dart';
import 'subscription_center_screen.dart';

class SyncDevicesScreen extends ConsumerStatefulWidget {
  const SyncDevicesScreen({super.key});

  @override
  ConsumerState<SyncDevicesScreen> createState() => _SyncDevicesScreenState();
}

class _SyncDevicesScreenState extends ConsumerState<SyncDevicesScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _devices = [];
  String? _currentDeviceId;
  bool _loading = true;
  String? _error;
  int _registerAttempts = 0; // 防止设备注册失败时无限递归

  /// 同步中状态图标的旋转动画
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      final jwt = auth.jwtToken;
      if (jwt == null) {
        throw Exception(AppLocalizations.of(context).get('notLoggedIn'));
      }
      _currentDeviceId = await DeviceIdService.id;

      final svc = AuthService()..setTokens(jwt: jwt);
      final data = await svc.listDevices(deviceId: _currentDeviceId);
      await ref.read(syncProvider.notifier).loadPolicy();

      if (!mounted) return;
      setState(() {
        _devices =
            (data['devices'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];
        _loading = false;
      });

      // 后台注册当前设备（若未注册）
      await _maybeRegisterCurrentDevice(svc);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _maybeRegisterCurrentDevice(AuthService svc) async {
    // 重试次数限制，防止注册失败后 _loadData → _maybeRegisterCurrentDevice 无限递归
    if (_registerAttempts >= 3) return;
    _registerAttempts++;
    try {
      final exists = _devices.any((d) => d['device_id'] == _currentDeviceId);
      if (exists) return;
      await svc.registerCurrentDevice();
      if (!mounted) return;
      await _loadData();
    } catch (_) {}
  }

  Future<void> _setRole(String deviceId, String role) async {
    try {
      final auth = ref.read(authProvider);
      final svc = AuthService()..setTokens(jwt: auth.jwtToken);
      await svc.setDeviceRole(deviceId, role);
      if (!mounted) return;
      _loadData();
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      _snack(
        l10n.getP('deviceSettingFailed', {'error': e.toString()}),
        error: true,
      );
    }
  }

  Future<void> _savePolicy(SyncPolicy policy) async {
    await ref.read(syncProvider.notifier).savePolicy(policy);
    if (!mounted) return;
    final error = ref.read(syncProvider).error;
    if (error != null) {
      _snack(error, error: true);
    }
  }

  Future<void> _runCurrentScope() async {
    final preview = await ref.read(syncProvider.notifier).previewCurrentScope();
    if (preview != null && mounted) await _confirmAndRun(preview);
  }

  Future<void> _runOneShot() async {
    final agents = ref
        .read(agentProvider)
        .agents
        .where((agent) => !agent.isGroupOnly)
        .toList();
    final selected = <String>{};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).get('oneShotSync')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: agents
                  .map(
                    (agent) => CheckboxListTile(
                      value: selected.contains(agent.id),
                      title: Text(agent.name),
                      onChanged: (checked) {
                        setDialogState(() {
                          checked == true
                              ? selected.add(agent.id)
                              : selected.remove(agent.id);
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).get('cancel')),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, Set.of(selected)),
              child: Text(AppLocalizations.of(context).get('previewSync')),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final preview = await ref
        .read(syncProvider.notifier)
        .previewOneShot(result);
    if (preview != null && mounted) await _confirmAndRun(preview);
  }

  Future<void> _deleteCloudCopy(SyncPolicy policy) async {
    final l10n = AppLocalizations.of(context);
    final agents = ref
        .read(agentProvider)
        .agents
        .where((agent) => !agent.isGroupOnly)
        .toList();
    var mode = policy.scopeMode;
    final selected = <String>{...policy.selectedAgentIds};
    final scope = await showDialog<SyncScope>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.get('deleteCloudCopyTitle')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.get('deleteCloudCopyConfirm')),
                  const SizedBox(height: 12),
                  RadioGroup<SyncScopeMode>(
                    groupValue: mode,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => mode = value);
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<SyncScopeMode>(
                          contentPadding: EdgeInsets.zero,
                          value: SyncScopeMode.all,
                          title: Text(l10n.get('deleteCloudCopyAll')),
                        ),
                        RadioListTile<SyncScopeMode>(
                          contentPadding: EdgeInsets.zero,
                          value: SyncScopeMode.selected,
                          title: Text(l10n.get('deleteCloudCopySelected')),
                        ),
                      ],
                    ),
                  ),
                  if (mode == SyncScopeMode.selected)
                    ...agents.map(
                      (agent) => CheckboxListTile(
                        contentPadding: const EdgeInsets.only(left: 24),
                        dense: true,
                        value: selected.contains(agent.id),
                        title: Text(agent.name),
                        onChanged: (checked) => setDialogState(() {
                          checked == true
                              ? selected.add(agent.id)
                              : selected.remove(agent.id);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: mode == SyncScopeMode.selected && selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      dialogContext,
                      mode == SyncScopeMode.all
                          ? SyncScope.all()
                          : SyncScope.oneShot(selected),
                    ),
              child: Text(l10n.get('delete')),
            ),
          ],
        ),
      ),
    );
    if (scope == null || !mounted) return;
    final result = await ref.read(syncProvider.notifier).deleteCloudCopy(scope);
    if (!mounted || result == null) return;
    _snack(
      result.success
          ? l10n.getP('deleteCloudCopyDone', {
              'count': '${result.itemsProcessed}',
            })
          : (result.error ?? l10n.get('deleteCloudCopyFailed')),
      error: !result.success,
    );
  }

  Future<void> _confirmAndRun(SyncPreview preview) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.get('syncPreviewTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.getP('syncPreviewUpload', {
                'count': '${preview.uploadCount}',
              }),
            ),
            Text(
              l10n.getP('syncPreviewDownload', {
                'count': '${preview.downloadCount}',
              }),
            ),
            Text(
              l10n.getP('syncPreviewOverwrite', {
                'local': '${preview.overwriteLocalCount}',
                'cloud': '${preview.overwriteCloudCount}',
              }),
            ),
            Text(
              l10n.getP('syncPreviewDelete', {
                'count': '${preview.deleteCount}',
              }),
            ),
            if (preview.conflictCount > 0)
              Text(
                l10n.getP('syncPreviewConflict', {
                  'count': '${preview.conflictCount}',
                }),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.get('startSync')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      ref.read(syncProvider.notifier).clearPreview();
      return;
    }
    final result = await ref.read(syncProvider.notifier).runPreparedPreview();
    if (!mounted || result == null) return;
    if (result.success) {
      _snack(l10n.getP('syncCompleted', {'count': '${result.itemsProcessed}'}));
      await _loadData();
    } else {
      _snack(result.error ?? l10n.get('syncFailed'), error: true);
    }
  }

  Future<void> _deleteDevice(String deviceId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('deleteDevice')),
        content: Text(l10n.get('deleteDeviceConfirm')),
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
    if (confirmed != true) return;
    try {
      final auth = ref.read(authProvider);
      final svc = AuthService()..setTokens(jwt: auth.jwtToken);
      await svc.deleteDevice(deviceId);
      if (!mounted) return;
      _loadData();
    } catch (e) {
      _snack(
        l10n.getP('deviceDeleteFailed', {'error': e.toString()}),
        error: true,
      );
    }
  }

  Future<void> _editName(String deviceId, String currentName) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: currentName);
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.get('editDeviceName')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.get('deviceNameHint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      );
      if (newName == null || newName.isEmpty || newName == currentName) return;
      final auth = ref.read(authProvider);
      final svc = AuthService()..setTokens(jwt: auth.jwtToken);
      await svc.updateDeviceName(deviceId, newName);
      if (!mounted) return;
      _loadData();
    } catch (e) {
      _snack(
        l10n.getP('deviceUpdateFailed', {'error': e.toString()}),
        error: true,
      );
    } finally {
      ctrl.dispose();
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final sync = ref.watch(syncProvider);
    final agents = ref
        .watch(agentProvider)
        .agents
        .where((agent) => !agent.isGroupOnly)
        .toList();
    final isSyncing =
        sync.isRunning || sync.isUploading || sync.isDownloading;
    // 驱动状态图标旋转动画：同步中转圈，结束后停止
    if (isSyncing) {
      if (!_spinController.isAnimating) _spinController.repeat();
    } else if (_spinController.isAnimating) {
      _spinController.stop();
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('multiDeviceSync'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 30,
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.get('syncLoadErrorHint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.get('retry')),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSyncStatusCard(sync, scheme, l10n),
                  const SizedBox(height: 16),
                  _buildSyncSettingsCard(sync, agents, scheme, l10n),
                  const SizedBox(height: 16),
                  // 设备列表
                  Text(
                    l10n.getP('loggedInDevicesCount', {
                      'count': _devices.length.toString(),
                    }),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._devices.map((d) => _buildDeviceCard(d, scheme, l10n)),
                ],
              ),
            ),
    );
  }

  /// 把上次同步时间转成人性化相对文案（如"3 分钟前"），过旧回退完整日期
  String _relativeTimeText(AppLocalizations l10n, DateTime? lastSync) {
    final rel = syncRelativeTime(lastSync, DateTime.now());
    switch (rel.kind) {
      case SyncFreshness.never:
        return l10n.get('syncNever');
      case SyncFreshness.justNow:
        return l10n.get('syncTimeJustNow');
      case SyncFreshness.minutesAgo:
        return l10n.getP('syncTimeMinutesAgo', {'count': '${rel.count}'});
      case SyncFreshness.hoursAgo:
        return l10n.getP('syncTimeHoursAgo', {'count': '${rel.count}'});
      case SyncFreshness.daysAgo:
        return l10n.getP('syncTimeDaysAgo', {'count': '${rel.count}'});
      case SyncFreshness.stale:
        return DateFormat('yyyy-MM-dd HH:mm').format(lastSync!);
    }
  }

  // ── 顶部同步状态卡：大图标 + 人性化状态文案 + 主操作按钮 ──
  Widget _buildSyncStatusCard(
    SyncState sync,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final busy = sync.isRunning || sync.isUploading || sync.isDownloading;
    final status = resolveSyncStatus(
      canUseSync: sync.canUseSync,
      isBusy: busy,
      hasCloudUpdate: sync.hasCloudUpdate,
      lastSyncTime: sync.lastSyncTime,
    );
    final relText = _relativeTimeText(l10n, sync.lastSyncTime);

    final IconData icon;
    final Color iconBg;
    final Color iconFg;
    final String headline;
    final String? subline;
    switch (status) {
      case SyncStatusKind.unavailable:
        icon = Icons.cloud_off_outlined;
        iconBg = scheme.surfaceContainerHighest;
        iconFg = scheme.onSurfaceVariant;
        headline = l10n.get('syncStatusUnavailable');
        subline = l10n.get('syncStatusSubscribeGuide');
      case SyncStatusKind.syncing:
        icon = Icons.sync_rounded;
        iconBg = scheme.primaryContainer;
        iconFg = scheme.onPrimaryContainer;
        headline = l10n.get('syncStatusSyncing');
        subline = null;
      case SyncStatusKind.cloudUpdate:
        icon = Icons.cloud_download_outlined;
        iconBg = scheme.tertiaryContainer;
        iconFg = scheme.onTertiaryContainer;
        headline = l10n.getP('syncStatusCloudUpdate', {'time': relText});
        subline = null;
      case SyncStatusKind.synced:
        icon = Icons.cloud_done_outlined;
        iconBg = scheme.primaryContainer;
        iconFg = scheme.onPrimaryContainer;
        headline = l10n.getP('syncStatusOk', {'time': relText});
        subline = null;
      case SyncStatusKind.never:
        icon = Icons.cloud_upload_outlined;
        iconBg = scheme.surfaceContainerHighest;
        iconFg = scheme.onSurfaceVariant;
        headline = l10n.get('syncStatusNever');
        subline = null;
    }

    final canSyncNow =
        status != SyncStatusKind.unavailable &&
        !busy &&
        sync.policy != null &&
        !sync.isLoadingPolicy;

    final statusIcon = Icon(icon, size: 26, color: iconFg);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.tertiaryContainer.withValues(alpha: 0.30),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: status == SyncStatusKind.syncing
                      ? RotationTransition(
                          turns: _spinController,
                          child: statusIcon,
                        )
                      : statusIcon,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.get('syncStatusCardTitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headline,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subline != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subline,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: status == SyncStatusKind.unavailable
                  ? FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionCenterScreen(),
                        ),
                      ),
                      icon: const Icon(
                        Icons.workspace_premium_outlined,
                        size: 18,
                      ),
                      label: Text(l10n.get('goSubscribe')),
                    )
                  : FilledButton.icon(
                      onPressed: canSyncNow ? _runCurrentScope : null,
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: Text(l10n.get('syncNow')),
                    ),
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSettingsCard(
    SyncState sync,
    List<Agent> agents,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final policy = sync.policy;
    final busy = sync.isLoadingPolicy || sync.isRunning;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: policy == null
            ? sync.isLoadingPolicy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      key: const ValueKey('syncPolicyError'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 30,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          sync.error ?? l10n.get('syncFailed'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('syncPolicyRetry'),
                          onPressed: () =>
                              ref.read(syncProvider.notifier).loadPolicy(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.get('retry')),
                        ),
                      ],
                    )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('syncScopeTitle'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<SyncScopeMode>(
                      segments: [
                        ButtonSegment(
                          value: SyncScopeMode.all,
                          label: Text(l10n.get('syncAllAgents')),
                          icon: const Icon(Icons.all_inclusive),
                        ),
                        ButtonSegment(
                          value: SyncScopeMode.selected,
                          label: Text(l10n.get('syncSelectedAgents')),
                          icon: const Icon(Icons.checklist),
                        ),
                      ],
                      selected: {policy.scopeMode},
                      onSelectionChanged: busy
                          ? null
                          : (selection) {
                              _savePolicy(
                                policy.copyWith(scopeMode: selection.first),
                              );
                            },
                    ),
                  ),
                  if (policy.scopeMode == SyncScopeMode.selected) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.getP('syncSelectedCount', {
                        'count': '${policy.selectedAgentIds.length}',
                      }),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (agents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(l10n.get('syncNoAgents')),
                      )
                    else
                      ...agents.map(
                        (agent) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: policy.selectedAgentIds.contains(agent.id),
                          title: Text(agent.name),
                          onChanged: busy
                              ? null
                              : (checked) {
                                  final selected = Set<String>.from(
                                    policy.selectedAgentIds,
                                  );
                                  checked == true
                                      ? selected.add(agent.id)
                                      : selected.remove(agent.id);
                                  _savePolicy(
                                    policy.copyWith(selectedAgentIds: selected),
                                  );
                                },
                        ),
                      ),
                    Text(
                      policy.selectedAgentIds.isEmpty
                          ? l10n.get('syncNoSelectedAgents')
                          : l10n.get('syncNewAgentExcludedHint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.get('continuousSync')),
                    subtitle: Text(l10n.get('continuousSyncDesc')),
                    value: policy.realtimeEnabled,
                    onChanged: busy
                        ? null
                        : (enabled) => _savePolicy(
                            policy.copyWith(realtimeEnabled: enabled),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : _runCurrentScope,
                        icon: const Icon(Icons.sync),
                        label: Text(l10n.get('syncCurrentScopeNow')),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _runOneShot,
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: Text(l10n.get('oneShotSync')),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => _deleteCloudCopy(policy),
                        icon: const Icon(Icons.cloud_off_outlined),
                        label: Text(l10n.get('deleteCloudCopy')),
                      ),
                    ],
                  ),
                  if (sync.isRunning) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildDeviceCard(
    Map<String, dynamic> d,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final deviceId = d['device_id'] as String? ?? '';
    final deviceName = d['device_name'] as String? ?? l10n.get('unnamedDevice');
    final platform = d['platform'] as String? ?? '';
    final browser = d['browser'] as String? ?? '';
    final role = d['role'] as String? ?? 'slave';
    final isMaster = role == 'master';
    final isCurrent = deviceId == _currentDeviceId;
    final lastActive = d['last_active_at'] as String? ?? '';
    final lastSync = d['last_sync_at'] as String? ?? '';
    String lastActiveStr = '';
    if (lastActive.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastActive);
        lastActiveStr = DateFormat('MM-dd HH:mm').format(dt);
      } catch (_) {}
    }
    var lastSyncStr = '';
    if (lastSync.isNotEmpty) {
      try {
        lastSyncStr = DateFormat(
          'MM-dd HH:mm',
        ).format(DateTime.parse(lastSync));
      } catch (_) {}
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: isCurrent
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.3),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMaster
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isMaster ? Icons.phone_iphone : Icons.devices,
                color: isMaster
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        deviceName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            l10n.get('currentDevice'),
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      platform,
                      browser,
                      lastActiveStr,
                    ].where((value) => value.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (lastSyncStr.isNotEmpty)
                    Text(
                      '${l10n.get('syncLastTime')} $lastSyncStr',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // 角色
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isMaster
                    ? scheme.tertiaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isMaster ? l10n.get('masterDevice') : l10n.get('slaveDevice'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMaster
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (v) {
                if (v == 'set_master') {
                  _setRole(deviceId, 'master');
                } else if (v == 'set_slave') {
                  _setRole(deviceId, 'slave');
                } else if (v == 'edit_name') {
                  _editName(deviceId, deviceName);
                } else if (v == 'delete') {
                  _deleteDevice(deviceId);
                }
              },
              itemBuilder: (_) => [
                if (!isMaster)
                  PopupMenuItem(
                    value: 'set_master',
                    child: Row(
                      children: [
                        const Icon(Icons.star, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.get('setAsMaster')),
                      ],
                    ),
                  ),
                if (isMaster && !isCurrent)
                  PopupMenuItem(
                    value: 'set_slave',
                    child: Row(
                      children: [
                        const Icon(Icons.star_border, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.get('setAsSlave')),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'edit_name',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.get('editName')),
                    ],
                  ),
                ),
                if (!isCurrent)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: scheme.error),
                        const SizedBox(width: 8),
                        Text(
                          l10n.get('delete'),
                          style: TextStyle(color: scheme.error),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
