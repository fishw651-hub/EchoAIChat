import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/group_provider.dart';
import '../providers/home_tab_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_group_tab.dart';
import '../widgets/contact_list.dart';
import '../widgets/group_list_tab.dart';
import '../widgets/newbie_guide.dart';
import '../widgets/sub_tab_switcher.dart';
import 'account_screen.dart';
import 'agent_create_screen.dart';
import 'group_create_screen.dart';
import 'home_tab_screen.dart';
import 'network_content_tab.dart';

/// 移动端 PageView 6 页 → 底部导航 4 tab 的映射。
///
/// 页序：[首页, 智能体, 群聊, 发现-智能体, 发现-群聊, 账户]，
/// 即 page 1-2 同属 tab 1（智能体·群聊合并 tab），page 3-4 同属 tab 2（发现），
/// 让左右滑动先切子 tab、再切主 tab。
int homePageToTabIndex(int page) => switch (page) {
  0 => 0,
  1 || 2 => 1,
  3 || 4 => 2,
  _ => 3,
};

/// 底部导航 tab → PageView 页码（上一映射的反向）。
///
/// [subPageGroups] 表示该 tab 当前是否停在"群聊"子页
/// （tab 1 读 agentTabSubPageProvider，tab 2 读 discoveryTabTypeProvider）。
int homeTabToPageIndex(int tab, {bool subPageGroups = false}) => switch (tab) {
  0 => 0,
  1 => subPageGroups ? 2 : 1,
  2 => subPageGroups ? 4 : 3,
  _ => 5,
};

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  // 桌面端侧边栏切换 tab 后，回到移动端需把 PageView 同步到当前页
  bool _needsPageSync = false;

  @override
  void initState() {
    super.initState();
    // 新账号首次进入主界面：询问是否需要新手指导
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuide());
  }

  Future<void> _maybeShowGuide() async {
    // 等 providers 从本地数据库加载完成再判断
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final auth = ref.read(authProvider);
    final user = auth.user;
    if (!auth.isLoggedIn || user == null) return;
    final hasAgents = ref.read(agentProvider).agents.isNotEmpty;
    final hasGroups = ref.read(groupProvider).groups.isNotEmpty;
    if (!mounted) return;
    await NewbieGuide.maybeShow(
      context,
      userId: user.id.toString(),
      hasAgents: hasAgents,
      hasGroups: hasGroups,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 合并 tab（index 1）与发现 tab（index 2）有智能体/群聊两个子页，
  /// 需要显示子页分段控件（移动端浮于底部导航栏上方，桌面端在内容区顶部）
  bool get _showSubTabBar => _currentIndex == 1 || _currentIndex == 2;

  // tab 顺序：首页 / 智能体·群聊（合并，标签跟随当前子页） / 发现 / 账户
  List<String> _tabTitles(AppLocalizations l10n, bool showingGroups) => [
    l10n.get('tabHome'),
    showingGroups ? l10n.get('groupChats') : l10n.get('agentSection'),
    l10n.get('tabDiscovery'),
    l10n.get('account'),
  ];

  /// 各 tab 的 未选中/选中 图标
  static (IconData, IconData) _tabIcons(int index) => switch (index) {
    0 => (Icons.home_outlined, Icons.home_rounded),
    1 => (Icons.people_alt_outlined, Icons.people_alt_rounded),
    2 => (Icons.cloud_outlined, Icons.cloud_rounded),
    _ => (Icons.account_circle_outlined, Icons.account_circle_rounded),
  };

  /// 桌面端 _LazyIndexedStack 用的 4 tab 构建器（子页由 provider 控制的
  /// IndexedStack 承载）
  late final List<WidgetBuilder> _tabBuilders = [
    (_) => const HomeTabScreen(),
    (_) => const AgentGroupTab(),
    (_) => const NetworkContentTab(),
    (_) => const AccountScreen(),
  ];

  /// 移动端 PageView 6 页构建器：[首页, 智能体, 群聊, 发现-智能体,
  /// 发现-群聊, 账户]。智能体/群聊、发现-智能体/发现-群聊拆为独立页，
  /// 左右滑动先切子 tab 再切主 tab；发现子页用 fixedType 固定类型，
  /// 不随 discoveryTabTypeProvider 重拉列表。
  late final List<WidgetBuilder> _pageBuilders = [
    (_) => const HomeTabScreen(),
    (_) => const ContactListWidget(),
    (_) => const GroupListTabWidget(),
    (_) => const NetworkContentTab(fixedType: 'agent'),
    (_) => const NetworkContentTab(fixedType: 'group'),
    (_) => const AccountScreen(),
  ];

  /// tab → 当前应显示的 PageView 页码（读子页 provider 决定落在哪个子页）
  int _pageForTab(int tab) => homeTabToPageIndex(
    tab,
    subPageGroups: switch (tab) {
      1 => ref.read(agentTabSubPageProvider),
      2 => ref.read(discoveryTabTypeProvider),
      _ => false,
    },
  );

  /// PageView 翻页回调：同步底部导航高亮与子页 provider
  /// （page 1/2 → agentTabSubPageProvider，page 3/4 → discoveryTabTypeProvider），
  /// 保证浮动分段控件与桌面端子页状态一致
  void _onPageChanged(int page) {
    if (page == 1 || page == 2) {
      ref.read(agentTabSubPageProvider.notifier).state = page == 2;
    } else if (page == 3 || page == 4) {
      ref.read(discoveryTabTypeProvider.notifier).state = page == 4;
    }
    final tab = homePageToTabIndex(page);
    if (tab != _currentIndex) setState(() => _currentIndex = tab);
  }

  void _switchTo(int index) {
    // 底部 tab 点击只负责切 tab，子页切换由浮动分段控件承担
    if (index == _currentIndex) return;
    if (_pageController.hasClients) {
      // 移动端：PageView 切换，onPageChanged 会同步 _currentIndex
      // 目标页 = 该 tab 当前子页对应页；跨度 >1 时直接跳转，避免快速闪过中间页面
      final targetPage = _pageForTab(index);
      final currentPage =
          _pageController.page?.round() ?? _pageForTab(_currentIndex);
      if ((targetPage - currentPage).abs() > 1) {
        _pageController.jumpToPage(targetPage);
      } else {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } else {
      setState(() {
        _currentIndex = index;
        _needsPageSync = true;
      });
    }
  }

  /// tab 图标：AnimatedSwitcher（scale+fade）切换选中态
  Widget _tabIcon(int index, bool selected) {
    final (outlined, filled) = _tabIcons(index);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        selected ? filled : outlined,
        key: ValueKey('tabIcon-$index-$selected'),
      ),
    );
  }

  /// 子页分段控件（智能体 | 群聊）：合并 tab 控制 [agentTabSubPageProvider]，
  /// 发现 tab 控制 [discoveryTabTypeProvider]（NetworkContentTab watch 后重新拉取列表）。
  /// 移动端点击时同步 animateToPage 到对应子页；桌面端 PageController 未挂载，
  /// 仅更新 provider 由 IndexedStack 子页自行刷新。
  Widget _buildSubTabSwitcher(AppLocalizations l10n) {
    final forAgentTab = _currentIndex == 1;
    final provider = forAgentTab
        ? agentTabSubPageProvider
        : discoveryTabTypeProvider;
    final secondSelected = ref.watch(provider);
    return SubTabSwitcher(
      firstLabel: l10n.get('agentSection'),
      secondLabel: l10n.get('groupChats'),
      firstIcon: Icons.person_outline_rounded,
      secondIcon: Icons.groups_outlined,
      secondSelected: secondSelected,
      onChanged: (value) {
        ref.read(provider.notifier).state = value;
        if (_pageController.hasClients) {
          final basePage = forAgentTab ? 1 : 3;
          _pageController.animateToPage(
            value ? basePage + 1 : basePage,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) return _buildDesktop(context);
        return _buildMobile(context);
      },
    );
  }

  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final tabTitles = _tabTitles(l10n, ref.watch(agentTabSubPageProvider));
    final isDark = scheme.brightness == Brightness.dark;
    // 智能体列表多选时隐藏浮动子页分段控件，避免遮挡多选底栏操作键
    final contactSelecting = ref.watch(contactSelectionModeProvider);
    final showSubTabBar =
        _showSubTabBar && !(_currentIndex == 1 && contactSelecting);
    if (_needsPageSync) {
      _needsPageSync = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        final targetPage = _pageForTab(_currentIndex);
        final page = _pageController.page?.round() ?? targetPage;
        if (page != targetPage) {
          _pageController.jumpToPage(targetPage);
        }
      });
    }
    return Scaffold(
      // 页面内容延伸到底部，悬浮栏之外的透明区域能看到栏下内容
      extendBody: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pageBuilders.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) =>
                _KeepAliveTab(child: _pageBuilders[index](context)),
          ),
          // 浮动子页分段控件：浮在底部悬浮导航栏上方，切走 tab 时滑出淡出。
          // 常驻树中（隐藏时 IgnorePointer），保证出现/消失动画可播放。
          Positioned(
            left: 0,
            right: 0,
            // 悬浮导航栏总高 ≈ 上下 margin 16 + 栏高 80，再加 12 间距
            bottom: MediaQuery.paddingOf(context).bottom + 96 + 12,
            child: IgnorePointer(
              ignoring: !showSubTabBar,
              child: Center(
                child: AnimatedSlide(
                  offset: showSubTabBar ? Offset.zero : const Offset(0, 0.6),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: showSubTabBar ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: _buildSubTabSwitcher(l10n),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            AppTheme.space1,
            AppTheme.space4,
            AppTheme.space3,
          ),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.92 : 0.94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark
                  ? scheme.outlineVariant.withValues(alpha: 0.65)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
            // 3D 立体感：浅色多层柔和投影；深色减弱阴影、靠边框与微光分层
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.08),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              SizedBox(
                height: 76,
                child: Row(
                  children: [
                    Expanded(
                      child: _MobileTabDestination(
                        label: tabTitles[0],
                        selected: _currentIndex == 0,
                        icon: _tabIcon(0, false),
                        selectedIcon: _tabIcon(0, true),
                        onTap: () => _switchTo(0),
                      ),
                    ),
                    Expanded(
                      child: _MobileTabDestination(
                        label: tabTitles[1],
                        selected: _currentIndex == 1,
                        icon: _tabIcon(1, false),
                        selectedIcon: _tabIcon(1, true),
                        onTap: () => _switchTo(1),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Center(
                        child: MobileCreateAction(
                          onCreateAgent: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AgentCreateScreen(),
                            ),
                          ),
                          onCreateGroup: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GroupCreateScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _MobileTabDestination(
                        label: tabTitles[2],
                        selected: _currentIndex == 2,
                        icon: _tabIcon(2, false),
                        selectedIcon: _tabIcon(2, true),
                        onTap: () => _switchTo(2),
                      ),
                    ),
                    Expanded(
                      child: _MobileTabDestination(
                        label: tabTitles[3],
                        selected: _currentIndex == 3,
                        icon: _tabIcon(3, false),
                        selectedIcon: _tabIcon(3, true),
                        onTap: () => _switchTo(3),
                      ),
                    ),
                  ],
                ),
              ),
              // 顶部 1px 高亮边，强化浮层立体感
              Positioned(
                top: 0,
                left: 28,
                right: 28,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.surfaceTint.withValues(alpha: 0),
                          (isDark ? scheme.surfaceTint : scheme.onSurface)
                              .withValues(alpha: isDark ? 0.2 : 0.08),
                          scheme.surfaceTint.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final tabTitles = _tabTitles(l10n, ref.watch(agentTabSubPageProvider));
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.space4),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: AppTheme.brMd,
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: scheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space3),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.get('appTitle'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              l10n.get('appSlogan'),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.space2),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space3,
                      ),
                      itemCount: tabTitles.length,
                      itemBuilder: (context, index) {
                        final selected = index == _currentIndex;
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTheme.space1,
                          ),
                          child: ListTile(
                            selected: selected,
                            selectedTileColor: scheme.primaryContainer
                                .withValues(alpha: 0.7),
                            leading: _tabIcon(index, selected),
                            title: Text(tabTitles[index]),
                            onTap: () => _switchTo(index),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                // 桌面端无底部导航栏：子页分段控件放在内容区顶部（高度动画进出）
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _showSubTabBar
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppTheme.space3),
                          child: Center(child: _buildSubTabSwitcher(l10n)),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: _LazyIndexedStack(
                        index: _currentIndex,
                        builders: _tabBuilders,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.builders});

  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  final Map<int, Widget> _builtChildren = <int, Widget>{};

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.index.clamp(0, widget.builders.length - 1);
    _builtChildren.putIfAbsent(
      activeIndex,
      () => widget.builders[activeIndex](context),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _builtChildren.entries)
          Offstage(
            offstage: entry.key != activeIndex,
            child: TickerMode(
              enabled: entry.key == activeIndex,
              child: entry.value,
            ),
          ),
      ],
    );
  }
}

/// PageView 内保持 tab 状态不销毁（与桌面端 _LazyIndexedStack 语义一致）。
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _MobileTabDestination extends StatelessWidget {
  const _MobileTabDestination({
    required this.label,
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget icon;
  final Widget selectedIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    size: 26,
                  ),
                  child: selected ? selectedIcon : icon,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class MobileCreateAction extends StatefulWidget {
  const MobileCreateAction({
    super.key,
    required this.onCreateAgent,
    required this.onCreateGroup,
  });

  final VoidCallback onCreateAgent;
  final VoidCallback onCreateGroup;

  @override
  State<MobileCreateAction> createState() => _MobileCreateActionState();
}

class _MobileCreateActionState extends State<MobileCreateAction>
    with SingleTickerProviderStateMixin {
  static const _menuAnimationDuration = Duration(milliseconds: 220);

  final LayerLink _menuLink = LayerLink();
  final OverlayPortalController _menuController = OverlayPortalController();
  late final AnimationController _menuAnimationController = AnimationController(
    vsync: this,
    duration: _menuAnimationDuration,
  );
  late final Animation<Offset> _menuSlide =
      Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _menuAnimationController,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );

  @override
  void dispose() {
    _menuAnimationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isShowing) {
      _dismissMenu();
      return;
    }
    _menuController.show();
    _menuAnimationController.forward(from: 0);
  }

  Future<void> _dismissMenu() async {
    if (!_menuController.isShowing) return;
    await _menuAnimationController.reverse();
    if (mounted) _menuController.hide();
  }

  void _selectAction(VoidCallback action) {
    _menuController.hide();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OverlayPortal(
      controller: _menuController,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _dismissMenu();
              },
            ),
            CompositedTransformFollower(
              link: _menuLink,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -12),
              child: FadeTransition(
                opacity: _menuAnimationController,
                child: SlideTransition(
                  key: const Key('create-menu-enter-animation'),
                  position: _menuSlide,
                  child: _buildMenuCard(context),
                ),
              ),
            ),
          ],
        ),
      ),
      child: CompositedTransformTarget(
        link: _menuLink,
        child: Tooltip(
          message: '新建',
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              key: const Key('home-create-button'),
              customBorder: const CircleBorder(),
              onTap: _toggleMenu,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  Icons.add_rounded,
                  color: scheme.onPrimary,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 10,
      shadowColor: scheme.shadow.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 296,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CreateMenuItem(
              key: const Key('create-agent-action'),
              onPressed: () => _selectAction(widget.onCreateAgent),
              icon: Icons.person_add_alt_1_outlined,
              title: '创建智能体',
              subtitle: '从零开始打造专属角色',
            ),
            const Padding(
              padding: EdgeInsets.only(left: 66, right: 8),
              child: Divider(height: 1),
            ),
            _CreateMenuItem(
              key: const Key('create-group-action'),
              onPressed: () => _selectAction(widget.onCreateGroup),
              icon: Icons.group_add_outlined,
              title: '创建群聊',
              subtitle: '邀请多个智能体一起交流',
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateMenuItem extends StatelessWidget {
  const _CreateMenuItem({
    required super.key,
    required this.onPressed,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: scheme.onPrimaryContainer,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
