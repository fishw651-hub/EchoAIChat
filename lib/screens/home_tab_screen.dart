import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/announcement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/announcement_dialog.dart';
import '../widgets/conversation_list.dart';
import '../widgets/echo_visual_surface.dart';
import '../widgets/home_profile_summary_card.dart';
import 'account_screen.dart';
import 'memory_screen.dart';

class HomeTabScreen extends ConsumerStatefulWidget {
  const HomeTabScreen({super.key});

  @override
  ConsumerState<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends ConsumerState<HomeTabScreen> {
  bool _announcementChecked = false;

  @override
  void initState() {
    super.initState();
    // 进入首页时拉取一次公告（应用切后台再回来不触发 initState，不会重复拉）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAnnouncements();
    });
  }

  /// 拉取公告 → 目标过滤 + 频率过滤 → 按列表顺序依次弹出
  Future<void> _checkAnnouncements() async {
    if (_announcementChecked) return;
    _announcementChecked = true;

    // 等鉴权状态从本地存储恢复完成再判断登录态（未登录不弹公告）
    await ref.read(authProvider.notifier).ready;
    if (!mounted) return;
    final auth = ref.read(authProvider);
    final jwt = auth.jwtToken;
    if (!auth.isLoggedIn || jwt == null || jwt.isEmpty) return;

    final list = await AnnouncementService.fetchActive(jwt);
    if (!mounted || list.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasSub = ref.read(authProvider).hasActiveSubscription;
    final queue = list
        .where(
          (a) =>
              AnnouncementService.matchesAudience(
                a,
                hasActiveSubscription: hasSub,
              ) &&
              AnnouncementService.shouldShow(a, prefs),
        )
        .toList();

    // 队列依次弹出：一条关闭后才弹下一条；页面销毁即中断
    for (final a in queue) {
      if (!mounted) return;
      final result =
          await AnnouncementDialog.show(context, a) ??
          AnnouncementDismiss.close;
      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: result == AnnouncementDismiss.dontShowToday,
        prefs: prefs,
      );
    }
  }

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.read(authProvider.notifier).refreshUserProfile(),
      ref.read(userProfileProvider.notifier).loadProfiles(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final profile = ref.watch(userProfileProvider);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Stack(
        children: [
          // 头部渐隐光晕：固定于顶层，标题与额度胶囊浮于其上
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: EchoHeaderGlow(height: 220),
          ),
          Column(
            children: [
              // 固定标题行（回响AI + 今日可用胶囊）：不随滚动收起/位移
              SafeArea(
                bottom: false,
                child: Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.get('appTitle'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      _QuotaPill(
                        user: user,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refresh(ref),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.space4,
                          AppTheme.space3,
                          AppTheme.space4,
                          AppTheme.space4,
                        ),
                        child: HomeProfileSummaryCard(
                          entries: profile.grouped.values
                              .expand((entries) => entries)
                              .toList(),
                          totalCount: profile.totalCount,
                          onOpenProfile: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MemoryScreen(initialTabIndex: 3),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space4,
                        ),
                        child: EchoSectionHeader(
                          title: l10n.get('recentEchoes'),
                          subtitle: l10n.get('recentEchoesSubtitle'),
                        ),
                      ),
                      const SizedBox(height: AppTheme.space2),
                      const Expanded(child: ConversationListWidget()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaPill extends StatelessWidget {
  const _QuotaPill({required this.user, required this.onTap});

  final UserProfile? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final dailyLeft =
        (user?.dailyQuotaLeft ?? 0) + (user?.subscriptionQuotaLeft ?? 0);
    return Semantics(
      button: true,
      label: l10n.getP('todayQuotaSemantics', {
        'amount': dailyLeft.toStringAsFixed(2),
      }),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.62),
        borderRadius: AppTheme.brMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.brMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space3,
              vertical: AppTheme.space2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 15,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.get('todayAvailable'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '¥${dailyLeft.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
