import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/auth_service.dart';
import '../services/model_list_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../utils/avatar_cropper.dart';
import '../widgets/echo_profile_motion.dart';
import '../widgets/echo_visual_surface.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/user_avatar.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'subscription_center_screen.dart';
import 'sync_devices_screen.dart';

/// 账户管理页（底部第 5 Tab）
/// 未登录：用户卡占位 + 右侧"登录"按钮；已登录：用户信息 + 余额 + 订阅 + 同步
/// 底部固定顺序：模型选择、意见反馈、设置入口、退出登录（仅登录时）
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  /// 订阅状态是否在刷新中（用于订阅/同步区域骨架占位）
  bool _subRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 并行加载账户数据：资料(含头像)、余额、订阅三路同时发起，
  /// 各自独立 try/catch，任一失败不影响其他；总耗时≈最慢一路。
  /// [forceRefresh] 为 true 时（下拉刷新）订阅不节流、强制全量刷新。
  Future<void> _loadData({bool forceRefresh = false}) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    final notifier = ref.read(authProvider.notifier);
    if (mounted) setState(() => _subRefreshing = true);
    await Future.wait([
      _guarded(notifier.refreshUserProfile),
      _guarded(() => _refreshBalance(auth)),
      _guarded(
        forceRefresh
            ? notifier.refreshSubscription
            : notifier.maybeRefreshSubscription,
      ),
    ]);
    if (mounted) setState(() => _subRefreshing = false);
  }

  /// 兜底保护：单路失败静默吞掉，不拖垮其他并行任务
  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  /// 余额刷新：401 时上报触发 token 刷新，其余失败静默
  Future<void> _refreshBalance(AuthState auth) async {
    final svc = AuthService()..setTokens(jwt: auth.jwtToken);
    try {
      final balanceData = await svc.getBalance();
      final newBalance = (balanceData['balance'] as num?)?.toDouble();
      if (newBalance != null) {
        ref
            .read(authProvider.notifier)
            .updateLocalBalance(
              newBalance,
              dailyQuotaUsed: (balanceData['daily_quota_used'] as num?)
                  ?.toDouble(),
              dailyQuotaLeft: (balanceData['daily_quota_left'] as num?)
                  ?.toDouble(),
              subscriptionQuotaLeft:
                  (balanceData['subscription_quota_left'] as num?)?.toDouble(),
            );
      }
    } on AuthException catch (e) {
      if (e.isUnauthorized) {
        ref.read(authProvider.notifier).reportUnauthorized();
      }
    } catch (_) {}
  }

  /// 跳转独立登录页，登录成功后返回账户页（已登录状态自动刷新）
  Future<void> _goLogin() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);
    final user = auth.user;

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (prev != null && !prev.isLoggedIn && next.isLoggedIn) {
        _loadData();
      }
    });

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(l10n.get('account'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            // 下拉刷新：强制全量并行刷新（订阅不节流）
            onRefresh: () => _loadData(forceRefresh: true),
            child: ListView(
              // 底部预留悬浮导航栏高度（HomeScreen extendBody），避免内容被挡住拉不到底
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
              children: [
                // ─── 用户信息卡片（登录/未登录均显示） ───
                _buildProfileCard(user, scheme, l10n, auth.isLoggedIn),
                const SizedBox(height: 16),

                // ─── 未登录引导块（仅未登录时显示） ───
                if (!auth.isLoggedIn) ...[
                  _buildLoginGuide(scheme, l10n),
                  const SizedBox(height: 16),
                ],

                // ─── 余额卡片（仅登录后显示） ───
                if (auth.isLoggedIn && user != null) ...[
                  _buildBalanceCard(user, scheme, l10n),
                  const SizedBox(height: 16),
                  // ─── 订阅中心入口 ───
                  _buildSubscriptionCenterEntry(scheme),
                  const SizedBox(height: 12),
                  // ─── 多端同步引导 ───
                  _buildSyncEntry(scheme, l10n),
                  const SizedBox(height: 16),
                ],

                Card(
                  child: Column(
                    children: [
                      _buildModelEntry(l10n),
                      const Divider(indent: 64),
                      _accountActionTile(
                        icon: Icons.feedback_outlined,
                        title: l10n.get('feedback'),
                        onTap: () => FeedbackDialog.show(context),
                      ),
                      const Divider(indent: 64),
                      _accountActionTile(
                        icon: Icons.settings_outlined,
                        title: l10n.get('settings'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── 退出登录（仅登录时显示） ───
                if (auth.isLoggedIn) ...[
                  Card(
                    child: _accountActionTile(
                      icon: Icons.logout_rounded,
                      title: l10n.get('logout'),
                      onTap: _logout,
                      destructive: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 模型选择入口（原设置页"模型与模式"分区迁来） ──
  Widget _buildModelEntry(AppLocalizations l10n) {
    final s = ref.watch(settingsProvider);
    final models = ref.watch(modelListProvider).models;
    var currentName = s.selectedModel;
    for (final m in models) {
      if (m.id == s.selectedModel) {
        currentName = m.name;
        break;
      }
    }
    return _accountActionTile(
      icon: Icons.smart_toy_outlined,
      title: l10n.get('selectModel'),
      subtitle: '$currentName · ${l10n.get('chatModelOnly')}',
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _ModelSelectionSheet(),
      ),
    );
  }

  Widget _accountActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.brLg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: destructive
                    ? scheme.errorContainer.withValues(alpha: 0.62)
                    : scheme.primaryContainer.withValues(alpha: 0.54),
                borderRadius: AppTheme.brMd,
              ),
              child: Icon(
                icon,
                size: 20,
                color: destructive
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: foreground),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: destructive ? scheme.error : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ── 用户信息 ──
  Widget _buildProfileCard(
    UserProfile? user,
    ColorScheme scheme,
    AppLocalizations l10n,
    bool loggedIn,
  ) {
    return Container(
      key: const ValueKey('accountProfileHero'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.78),
            scheme.tertiaryContainer.withValues(alpha: 0.44),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.brXl,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.44),
        ),
        boxShadow: AppTheme.primaryShadowSm(scheme),
      ),
      child: ClipRRect(
        borderRadius: AppTheme.brXl,
        child: Stack(
          children: [
            // 右上角轨道环氛围装饰（低透明度，裁剪防溢出圆角）
            Positioned(
              top: -26,
              right: -26,
              child: IgnorePointer(
                child: SizedBox(
                  width: 108,
                  height: 108,
                  child: FittedBox(
                    child: EchoOrbitRings(
                      color: scheme.primary.withValues(alpha: 0.30),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
          children: [
            // 头像（外圈 primary 低透明度描边光环）
            GestureDetector(
              onTap: loggedIn ? _editAvatar : null,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.30),
                    width: 2,
                  ),
                ),
                child: UserAvatar(
                avatar: loggedIn ? user?.avatar : null,
                radius: 36,
                backgroundColor: scheme.surface.withValues(alpha: 0.76),
                fallback: Icon(
                  Icons.person_outline,
                  size: 34,
                  color: scheme.primary,
                ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 名称 + 邮箱（未登录时不显示名称文本）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loggedIn && user != null)
                    GestureDetector(
                      onTap: _editNickname,
                      child: Row(
                        children: [
                          Text(
                            user.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  if (!loggedIn)
                    Text(
                      l10n.get('account'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  if (loggedIn && user != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 右侧登录按钮（未登录时）
            if (!loggedIn)
              FilledButton.icon(
                onPressed: _goLogin,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(l10n.get('login')),
              ),
          ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 未登录引导块 ──
  Widget _buildLoginGuide(ColorScheme scheme, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.60),
            scheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.brXl,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.44),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const EchoIconBadge(
            icon: Icons.cloud_done_outlined,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('loginGuideTitle'),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.get('loginGuideSubtitle'),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _goLogin, child: Text(l10n.get('login'))),
        ],
      ),
    );
  }

  // ── 余额 ──
  Widget _buildBalanceCard(
    UserProfile user,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: AppTheme.brMd,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: scheme.onPrimary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('availableBalance'),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '¥${user.totalAvailable.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildQuotaMetrics(user, scheme, l10n),
          ],
        ),
      ),
    );
  }

  /// 配额用量条：「今日已用」标签 + 右侧「¥已用 / ¥总额」数值，
  /// 下方一条圆角进度条（已用 / 当日总可支配）。
  Widget _buildQuotaMetrics(
    UserProfile user,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final used = user.dailyQuotaUsed;
    // 当日总可支配 = 今日已用 + 今日配额剩余 + 订阅配额剩余
    final total = used + user.dailyQuotaLeft + user.subscriptionQuotaLeft;
    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.get('todayUsed'),
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '¥${user.formatDailyUsed} / ¥${total.toStringAsFixed(2)}',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
      ],
    );
  }

  /// 灰色圆角骨架条：数据尚未就绪时的占位，避免空白等待或展示误导性文案
  Widget _skeletonBar(
    ColorScheme scheme, {
    double width = 160,
    double height = 11,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  // ── 订阅中心入口 ──
  Widget _buildSubscriptionCenterEntry(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final sub = auth.subscription;
    final title = sub?['plan_name'] as String?;
    final syncText = auth.canUseSync
        ? l10n.get('syncIncluded')
        : l10n.get('syncNotIncluded');
    // 无缓存订阅且正在刷新：展示骨架而非可能错误的"未订阅"文案
    final showSkeleton = sub == null && _subRefreshing;
    final subtitle = sub == null
        ? l10n.get('subscriptionCenterSubtitle')
        : '${title == null || title.isEmpty ? l10n.get('subscribed') : title} · ${_formatSubscriptionDays(l10n, auth.subRemainingDays)} · $syncText';
    return _featureCard(
      icon: Icons.workspace_premium,
      title: l10n.get('subscriptionCenter'),
      emphasized: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionCenterScreen()),
      ),
      subtitle: showSkeleton
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _skeletonBar(scheme, width: 200),
            )
          : Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
              ),
            ),
    );
  }

  /// 统一的功能入口卡：EchoIconBadge + 标题 + 副标题 + 状态徽标 + chevron。
  /// [emphasized] 为 true 时使用 primaryContainer 强调底（订阅中心），
  /// 否则使用普通 Card 底色（多端同步）。
  Widget _featureCard({
    required IconData icon,
    required String title,
    Widget? subtitle,
    List<Widget> badges = const [],
    VoidCallback? onTap,
    bool emphasized = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = emphasized ? scheme.onPrimaryContainer : scheme.onSurface;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: AppTheme.brLg,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppTheme.brLg,
            color: emphasized ? scheme.primaryContainer : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              EchoIconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ?subtitle,
                  ],
                ),
              ),
              if (badges.isNotEmpty) ...[...badges, const SizedBox(width: 6)],
              Icon(
                Icons.chevron_right,
                color: emphasized
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSubscriptionDays(AppLocalizations l10n, int? days) {
    if (days == null) return l10n.get('remainingDays');
    if (days < 0) return l10n.get('expiredLabel');
    if (days == 0) return l10n.get('expiresTodayLabel');
    return '$days ${l10n.get('daysUnit')}';
  }

  // ── 多端同步引导 ──
  Widget _buildSyncEntry(ColorScheme scheme, AppLocalizations l10n) {
    final auth = ref.watch(authProvider);
    final sync = ref.watch(syncProvider);
    final canUse = sync.canUseSync;
    final isBusy = sync.isUploading || sync.isDownloading;
    final lastTime = sync.lastSyncTime;
    final blockedText = auth.hasActiveSubscription
        ? l10n.get('syncNotAvailableForPlan')
        : l10n.get('syncNeedSubscription');
    final subtitle = canUse
        ? (lastTime != null
              ? '${l10n.get('syncLastTime')}: ${DateFormat('yyyy-MM-dd HH:mm').format(lastTime)}'
              : l10n.get('syncNever'))
        : blockedText;
    // 订阅刷新中且本地无缓存：同步权益尚未确定，展示骨架而非"需订阅"误导文案
    final showSkeleton =
        !canUse && _subRefreshing && auth.subscription == null;

    return _featureCard(
      icon: Icons.cloud_sync,
      title: l10n.get('multiDeviceSync'),
      onTap: isBusy ? null : () => _showSyncConfirmDialog(scheme, l10n, canUse),
      subtitle: showSkeleton
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _skeletonBar(scheme, width: 150),
            )
          : Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
      badges: [
        if (!canUse && !showSkeleton)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.get('subscribeOnly'),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else if (sync.hasCloudUpdate)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.tertiary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.get('syncCloudUpdate'),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ── 多端同步确认弹窗 ──
  Future<void> _showSyncConfirmDialog(
    ColorScheme scheme,
    AppLocalizations l10n,
    bool canUse,
  ) async {
    if (!canUse) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.lock_outline, color: scheme.error, size: 32),
          title: Text(l10n.get('multiDeviceSync')),
          content: Text(
            ref.read(authProvider).hasActiveSubscription
                ? l10n.get('syncNotAvailableForPlan')
                : l10n.get('syncNeedSubscription'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('confirm')),
            ),
          ],
        ),
      );
      return;
    }
    // 同一用户同一设备已确认过，下次直接进入设备管理页，不再重复询问
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(authProvider).user?.id.toString() ?? '';
    if (prefs.getBool('sync_confirmed_$userId') == true) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SyncDevicesScreen()),
      );
      return;
    }
    if (!mounted) return;
    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cloud_sync, color: scheme.primary, size: 32),
        title: Text(l10n.get('multiDeviceSync')),
        content: Text(l10n.get('syncConfirmContent')),
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
    if (agree != true) return;
    if (!mounted) return;
    // 记录已确认，同一用户同一设备下次不再询问
    await prefs.setBool('sync_confirmed_$userId', true);
    // 首次同意时先做一次完整同步（上传 + 下载）
    try {
      await ref.read(syncProvider.notifier).uploadAll();
      if (!mounted) return;
      await ref.read(syncProvider.notifier).downloadAll();
    } catch (e) {
      debugPrint('sync error: $e');
    }
    if (!mounted) return;
    // 跳转到设备管理页
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SyncDevicesScreen()),
    );
  }

  // ── 操作 ──
  Future<void> _editNickname() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(
      text: ref.read(authProvider).user?.nickname ?? '',
    );
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.get('editNickname')),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: l10n.get('nickname'),
              border: const OutlineInputBorder(),
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
      if (result != null && result.isNotEmpty) {
        await ref.read(authProvider.notifier).updateProfile(nickname: result);
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _editAvatar() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.get('camera')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.get('gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (img == null) return;

      // 1:1 交互裁剪（全平台一致的底部按钮裁剪页）；取消则放弃本次选择
      if (!mounted) return;
      final cropped = await AvatarCropper.cropAvatar(
        context,
        img.path,
        title: l10n.get('cropAvatar'),
      );
      if (cropped == null) return;

      final auth = ref.read(authProvider);
      final svc = AuthService()..setTokens(jwt: auth.jwtToken);
      await svc.uploadAvatar(cropped);

      // 重新拉取用户资料以刷新头像显示
      await ref.read(authProvider.notifier).refreshUserProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('avatarUploadSuccess'))),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('avatarUploadFailed')}: $e')),
        );
      }
    }
  }

  void _logout() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirmLogout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: Text(l10n.get('logout')),
          ),
        ],
      ),
    );
  }
}

/// 模型选择底部弹窗：打开时静默刷新一次，顶部"刷新"按钮可手动重拉，
/// 失败 toast 提示并继续使用缓存列表。
class _ModelSelectionSheet extends ConsumerStatefulWidget {
  const _ModelSelectionSheet();

  @override
  ConsumerState<_ModelSelectionSheet> createState() =>
      _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends ConsumerState<_ModelSelectionSheet> {
  @override
  void initState() {
    super.initState();
    // 打开时静默刷新（失败不打扰用户，沿用缓存）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelListProvider.notifier).refresh();
    });
  }

  Future<void> _manualRefresh() async {
    final l10n = AppLocalizations.of(context);
    final error = await ref.read(modelListProvider.notifier).refresh();
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? l10n.get('modelRefreshSuccess')
              : l10n.get('modelFetchFailed'),
        ),
        backgroundColor: error == null
            ? scheme.primaryContainer
            : scheme.errorContainer,
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final listState = ref.watch(modelListProvider);
    final selected = ref.watch(settingsProvider).selectedModel;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.get('selectModel'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (listState.refreshing)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: l10n.get('refresh'),
                    onPressed: _manualRefresh,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.get('chatModelOnly'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: listState.models.length,
              itemBuilder: (context, index) {
                final model = listState.models[index];
                final isSelected = model.id == selected;
                return ListTile(
                  title: Text(
                    model.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    model.id,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () {
                    ref
                        .read(settingsProvider.notifier)
                        .setSelectedModel(model.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
