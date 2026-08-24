import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/model_list_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // 总页数（欢迎页 + 主题语言页 + 模型选择页 + 登录页），避免魔法数字
  static const int _totalPages = 4;
  final _pageController = PageController();
  int _currentPage = 0;

  // 第二页本地状态：主题模式
  String _selectedThemeMode = 'system';

  // 第三页本地状态：模型列表拉取失败信息（null = 无失败）
  String? _modelListError;

  @override
  void initState() {
    super.initState();
    // 用当前 settings 中的值初始化，避免覆盖用户之前的选择
    final s = ref.read(settingsProvider);
    _selectedThemeMode = s.themeMode;
    // 公开端点无需登录，进入向导即预拉模型列表
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshModels());
  }

  Future<void> _refreshModels() async {
    final error = await ref.read(modelListProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _modelListError = error);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(l10n.get('skip')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildWelcomePage(l10n, scheme),
                  _buildThemeLanguagePage(l10n, scheme),
                  _buildModelPage(l10n, scheme),
                  _buildLoginPage(),
                ],
              ),
            ),
            _buildBottomBar(l10n, scheme),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(AppLocalizations l10n, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: ClipRRect(
                borderRadius: AppTheme.brLg,
                child: Container(
                  color: Colors.black,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 400,
                      height: 400,
                      child: Image.asset('assets/1.jpg'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            l10n.get('onboardingWelcome'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l10n.get('onboardingWelcomeDesc'),
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildThemeLanguagePage(AppLocalizations l10n, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),
          // 图标
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: AppTheme.brLg,
            ),
            child: Icon(
              Icons.palette_outlined,
              size: 36,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppTheme.space5),
          // 标题
          Text(
            l10n.get('onboardingTheme'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l10n.get('onboardingThemeDesc'),
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          // ─── 主题模式 ───
          Row(
            children: [
              Icon(Icons.brightness_6_outlined, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                l10n.get('themeMode'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space3),
          SegmentedButton<String>(
            key: ValueKey('ob_theme_$_selectedThemeMode'),
            segments: [
              ButtonSegment(value: 'system', label: Text(l10n.get('autoTheme'), style: const TextStyle(fontSize: 12))),
              ButtonSegment(value: 'light', label: Text(l10n.get('lightTheme'), style: const TextStyle(fontSize: 12))),
              ButtonSegment(value: 'dark', label: Text(l10n.get('darkTheme'), style: const TextStyle(fontSize: 12))),
            ],
            selected: {_selectedThemeMode},
            onSelectionChanged: (v) {
              setState(() => _selectedThemeMode = v.first);
              ref.read(settingsProvider.notifier).updateThemeMode(v.first);
            },
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildModelPage(AppLocalizations l10n, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppTheme.space4),
          // 图标
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: AppTheme.brLg,
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 36,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space5),
          // 标题
          Text(
            l10n.get('onboardingModel'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l10n.get('onboardingModelDesc'),
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          Expanded(child: _buildModelListArea(l10n, scheme)),
        ],
      ),
    );
  }

  Widget _buildModelListArea(AppLocalizations l10n, ColorScheme scheme) {
    final modelState = ref.watch(modelListProvider);
    final selectedId = ref.watch(settingsProvider).selectedModel;

    // 拉取失败：错误说明 + 重试；不选也可用默认模型直接进入下一页
    if (_modelListError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppTheme.space3),
            Text(
              l10n.get('onboardingModelFailed'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTheme.space4),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _modelListError = null);
                _refreshModels();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.get('retry')),
            ),
          ],
        ),
      );
    }

    // 首次拉取中（仅有内置默认条目时视为列表未就绪）
    if (modelState.refreshing && modelState.models.length <= 1) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              l10n.get('onboardingModelLoading'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: modelState.models.length,
      itemBuilder: (context, i) {
        final m = modelState.models[i];
        final isSelected = m.id == selectedId;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space2),
          child: Material(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: AppTheme.brMd,
            child: InkWell(
              borderRadius: AppTheme.brMd,
              onTap: () =>
                  ref.read(settingsProvider.notifier).setSelectedModel(m.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space4,
                  vertical: AppTheme.space3,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (m.name != m.id)
                            Text(
                              m.id,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginPage() {
    return LoginScreen(
      embedded: true,
      onSuccess: () {
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n, ColorScheme scheme) {
    final isLastPage = _currentPage == _totalPages - 1;
    final isLoggedIn = ref.watch(authProvider).isLoggedIn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Row(
            children: List.generate(
              _totalPages,
              (i) => AnimatedContainer(
                duration: AppTheme.durFast,
                margin: const EdgeInsets.only(right: 6),
                width: _currentPage == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: isLastPage ? (isLoggedIn ? _complete : null) : _nextPage,
            child: Text(isLastPage ? l10n.get('getStarted') : l10n.get('next')),
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: AppTheme.durBase,
      curve: AppTheme.curve,
    );
  }

  void _skip() {
    ref.read(settingsProvider.notifier).markFirstRunComplete();
  }

  Future<void> _complete() async {
    await ref.read(settingsProvider.notifier).markFirstRunComplete();
  }
}
