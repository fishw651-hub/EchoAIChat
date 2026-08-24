import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/update_service.dart';
import 'services/database_service_noop.dart'
    if (dart.library.html) 'services/database_service_web.dart';
import 'config/server_config.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/force_update_screen.dart';
import 'services/network_service.dart';
import 'services/file_cleanup_service.dart';
import 'services/account_guard_service.dart';
import 'services/proactive_care_service.dart';
import 'services/proactive_care_alarm.dart';
import 'providers/account_guard_provider.dart';
import 'providers/app_event_provider.dart';
import 'providers/agent_provider.dart';
import 'providers/agent_folder_provider.dart';
import 'providers/group_provider.dart';
import 'providers/memory_provider.dart';
import 'providers/plan_provider.dart';
import 'providers/user_profile_provider.dart';
import 'screens/account_ban_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/my_network_agents_screen.dart';

final localeProvider = StateProvider<Locale?>((ref) => null);

/// 全局导航 key：通知点击（主动关心）需要在无 BuildContext 处跳转聊天页
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 主动关心通知点击的全局处理器（chat_screen 覆盖 onAiMessageTapped 时委托到这里）
void Function(String payload)? proactiveCareNotificationHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Release 构建静默全部 debugPrint：聊天全文、API 请求结构等敏感内容
  // 不得随 logcat/控制台日志泄漏（debugPrint 在 release 下默认仍会输出）
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // 边到边显示：应用内容（聊天背景、顶/底栏高斯模糊）延伸到
  // 状态栏与导航栏后方，系统栏设为透明
  if (!kIsWeb) {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('[main] edgeToEdge failed: $e');
    }
  }

  // Web 平台初始化 ffi_web 数据库工厂（必须在任何数据库操作前调用）
  // 任何 Web 初始化失败都不能阻塞 UI 渲染，否则会白屏
  if (kIsWeb) {
    try {
      await initWebDatabase();
    } catch (e) {
      debugPrint('[Web] initWebDatabase failed: $e');
    }
  }

  // Phase 0 — minimal sync init: DB + locale + notification (fire-and-forget)
  // DB 迁移失败不能阻塞 UI（Web 端首次访问时 IndexedDB 可能受限）
  Future<void> dbFuture;
  try {
    dbFuture = DatabaseService.migrateDefaultPersona(defaultSystemPersona);
  } catch (e) {
    debugPrint('[main] migrateDefaultPersona launch failed: $e');
    dbFuture = Future.value();
  }

  // Fire notification init in background; don't block first frame
  // Web 端 flutter_local_notifications 不支持，吞异常即可
  final notificationService = NotificationService();
  Future<void> notificationInitFuture;
  try {
    notificationInitFuture = notificationService.initialize();
  } catch (e) {
    debugPrint('[main] notification initialize launch failed: $e');
    notificationInitFuture = Future.value();
  }

  // 从持久化偏好读取语言设置
  final prefs = await SharedPreferences.getInstance();
  final savedLocale = prefs.getString('locale') ?? 'zh';
  final initialLocale = Locale(savedLocale);

  // Ensure DB migration finishes before providers need it
  try {
    await dbFuture;
  } catch (e) {
    debugPrint('[main] dbFuture await failed: $e');
  }

  final container = ProviderContainer(
    overrides: [
      notificationServiceProvider.overrideWithValue(notificationService),
      localeProvider.overrideWith((ref) => initialLocale),
    ],
  );

  DatabaseService.onAccountSwitched = () {
    container.invalidate(chatProvider);
    container.invalidate(groupProvider);
    container.invalidate(longTermProvider);
    container.invalidate(baseProvider);
    container.invalidate(memoryServiceProvider);
    container.invalidate(planProvider);
    container.invalidate(agentFolderProvider);
    container.invalidate(userProfileProvider);
    container.invalidate(agentProvider);
  };
  ApiService.clientAgentIdProvider = () =>
      container.read(agentProvider).currentAgent?.id;
  Future<void> registerAgentById(String clientAgentId) async {
    final agent = await DatabaseService.getAgent(clientAgentId);
    if (agent == null) {
      throw ApiException('本地智能体不存在，请返回首页重新选择');
    }
    try {
      await container.read(authProvider.notifier).ensureAgentRegistered(agent);
    } on AuthException catch (error) {
      throw ApiException('智能体登记失败：${error.message}');
    }
  }

  ApiService.ensureClientAgentRegistered = registerAgentById;
  AgentNotifier.onAgentSaved = (agent) => registerAgentById(agent.id);
  // 只等待本地会话恢复和账号切库，不等待后续网络刷新。
  await container.read(authProvider.notifier).databaseReady;

  // 注册计划消息触发回调：到时间后由 PlanService 触发，注入到当前聊天流
  // 注意：此回调可能在后台/isolate 中触发，因此通过全局 container 访问 ChatNotifier
  try {
    final planService = container.read(planServiceProvider);
    planService.onPlanTriggered = (message, agentId) {
      try {
        container
            .read(chatProvider.notifier)
            .deliverPlannedMessage(message, agentId: agentId);
      } catch (e) {
        debugPrint('[PlanTrigger] deliver failed: $e');
      }
    };
    // 通知点击时也尝试投递
    notificationService.onNotificationTapped = (id) {
      try {
        container.read(planServiceProvider).deliverFromNotification(id);
      } catch (e) {
        debugPrint('[PlanTrigger] notification tapped deliver failed: $e');
      }
    };
  } catch (e) {
    debugPrint('[PlanTrigger] setup failed: $e');
  }

  // ═══ AI 主动关心 ═══
  try {
    final proactiveCare = ProactiveCareService.instance;
    proactiveCare.notificationService = notificationService;
    // 主动关心消息落库后刷新聊天 UI（仅当前聊天窗口属于该智能体时）
    proactiveCare.onMessageDelivered = (agentId) {
      try {
        if (container.read(agentProvider).currentAgent?.id == agentId) {
          container.read(chatProvider.notifier).reloadChatFromDb(agentId);
        }
      } catch (e) {
        debugPrint('[ProactiveCare] UI refresh failed: $e');
      }
    };
    // 通知点击：跳到对应智能体的聊天页
    proactiveCareNotificationHandler = (payload) {
      try {
        if (!payload.startsWith('proactive:')) return;
        final agentId = payload.substring('proactive:'.length);
        if (agentId.isEmpty) return;
        _openAgentChatFromNotification(container, agentId);
      } catch (e) {
        debugPrint('[ProactiveCare] notification tap failed: $e');
      }
    };
    notificationService.onAiMessageTapped = (payload) {
      if (payload != null) proactiveCareNotificationHandler?.call(payload);
    };
    // Android 后台按需安排单个 one-shot alarm
    unawaited(ProactiveCareAlarmScheduler.sync());
    // 前台首次检查（延迟启动，避免与启动初始化争抢资源）
    unawaited(
      Future.delayed(const Duration(minutes: 2), () {
        ProactiveCareService.instance.checkAndTrigger();
      }),
    );
  } catch (e) {
    debugPrint('[ProactiveCare] setup failed: $e');
  }

  runApp(UncontrolledProviderScope(container: container, child: const AIApp()));

  // Complete notification init after first frame (won't block UI)
  await notificationInitFuture;
}

/// 主动关心通知点击：激活对应智能体并跳转聊天页
void _openAgentChatFromNotification(
  ProviderContainer container,
  String agentId,
) {
  final agents = container.read(agentProvider).agents;
  if (!agents.any((a) => a.id == agentId)) return;
  unawaited(container.read(agentProvider.notifier).setActiveAgent(agentId));
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen()));
}

class AIApp extends ConsumerWidget {
  const AIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider) ?? const Locale('zh');
    // 同步给无 BuildContext 的服务层使用（错误提示等）
    AppLocalizations.currentLocale = locale;
    final themeModeSetting = ref.watch(
      settingsProvider.select((state) => state.themeMode),
    );

    ThemeMode themeMode;
    switch (themeModeSetting) {
      case 'light':
        themeMode = ThemeMode.light;
      case 'dark':
        themeMode = ThemeMode.dark;
      default:
        themeMode = ThemeMode.system;
    }

    // Ocean 浅蓝主题为唯一主题
    // 注意：不要用 ValueKey 包含 themeMode，否则主题切换时整个 MaterialApp 树重建，
    // 导致 OnboardingScreen 等子树的 PageController 重置到第 0 页。
    // MaterialApp 的 themeMode 参数变化本身就能正确切换主题。
    // 系统栏透明（边到边）：图标亮度跟随当前主题
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && platformDark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: MaterialApp(
        title: AppLocalizations.of(context).get('appTitle'),
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: AppTheme.oceanLight(),
        darkTheme: AppTheme.oceanDark(),
        themeMode: themeMode,
        // Keyboard shortcut for sending message with Ctrl+Enter
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
              const ActivateIntent(),
        },
        home: const _AppShell(),
      ),
    );
  }
}

/// Shell that decides onboarding vs chat, and wraps keyboard shortcuts.
/// 同时承载浅色/深色模式切换的渐变过渡动画。
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _transitionCtrl;
  String? _lastThemeMode;
  bool _transitionInit = false;
  bool _loginRouteShowing = false;
  Timer? _proactiveCareTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    // 注册全局认证失效回调
    final authNotifier = ref.read(authProvider.notifier);
    authNotifier.onSessionExpired = _handleSessionExpired;
    NetworkService().onUnauthorized = () => authNotifier.trySilentReAuth();
    NetworkService().tokenProvider = () => ref.read(authProvider).jwtToken;
    ApiService.onUnauthorizedRetry = () => authNotifier.trySilentReAuth();
    ApiService.apiKeyProvider = () => ref.read(authProvider).apiKey;

    // 注册更新状态监听：触发 rebuild 以便 build 中拦截强制更新
    UpdateService.addListener(_onUpdateStateChanged);

    // 启动后等待认证初始化完成，检查是否需要跳转登录页
    // （处理上次运行遗留的 sessionExpired 状态）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await authNotifier.ready;
      if (mounted) {
        await authNotifier.refreshDailyAllowance();
        authNotifier.checkAndNotifySessionExpired();
      }
    });

    // 启动时检查本地账号封禁状态（到期自动解封）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final status = await AccountGuardService.checkBan();
      if (mounted) {
        ref.read(accountGuardProvider.notifier).state = status;
      }
    });

    // App 启动自动测试连接，失败时弹窗提示（除非账号失效）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoTestConnection());

    // 清理 app docs 目录中 7 天前的旧文件（截图/导出/备份）
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FileCleanupService.runOnce(),
    );

    // 启动后自动检查更新（仅一次，Web 端跳过——云端即最新）
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => UpdateService.checkUpdate(),
      );
    }

    // 主动关心：前台每 15 分钟周期检查（后台 alarm 之外的补充）
    _proactiveCareTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      ProactiveCareService.instance.checkAndTrigger();
    });
  }

  /// UpdateService 状态变化回调：触发 rebuild 让 build 决定是否渲染强制更新拦截页
  void _onUpdateStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 会话过期处理：清空页面栈，跳转登录页
  void _handleSessionExpired() {
    if (!mounted) return;
    if (_loginRouteShowing) return;
    _loginRouteShowing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _loginRouteShowing = false;
        return;
      }
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen())).then((_) {
        _loginRouteShowing = false;
      });
    });
  }

  /// 启动时自动测试连接，失败时弹窗提示
  Future<void> _autoTestConnection() async {
    if (!mounted) return;
    final auth = ref.read(authProvider);
    // 未登录或无 API key 不测试
    final apiKey = auth.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    try {
      final result = await ApiService.testConnection(
        baseUrl: ServerConfig.baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      // "连接成功" 之外都算失败
      if (result == '连接成功') return;
      // 账号失效类不弹（用户自己问题）
      if (result.contains('API Key') || result.contains('无权限')) return;
      _showConnectionFailDialog(l10n, result);
    } catch (e) {
      if (!mounted) return;
      _showConnectionFailDialog(
        l10n,
        l10n.getP('feedbackNetworkErrorWithDetail', {'error': '$e'}),
      );
    }
  }

  void _showConnectionFailDialog(AppLocalizations l10n, String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.wifi_off,
          color: Theme.of(context).colorScheme.error,
          size: 32,
        ),
        title: Text(l10n.get('connectionTestFailedTitle')),
        content: Text(
          l10n.getP('aiNoReplyNotice', {'reason': reason}),
          textAlign: TextAlign.start,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _proactiveCareTimer?.cancel();
    UpdateService.removeListener(_onUpdateStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _transitionCtrl.dispose();
    super.dispose();
  }

  void _triggerThemeTransition() {
    _transitionCtrl.forward(from: 0.0).then((_) {
      if (mounted) _transitionCtrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shellSettings = ref.watch(
      settingsProvider.select(
        (state) => (themeMode: state.themeMode, isFirstRun: state.isFirstRun),
      ),
    );

    ref.listen<AppEventState>(appEventProvider, (previous, next) {
      if (previous?.reviewNoticeRevision == next.reviewNoticeRevision ||
          next.reviewNotice == null) {
        return;
      }
      final notice = next.reviewNotice!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.hideCurrentSnackBar();
        final controller = messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${notice.name}: ${notice.reason}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            action: notice.resourceType == 'agent'
                ? SnackBarAction(
                    label: AppLocalizations.of(context).get('view'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyNetworkAgentsScreen(),
                        ),
                      );
                    },
                  )
                : null,
          ),
        );
        unawaited(
          controller.closed.then((_) {
            if (!mounted) return;
            ref
                .read(appEventProvider.notifier)
                .acknowledgeReviewNotice(notice.eventId);
          }),
        );
      });
    });

    // 首次 build 记录初始主题，后续变化时触发过渡动画
    if (!_transitionInit) {
      _lastThemeMode = shellSettings.themeMode;
      _transitionInit = true;
    } else if (_lastThemeMode != shellSettings.themeMode) {
      _lastThemeMode = shellSettings.themeMode;
      _triggerThemeTransition();
    }

    // ===== 本地账号封禁拦截（最高优先级）=====
    // 2 周内切换 ≥3 个不同账号触发本地封禁，渲染全屏拦截页替代主界面，
    // 到期自动解封；有订阅的账号不受限。
    final banStatus = ref.watch(accountGuardProvider);
    if (banStatus.banned) {
      return AccountBanScreen(status: banStatus);
    }

    // ===== 强制更新拦截（最高优先级）=====
    // 如果服务器返回 is_force=true 的更新，渲染全屏拦截页替代主界面，
    // 用户无法进入 app 任何功能，只能点击"立即更新"跳转浏览器下载安装。
    final forceUpdate = UpdateService.availableUpdate;
    if (forceUpdate != null && forceUpdate.isForce) {
      return ForceUpdateScreen(update: forceUpdate);
    }

    Widget home;
    if (shellSettings.isFirstRun) {
      home = const OnboardingScreen(key: ValueKey('onboarding'));
    } else {
      home = const HomeScreen(key: ValueKey('home'));
    }

    return Stack(
      children: [
        Positioned.fill(child: home),
        // 浅色/深色切换渐变过渡遮罩
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _transitionCtrl,
            builder: (context, _) {
              // 0 值且无动画时完全不显示
              if (_transitionCtrl.value == 0 && !_transitionCtrl.isAnimating) {
                return const SizedBox.shrink();
              }
              // 正向播放（淡入）：0 → 1，遮罩变浓
              // 反向播放（淡出）：1 → 0，遮罩变淡
              final v = _transitionCtrl.value;
              final opacity = (v * 0.85).clamp(0.0, 0.85);
              return ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: opacity),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).refreshDailyAllowance();
      unawaited(ref.read(appEventProvider.notifier).refreshAfterResume());
      // 回前台时补一次主动关心检查（后台 alarm 可能被杀后台延迟）
      ProactiveCareService.instance.checkAndTrigger();
      // 从后台回到前台时重新检查更新：
      // - 若首次检查曾因网络失败（_checked=false），此时重试
      // - 若用户在浏览器下载完新版本但未安装就返回 app，强制更新状态保持不变
      //   （_checked=true 时 checkUpdate 是 no-op，拦截页继续生效）
      UpdateService.checkUpdate();
    }
  }
}
