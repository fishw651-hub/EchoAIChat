import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/app_event_provider.dart';
import '../services/auth_service.dart';
import '../services/quota_service.dart';
import '../services/subscription_plan_cache.dart';
import '../widgets/payment_webview.dart';

/// 独立订阅中心页：当前状态 + 配额展示 + 订阅计划 + 功能对比表
class SubscriptionCenterScreen extends ConsumerStatefulWidget {
  const SubscriptionCenterScreen({super.key});

  @override
  ConsumerState<SubscriptionCenterScreen> createState() =>
      _SubscriptionCenterScreenState();
}

class _SubscriptionCenterScreenState
    extends ConsumerState<SubscriptionCenterScreen> {
  List<dynamic>? _plans;
  List<dynamic>? _mySubs;
  QuotaSnapshot? _quota;
  bool _loading = true;
  String? _error;

  final GlobalKey _plansKey = GlobalKey();
  int? _subscribingPlanId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAll({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      final svc = AuthService()..setTokens(jwt: auth.jwtToken);
      final results = await Future.wait([
        SubscriptionPlanCache.instance.get(
          svc.getSubscriptionPlans,
          force: force,
        ),
        _getMySubscriptionsWithCache(svc, force: force),
        QuotaService.instance.getUsage(
          cacheMaxAge: force ? null : const Duration(minutes: 1),
        ),
      ]);
      if (mounted) {
        setState(() {
          _plans = results[0] as List<dynamic>;
          _mySubs = results[1] as List<dynamic>;
          _quota = results[2] as QuotaSnapshot;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 订阅接口暂时不可用时，使用认证层刚刚成功缓存的订阅快照。
  /// 缓存有账号归属和有限有效期，过期后宁可显示错误，也不继续放行同步权益。
  Future<List<dynamic>> _getMySubscriptionsWithCache(
    AuthService svc, {
    required bool force,
  }) async {
    if (!force) {
      final cached = _readCachedSubscriptions(ref.read(authProvider));
      if (cached != null) return cached;
    }

    late final List<dynamic> subscriptions;
    try {
      subscriptions = await svc.getMySubscription();
    } catch (_) {
      final cached = _readCachedSubscriptions(ref.read(authProvider));
      if (cached != null) return cached;
      rethrow;
    }
    // 页面请求成功后同步更新认证层缓存；缓存写入失败不应遮蔽服务端结果。
    try {
      await ref
          .read(authProvider.notifier)
          .applySubscriptionSnapshot(subscriptions);
    } catch (_) {}
    return subscriptions;
  }

  List<dynamic>? _readCachedSubscriptions(AuthState auth) {
    final maxAge = auth.subscription == null
        ? const Duration(minutes: 1)
        : AuthState.subscriptionCacheTtl;
    if (!auth.isSubscriptionCacheFresh(maxAge)) return null;
    final subscription = auth.subscription;
    if (subscription == null || !auth.hasActiveSubscription) {
      return <dynamic>[];
    }
    return <dynamic>[subscription];
  }

  /// 滚动到订阅计划区域
  void _scrollToPlans() {
    final ctx = _plansKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        alignment: 0.0,
      );
    }
  }

  /// 直接订阅指定计划（调用付款，不再打开充值弹窗）
  Future<void> _subscribePlan(Map<String, dynamic> plan) async {
    if (_subscribingPlanId != null) return;
    final planId = (plan['id'] as num?)?.toInt();
    if (planId == null) return;
    setState(() => _subscribingPlanId = planId);
    final l10n = AppLocalizations.of(context);
    try {
      final svc = AuthService()
        ..setTokens(jwt: ref.read(authProvider).jwtToken);
      final result = await svc.subscribe(planId, paymentType: 'wxpay');
      final payUrl = result['pay_url'] as String?;
      final orderNo = result['order_no'] as String?;
      if (payUrl != null && payUrl.isNotEmpty && mounted) {
        final paid = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentWebView(
              url: payUrl,
              jwtToken: ref.read(authProvider).jwtToken,
            ),
          ),
        );
        if (paid == true && orderNo != null && mounted) {
          try {
            final status = await svc.getOrderStatus(orderNo);
            if (status['status'] == 'paid' && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.get('subscribeSuccess'))),
              );
              await ref.read(authProvider.notifier).refreshUserProfile();
              await ref.read(authProvider.notifier).refreshSubscription();
              if (mounted) await _loadAll();
            }
          } catch (_) {}
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('subscribeSuccess'))));
        await ref.read(authProvider.notifier).refreshUserProfile();
        await ref.read(authProvider.notifier).refreshSubscription();
        if (mounted) await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subscribingPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appEventProvider.select((state) => state.quotaRevision), (
      previous,
      next,
    ) {
      if (previous != next && mounted) _loadAll(force: true);
    });
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('subscriptionCenter'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(scheme, l10n)
          : RefreshIndicator(
              onRefresh: () => _loadAll(force: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCurrentStatusCard(scheme, l10n),
                  const SizedBox(height: 16),
                  _buildQuotaCard(scheme, l10n),
                  const SizedBox(height: 16),
                  _buildPlansSection(scheme, l10n),
                  const SizedBox(height: 16),
                  _buildComparisonTable(scheme, l10n),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scrollToPlans,
        icon: const Icon(Icons.bolt),
        label: Text(l10n.get('subscribeNow')),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  错误状态
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
            Text(_error ?? l10n.get('loadFailed'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadAll, child: Text(l10n.get('retry'))),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  当前订阅状态
  // ═══════════════════════════════════════════

  Widget _buildCurrentStatusCard(ColorScheme scheme, AppLocalizations l10n) {
    final activeSubs = _activeSubscriptionMaps();
    final hasSub = activeSubs.isNotEmpty;
    final sub = hasSub ? activeSubs.first : null;
    final allowSync = sub != null && _allowsSync(sub);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasSub
                ? [scheme.primary, scheme.primaryContainer]
                : [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasSub ? Icons.verified : Icons.workspace_premium,
                  color: hasSub ? scheme.onPrimary : scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  hasSub ? l10n.get('subscribed') : l10n.get('notSubscribed'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: hasSub ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasSub) ...[
              Text(
                sub?['plan_name'] as String? ?? '',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onPrimary.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 6),
              _buildRemainingRow(
                scheme,
                label: l10n.get('remainingDays'),
                value: _formatRemainingDays(
                  l10n,
                  sub?['expires_at'] as String?,
                ),
                onPrimary: true,
              ),
              const SizedBox(height: 4),
              _buildRemainingRow(
                scheme,
                label: l10n.get('dailyChatQuota'),
                value:
                    '¥${(sub?['daily_quota'] as num?)?.toDouble().toStringAsFixed(1) ?? '0'}',
                onPrimary: true,
              ),
              const SizedBox(height: 4),
              _buildRemainingRow(
                scheme,
                label: l10n.get('multiDeviceSync'),
                value: allowSync
                    ? l10n.get('included')
                    : l10n.get('notIncluded'),
                onPrimary: true,
              ),
            ] else ...[
              Text(
                l10n.get('upgradeToUnlockMore'),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _scrollToPlans,
                icon: const Icon(Icons.bolt, size: 18),
                label: Text(l10n.get('subscribeNow')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _activeSubscriptionMaps() {
    return (_mySubs ?? [])
        .whereType<Map<String, dynamic>>()
        .where(
          (s) =>
              !s.containsKey('status') || (s['status'] as num?)?.toInt() == 1,
        )
        .toList();
  }

  bool _allowsSync(Map<String, dynamic> data) {
    final v = data['allow_sync'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final normalized = v.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Widget _buildRemainingRow(
    ColorScheme scheme, {
    required String label,
    required String value,
    bool onPrimary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onPrimary
                ? scheme.onPrimary.withValues(alpha: 0.85)
                : scheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onPrimary ? scheme.onPrimary : scheme.primary,
          ),
        ),
      ],
    );
  }

  String _formatRemainingDays(AppLocalizations l10n, String? expiresAt) {
    if (expiresAt == null || expiresAt.isEmpty) return '--';
    try {
      final end = DateTime.parse(expiresAt);
      final days = end.difference(DateTime.now()).inDays;
      if (days < 0) return l10n.get('expiredLabel');
      if (days == 0) return l10n.get('expiresTodayLabel');
      return '$days ${l10n.get('daysUnit')}';
    } catch (_) {
      return '--';
    }
  }

  // ═══════════════════════════════════════════
  //  配额使用卡片
  // ═══════════════════════════════════════════

  Widget _buildQuotaCard(ColorScheme scheme, AppLocalizations l10n) {
    final q = _quota;
    if (q == null) return const SizedBox.shrink();

    // 有活跃订阅时按订阅独立展示；无订阅时展示聚合视图
    final hasSubs = q.subscriptions.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.get('todayQuotaTitle'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasSubs) ...[
              // 无订阅：展示默认配额
              _buildQuotaBar(
                scheme,
                l10n,
                icon: Icons.image_search,
                label: l10n.get('chatHistoryRecognition'),
                usage: q.ocr,
              ),
              const SizedBox(height: 12),
              _buildQuotaBar(
                scheme,
                l10n,
                icon: Icons.psychology,
                label: l10n.get('realReplyConversation'),
                usage: q.realReply,
              ),
            ] else ...[
              // 有订阅：按订阅独立展示
              for (int i = 0; i < q.subscriptions.length; i++) ...[
                _buildSubscriptionQuotaSection(
                  scheme,
                  l10n,
                  q.subscriptions[i],
                ),
                if (i < q.subscriptions.length - 1)
                  Divider(
                    height: 24,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
              ],
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.refresh, size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  l10n.get('dailyResetHint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 单个订阅的配额区块：标题 + OCR 进度条 + 真实回复进度条
  Widget _buildSubscriptionQuotaSection(
    ColorScheme scheme,
    AppLocalizations l10n,
    SubscriptionQuota sub,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sub.planName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Text(
              _formatRemainingDays(l10n, sub.expiresAt),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildQuotaBar(
          scheme,
          l10n,
          icon: Icons.image_search,
          label: l10n.get('chatHistoryRecognition'),
          usage: sub.ocr,
        ),
        const SizedBox(height: 8),
        _buildQuotaBar(
          scheme,
          l10n,
          icon: Icons.psychology,
          label: l10n.get('realReplyConversation'),
          usage: sub.realReply,
        ),
      ],
    );
  }

  Widget _buildQuotaBar(
    ColorScheme scheme,
    AppLocalizations l10n, {
    required IconData icon,
    required String label,
    required QuotaUsage usage,
  }) {
    final percent = usage.unlimited || usage.quota == 0
        ? 0.0
        : (usage.used / usage.quota).clamp(0.0, 1.0);
    final remainingText = usage.unlimited
        ? l10n.get('unlimited')
        : '${l10n.get('remaining')} ${usage.remaining < 0 ? 0 : usage.remaining} / ${usage.quota}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text(
              usage.unlimited
                  ? '${l10n.get('used')} ${usage.used} · ${l10n.get('unlimited')}'
                  : '${l10n.get('used')} ${usage.used} / ${usage.quota}',
              style: TextStyle(
                fontSize: 12,
                color: percent >= 1.0 ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
            color: usage.unlimited
                ? scheme.tertiary
                : percent >= 1.0
                ? scheme.error
                : percent >= 0.8
                ? scheme.secondary
                : scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          remainingText,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  订阅计划列表
  // ═══════════════════════════════════════════

  Widget _buildPlansSection(ColorScheme scheme, AppLocalizations l10n) {
    final plans = (_plans ?? [])
        .map((p) => p as Map<String, dynamic>)
        .where((p) => (p['status'] as num?)?.toInt() == 1)
        .toList();

    if (plans.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              l10n.get('noPlansAvailable'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    // 按优先级排序：sort_order 升序（值小优先），缺失则用 price 降序作为次要排序
    plans.sort((a, b) {
      final sa = (a['sort_order'] as num?)?.toInt() ?? 999;
      final sb = (b['sort_order'] as num?)?.toInt() ?? 999;
      if (sa != sb) return sa.compareTo(sb);
      return ((b['price'] as num?)?.toDouble() ?? 0).compareTo(
        (a['price'] as num?)?.toDouble() ?? 0,
      );
    });
    final recommendedId = plans.isNotEmpty ? plans.first['id'] : null;

    // 前 4 个直接显示，剩余放入"更多订阅"
    const maxVisible = 4;
    final visiblePlans = plans.take(maxVisible).toList();
    final morePlans = plans.skip(maxVisible).toList();

    return Column(
      key: _plansKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.get('subscriptionPlans'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
        for (final plan in visiblePlans)
          _buildPlanCard(scheme, l10n, plan, recommendedId),
        if (morePlans.isNotEmpty)
          _buildMorePlansSection(scheme, l10n, morePlans, recommendedId),
      ],
    );
  }

  /// "更多订阅"折叠区域：收纳优先级较低的计划
  Widget _buildMorePlansSection(
    ColorScheme scheme,
    AppLocalizations l10n,
    List<Map<String, dynamic>> morePlans,
    dynamic recommendedId,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.unfold_more, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              l10n.get('moreSubscriptions'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${morePlans.length}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final plan in morePlans)
            _buildPlanCard(scheme, l10n, plan, recommendedId, compact: true),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    ColorScheme scheme,
    AppLocalizations l10n,
    Map<String, dynamic> plan,
    dynamic recommendedId, {
    bool compact = false,
  }) {
    final id = (plan['id'] as num?)?.toInt();
    final isRecommended = id == recommendedId;
    final isSubscribing = _subscribingPlanId == id;
    final name = plan['name'] as String? ?? '';
    final desc = plan['description'] as String? ?? '';
    final price = (plan['price'] as num?)?.toDouble() ?? 0;
    final dailyQuota = (plan['daily_quota'] as num?)?.toDouble() ?? 0;
    final durationDays = (plan['duration_days'] as num?)?.toInt() ?? 0;
    final ocrQuota = (plan['ocr_daily_quota'] as num?)?.toInt() ?? 0;
    final realReplyQuota =
        (plan['real_reply_daily_quota'] as num?)?.toInt() ?? 0;
    final allowSync = _allowsSync(plan);

    return Card(
      elevation: isRecommended ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isRecommended
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.get('recommended'),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isRecommended) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '¥$price',
                  style: TextStyle(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  ' / $durationDays ${l10n.get('daysUnit')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPlanChip(
                  scheme,
                  Icons.chat,
                  '${l10n.get('dailyChat')} ¥${dailyQuota.toStringAsFixed(1)}',
                ),
                _buildPlanChip(
                  scheme,
                  Icons.image_search,
                  _formatQuota(
                    l10n,
                    l10n.get('recognitionShort'),
                    ocrQuota,
                    unit: 'times',
                  ),
                ),
                _buildPlanChip(
                  scheme,
                  Icons.psychology,
                  _formatQuota(
                    l10n,
                    l10n.get('realReplyShort'),
                    realReplyQuota,
                    unit: 'rounds',
                  ),
                ),
                _buildPlanChip(
                  scheme,
                  allowSync
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  allowSync
                      ? l10n.get('syncIncluded')
                      : l10n.get('syncNotIncluded'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isSubscribing ? null : () => _subscribePlan(plan),
                style: FilledButton.styleFrom(
                  backgroundColor: isRecommended
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor: isRecommended
                      ? scheme.onPrimary
                      : scheme.onSurface,
                ),
                child: isSubscribing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(l10n.get('subscribing')),
                        ],
                      )
                    : Text(l10n.get('subscribeNow')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanChip(ColorScheme scheme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 格式化订阅计划中某项配额的展示文本
  /// q = -1：无限；q = 0：使用系统默认（附带真实数字）；q > 0：具体次数
  /// unit：'times' 使用"次/日"，'rounds' 使用"轮/日"
  String _formatQuota(
    AppLocalizations l10n,
    String label,
    int q, {
    String unit = 'times',
  }) {
    final unitStr = unit == 'rounds'
        ? l10n.get('roundsPerDay')
        : l10n.get('timesPerDay');
    final prefix = label.isEmpty ? '' : '$label：';
    if (q == -1) return '$prefix${l10n.get('unlimited')}';
    if (q == 0) {
      // 0 = 使用系统默认，展示服务端返回的真实系统默认数字
      final defaultVal = unit == 'rounds'
          ? (_quota?.defaultRealReply ?? 30)
          : (_quota?.defaultOcr ?? 3);
      return '$prefix${l10n.get('defaultLabel')}($defaultVal $unitStr)';
    }
    return '$prefix$q $unitStr';
  }

  // ═══════════════════════════════════════════
  //  功能对比表
  // ═══════════════════════════════════════════

  Widget _buildComparisonTable(ColorScheme scheme, AppLocalizations l10n) {
    final plans = (_plans ?? [])
        .map((p) => p as Map<String, dynamic>)
        .where((p) => (p['status'] as num?)?.toInt() == 1)
        .toList();
    if (plans.isEmpty) return const SizedBox.shrink();

    // 限制最多展示 3 个计划列，避免横向溢出
    final displayPlans = plans.take(3).toList();

    final rows = <_CompareRow>[
      _CompareRow(
        label: l10n.get('dailyChatQuota'),
        freeValue: '¥0',
        planValue: (p) =>
            '¥${(p['daily_quota'] as num?)?.toDouble().toStringAsFixed(1) ?? '0'}',
      ),
      _CompareRow(
        label: l10n.get('chatHistoryRecognition'),
        // 免费用户列固定展示系统默认配额，不受当前订阅状态影响
        freeValue: '${_quota?.defaultOcr ?? 3} ${l10n.get('timesPerDay')}',
        planValue: (p) => _formatQuota(
          l10n,
          '',
          (p['ocr_daily_quota'] as num?)?.toInt() ?? 0,
          unit: 'times',
        ),
      ),
      _CompareRow(
        label: l10n.get('realReplyConversation'),
        // 免费用户列固定展示系统默认配额，不受当前订阅状态影响
        freeValue:
            '${_quota?.defaultRealReply ?? 30} ${l10n.get('roundsPerDay')}',
        planValue: (p) => _formatQuota(
          l10n,
          '',
          (p['real_reply_daily_quota'] as num?)?.toInt() ?? 0,
          unit: 'rounds',
        ),
      ),
      _CompareRow(
        label: l10n.get('validPeriod'),
        freeValue: '—',
        planValue: (p) =>
            '${p['duration_days'] ?? '0'} ${l10n.get('daysUnit')}',
      ),
      _CompareRow(
        label: l10n.get('multiDeviceSync'),
        freeValue: l10n.get('notIncluded'),
        planValue: (p) =>
            _allowsSync(p) ? l10n.get('included') : l10n.get('notIncluded'),
      ),
      _CompareRow(
        label: l10n.get('priceLabel'),
        freeValue: l10n.get('free'),
        planValue: (p) =>
            '¥${(p['price'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}',
        highlight: true,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.get('featureComparison'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 40,
                ),
                child: DataTable(
                  columnSpacing: 16,
                  horizontalMargin: 8,
                  columns: [
                    DataColumn(
                      label: Text(
                        l10n.get('feature'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        l10n.get('freeUser'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final p in displayPlans)
                      DataColumn(
                        label: Text(
                          p['name'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                  rows: rows.map((r) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(r.label, style: const TextStyle(fontSize: 11)),
                        ),
                        DataCell(
                          Text(
                            r.freeValue,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        for (final p in displayPlans)
                          DataCell(
                            Text(
                              r.planValue(p),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: r.highlight
                                    ? FontWeight.bold
                                    : null,
                                color: r.highlight ? scheme.primary : null,
                              ),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareRow {
  final String label;
  final String freeValue;
  final String Function(Map<String, dynamic>) planValue;
  final bool highlight;
  const _CompareRow({
    required this.label,
    required this.freeValue,
    required this.planValue,
    this.highlight = false,
  });
}
