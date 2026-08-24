import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/device_id_service.dart';
import '../services/database_service.dart';
import '../services/account_guard_service.dart';
import '../services/avatar_cache_service.dart';
import '../services/no_email_account_store.dart';
import 'account_guard_provider.dart';
import '../services/quota_service.dart';
import '../services/secure_session_store.dart';
import '../services/sync_websocket_service.dart';
import '../services/proactive_care_alarm.dart';
import 'agent_provider.dart';

/// 认证状态
class AuthState {
  final UserProfile? user;
  final String? jwtToken;
  final String? refreshToken;
  final String? apiKey; // key_secret (明文，用于 Chat Completions)
  final String? apiKeyId; // "ak_xxx" 格式
  final bool isLoading;
  final bool isLoggedIn;
  final String? error;
  final bool sessionExpired; // token 过期且刷新失败
  final Map<String, dynamic>? subscription; // 当前生效的订阅
  final int? subRemainingDays; // 剩余天数 (null=无订阅, <0=已过期)
  /// 订阅资格最近一次从服务端成功刷新的时间。
  ///
  /// 仅用于把本地缓存作为短时离线兜底，不能永久信任旧的订阅状态。
  final DateTime? subscriptionCachedAt;

  /// 多端同步资格的本地缓存有效期。
  static const subscriptionCacheTtl = Duration(hours: 6);

  const AuthState({
    this.user,
    this.jwtToken,
    this.refreshToken,
    this.apiKey,
    this.apiKeyId,
    this.isLoading = false,
    this.isLoggedIn = false,
    this.error,
    this.sessionExpired = false,
    this.subscription,
    this.subRemainingDays,
    this.subscriptionCachedAt,
  });

  bool get hasActiveSubscription => _hasActiveSubscriptionAt(DateTime.now());

  bool get canUseSync => canUseSyncAt(DateTime.now());

  /// 在指定时间判断是否仍可使用多端同步，便于缓存边界测试及统一日期处理。
  bool canUseSyncAt(DateTime now) {
    if (!isLoggedIn || subscription == null) return false;
    if (!_hasActiveSubscriptionAt(now)) return false;
    final cachedAt = subscriptionCachedAt;
    if (cachedAt != null && now.isAfter(cachedAt.add(subscriptionCacheTtl))) {
      return false;
    }
    return _isTruthy(subscription!['allow_sync']);
  }

  /// 页面在网络请求失败时可安全使用的本地订阅缓存。
  bool get hasFreshSubscriptionCache =>
      isSubscriptionCacheFresh(subscriptionCacheTtl);

  bool isSubscriptionCacheFresh(Duration maxAge) {
    final cachedAt = subscriptionCachedAt;
    return cachedAt != null && !DateTime.now().isAfter(cachedAt.add(maxAge));
  }

  bool _hasActiveSubscriptionAt(DateTime now) {
    final sub = subscription;
    if (sub == null) return false;
    final status = sub['status'];
    if (status != null && !_isTruthy(status)) return false;

    final rawExpiresAt = sub['expires_at'];
    if (rawExpiresAt == null || rawExpiresAt.toString().trim().isEmpty) {
      return true;
    }
    final expiry = DateTime.tryParse(rawExpiresAt.toString());
    if (expiry == null) return false;
    // 服务端按日期（含当天）判断有效期，客户端不能把当天的订阅提前判为过期。
    final today = DateTime(now.year, now.month, now.day);
    final expiryDate = DateTime(
      expiry.toLocal().year,
      expiry.toLocal().month,
      expiry.toLocal().day,
    );
    return !expiryDate.isBefore(today);
  }

  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  AuthState copyWith({
    UserProfile? user,
    String? jwtToken,
    String? refreshToken,
    String? apiKey,
    String? apiKeyId,
    bool? isLoading,
    bool? isLoggedIn,
    String? error,
    bool clearError = false,
    bool? sessionExpired,
    Map<String, dynamic>? subscription,
    int? subRemainingDays,
    DateTime? subscriptionCachedAt,
    bool clearSubscription = false,
    bool clearSubscriptionCache = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      jwtToken: jwtToken ?? this.jwtToken,
      refreshToken: refreshToken ?? this.refreshToken,
      apiKey: apiKey ?? this.apiKey,
      apiKeyId: apiKeyId ?? this.apiKeyId,
      isLoading: isLoading ?? this.isLoading,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      error: clearError ? null : (error ?? this.error),
      sessionExpired: sessionExpired ?? this.sessionExpired,
      subscription: clearSubscription
          ? null
          : (subscription ?? this.subscription),
      subRemainingDays: clearSubscription
          ? null
          : (subRemainingDays ?? this.subRemainingDays),
      subscriptionCachedAt: clearSubscriptionCache
          ? null
          : (subscriptionCachedAt ?? this.subscriptionCachedAt),
    );
  }
}

/// 认证状态管理器
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final Ref _ref;
  final SecureSessionStore _sessionStore;
  final RealtimeConnection _realtimeConnection;
  final Future<String> Function() _realtimeDeviceNameLoader;

  AuthNotifier(
    this._ref, {
    SecureSessionStore? sessionStore,
    AuthService? authService,
    RealtimeConnection? realtimeConnection,
    Future<String> Function()? realtimeDeviceNameLoader,
  }) : _sessionStore = sessionStore ?? SecureSessionStore(),
       _authService = authService ?? AuthService(),
       _realtimeConnection =
           realtimeConnection ?? SyncWebSocketService.instance,
       _realtimeDeviceNameLoader =
           realtimeDeviceNameLoader ??
           (() async => (await DeviceIdService.identity).displayName),
       super(const AuthState()) {
    _init();
  }

  /// 初始化完成标记（供外部等第一次加载完成）
  Future<void> get ready => _initCompleter.future;
  final _initCompleter = Completer<void>();
  Future<void> get databaseReady => _databaseReadyCompleter.future;
  final _databaseReadyCompleter = Completer<void>();

  Timer? _subCheckTimer;
  Timer? _tokenRefreshTimer;
  Future<bool>? _silentReAuthFuture;
  String? _storedUsername;
  String? _storedPassword;
  String? _connectedRealtimeJwt;
  int _realtimeGeneration = 0;
  bool _disposed = false;
  bool _logoutInProgress = false;

  /// 全局会话过期回调（由 UI 层设置，用于跳转登录页）
  void Function()? onSessionExpired;

  Future<void> _init() async {
    try {
      await _loadFromStorage();
      if (!_databaseReadyCompleter.isCompleted) {
        _databaseReadyCompleter.complete();
      }
      if (state.isLoggedIn) {
        await _registerCurrentDevice();
        if (state.sessionExpired) {
          final ok = await _tryRefresh();
          if (ok) {
            await refreshDailyAllowance();
            await refreshUserProfile();
            await refreshSubscription();
            _scheduleTokenRefresh();
          }
        } else {
          await refreshDailyAllowance();
          await refreshUserProfile();
          await refreshSubscription();
          // 启动时安排定时 token 刷新（每 6 小时主动续期，避免过期被强制登出）
          _scheduleTokenRefresh();
        }
        if (state.isLoggedIn) {
          await _reconcileAgentsWithServer();
          _startSubCheckTimer();
        }
      }
    } finally {
      if (!_databaseReadyCompleter.isCompleted) {
        _databaseReadyCompleter.complete();
      }
      // 注入鉴权头给 QuotaService（闭包读取最新 state.jwtToken）
      QuotaService.instance.authHeaderProvider = () {
        final jwt = state.jwtToken;
        if (jwt == null || jwt.isEmpty) return <String, String>{};
        return <String, String>{'Authorization': 'Bearer $jwt'};
      };
      QuotaService.instance.cacheOwnerProvider = () =>
          state.user?.username ?? _storedUsername;
      if (state.isLoggedIn && !_realtimeConnection.hasActiveChannel) {
        unawaited(ensureRealtimeConnection());
      }
      _initCompleter.complete();
    }
  }

  /// 统一实时通道：所有登录用户接收应用事件，同步权限由服务端 ready 单独声明。
  Future<void> ensureRealtimeConnection() async {
    final jwt = state.jwtToken;
    if (_disposed || _logoutInProgress || !state.isLoggedIn || jwt == null) {
      return;
    }
    if (_realtimeConnection.hasActiveChannel && _connectedRealtimeJwt == jwt) {
      return;
    }
    final generation = _realtimeGeneration;
    try {
      final deviceName = await _realtimeDeviceNameLoader();
      // 身份查询期间可能发生登出或切换账号，不能让旧任务重新建立连接。
      if (_disposed ||
          _logoutInProgress ||
          generation != _realtimeGeneration ||
          !state.isLoggedIn ||
          state.jwtToken != jwt) {
        return;
      }
      await _realtimeConnection.connect(jwt: jwt, deviceName: deviceName);
      if (!_disposed &&
          !_logoutInProgress &&
          generation == _realtimeGeneration &&
          state.jwtToken == jwt) {
        _connectedRealtimeJwt = jwt;
      }
    } catch (_) {}
  }

  Future<void> _registerCurrentDevice() async {
    if (!state.isLoggedIn || state.jwtToken == null) return;
    try {
      await _authService.registerCurrentDevice();
    } catch (_) {
      // 设备心跳失败不阻断登录，后续同步操作会再次注册。
    }
  }

  Future<void> ensureAgentRegistered(Agent agent) async {
    if (!state.isLoggedIn || state.jwtToken?.isNotEmpty != true) {
      throw const AuthException('请先登录账户');
    }
    await _authService.saveAgent(
      clientId: agent.id,
      name: agent.name,
      gender: agent.gender,
      description: agent.description,
      persona: agent.persona,
      openingLine: agent.openingLine,
      avatarColor: agent.avatarColor,
      avatarPath: agent.avatarPath,
      chatBackground: agent.chatBackground,
      worldview: agent.worldview,
      isSimCharacter: agent.isSimCharacter,
      maxResponseLength: agent.maxResponseLength,
      realInfoEnabled: agent.realInfoEnabled,
      proactiveCareEnabled: agent.proactiveCareEnabled,
      proactiveCareDailyLimit: agent.proactiveCareDailyLimit,
      proactiveCareMinIntervalHours: agent.proactiveCareMinIntervalHours,
    );
  }

  Future<void> _reconcileAgentsWithServer() async {
    final notifier = _ref.read(agentProvider.notifier);
    try {
      await notifier.syncFromServer(_authService);
    } catch (_) {}
    try {
      await notifier.syncToServer(_authService);
    } catch (_) {}
  }

  /// 定时刷新 token：每 6 小时主动调用 /auth/refresh 换取新 token
  /// 避免用户长时间使用后 token 过期被强制登出
  void _scheduleTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      unawaited(trySilentReAuth());
    });
  }

  // ═══ 本地持久化 ═══

  static const _keyUserJson = 'auth_user_json';
  static const _keySubscription = 'auth_subscription';
  static const _keySubDays = 'auth_sub_days';
  static const _keySubCachedAt = 'auth_subscription_cached_at';
  static const _keySubOwner = 'auth_subscription_owner';
  static const _keySessionExpired = 'auth_session_expired';

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await _sessionStore.save(
      SecureSession(
        userId: state.user?.id,
        jwtToken: state.jwtToken,
        refreshToken: state.refreshToken,
        apiKey: state.apiKey,
        apiKeyId: state.apiKeyId,
        username: _storedUsername ?? state.user?.username,
        password: _storedPassword,
      ),
    );
    if (state.user != null) {
      await prefs.setString(_keyUserJson, _userToJson(state.user!));
    }
    if (state.subscription != null) {
      await prefs.setString(_keySubscription, _subToJson(state.subscription!));
    } else {
      await prefs.remove(_keySubscription);
    }
    final cachedAt = state.subscriptionCachedAt;
    if (cachedAt != null) {
      await prefs.setInt(_keySubCachedAt, cachedAt.millisecondsSinceEpoch);
      final owner = state.user?.username;
      if (owner != null && owner.isNotEmpty) {
        await prefs.setString(_keySubOwner, owner);
      } else {
        await prefs.remove(_keySubOwner);
      }
    } else {
      await prefs.remove(_keySubCachedAt);
      await prefs.remove(_keySubOwner);
    }
    if (state.subRemainingDays != null) {
      await prefs.setInt(_keySubDays, state.subRemainingDays!);
    } else {
      await prefs.remove(_keySubDays);
    }
    if (state.sessionExpired) {
      await prefs.setBool(_keySessionExpired, true);
    } else {
      await prefs.remove(_keySessionExpired);
    }
  }

  String _userToJson(UserProfile u) {
    // 用 JSON 序列化：旧的 | 拼接格式在昵称含 | 时整体解析错位
    return jsonEncode({
      'id': u.id,
      'uuid': u.uuid,
      'username': u.username,
      'email': u.email,
      'nickname': u.nickname,
      'avatar': u.avatar,
      'role': u.role,
      'balance': u.balance,
      'totalSpent': u.totalSpent,
      'totalRecharged': u.totalRecharged,
      'frozenBalance': u.frozenBalance,
      'dailyQuotaUsed': u.dailyQuotaUsed,
      'dailyQuotaLeft': u.dailyQuotaLeft,
      'subscriptionQuotaLeft': u.subscriptionQuotaLeft,
    });
  }

  UserProfile? _userFromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    // 新格式：JSON
    if (s.startsWith('{')) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        double d(String key) => (m[key] as num?)?.toDouble() ?? 0;
        return UserProfile(
          id: (m['id'] as num?)?.toInt() ?? 0,
          uuid: m['uuid'] as String? ?? '',
          username: m['username'] as String? ?? '',
          email: m['email'] as String? ?? '',
          nickname: m['nickname'] as String? ?? '',
          avatar: m['avatar'] as String? ?? '',
          role: m['role'] as String? ?? 'user',
          balance: d('balance'),
          totalSpent: d('totalSpent'),
          totalRecharged: d('totalRecharged'),
          frozenBalance: d('frozenBalance'),
          dailyQuotaUsed: d('dailyQuotaUsed'),
          dailyQuotaLeft: d('dailyQuotaLeft'),
          subscriptionQuotaLeft: d('subscriptionQuotaLeft'),
        );
      } catch (_) {
        return null;
      }
    }
    // 旧格式回退（| 拼接）：读到即丢，下次写缓存自动升级 JSON
    final parts = s.split('|');
    if (parts.length < 7) return null;
    return UserProfile(
      id: int.tryParse(parts[0]) ?? 0,
      uuid: parts[1],
      username: parts[2],
      email: parts[3],
      nickname: parts.length > 4 ? parts[4] : '',
      avatar: parts.length > 5 ? parts[5] : '',
      role: parts.length > 6 ? parts[6] : 'user',
      balance: parts.length > 7 ? double.tryParse(parts[7]) ?? 0 : 0,
      totalSpent: parts.length > 8 ? double.tryParse(parts[8]) ?? 0 : 0,
      totalRecharged: parts.length > 9 ? double.tryParse(parts[9]) ?? 0 : 0,
      frozenBalance: parts.length > 10 ? double.tryParse(parts[10]) ?? 0 : 0,
      dailyQuotaUsed: parts.length > 11 ? double.tryParse(parts[11]) ?? 0 : 0,
      dailyQuotaLeft: parts.length > 12 ? double.tryParse(parts[12]) ?? 0 : 0,
      subscriptionQuotaLeft: parts.length > 13
          ? double.tryParse(parts[13]) ?? 0
          : 0,
    );
  }

  String _subToJson(Map<String, dynamic> sub) {
    // 只持久化关键字段，避免存储过大
    final m = <String, dynamic>{};
    for (final k in [
      'id',
      'plan_id',
      'plan_name',
      'daily_quota',
      'started_at',
      'expires_at',
      'model_restrict',
      'allowed_models',
      'allow_sync',
      'status',
    ]) {
      if (sub.containsKey(k)) m[k] = sub[k];
    }
    return const JsonEncoder().convert(m);
  }

  Map<String, dynamic>? _subFromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return const JsonDecoder().convert(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString(_keyUserJson);
      final session = await _sessionStore.loadAndMigrate(prefs);

      if (session?.jwtToken?.isNotEmpty == true) {
        final jwt = session!.jwtToken!;
        final user = _userFromJson(userStr);
        final userId = session.userId ?? user?.id ?? _userIdFromJwt(jwt);
        if (userId == null || userId <= 0) {
          await DatabaseService.switchOpaqueSession(jwt);
        } else {
          await DatabaseService.switchAccount(userId);
        }
        _storedUsername = session.username ?? user?.username;
        _storedPassword = session.password;

        state = state.copyWith(
          user: user,
          jwtToken: jwt,
          refreshToken: session.refreshToken,
          apiKey: session.apiKey,
          apiKeyId: session.apiKeyId,
          isLoggedIn: true,
        );

        _authService.setTokens(jwt: jwt, refresh: session.refreshToken);

        // 恢复缓存的订阅数据。缓存必须属于当前账号且带有时间戳；
        // 没有时间戳的旧缓存不再用于同步资格判定，避免永久放行。
        final subStr = prefs.getString(_keySubscription);
        final subDays = prefs.getInt(_keySubDays);
        final cachedAtMillis = prefs.getInt(_keySubCachedAt);
        final cachedOwner = prefs.getString(_keySubOwner);
        final owner = user?.username ?? session.username;
        if (cachedAtMillis != null &&
            cachedOwner != null &&
            owner != null &&
            cachedOwner == owner) {
          final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);
          if (subStr == null) {
            state = state.copyWith(
              clearSubscription: true,
              subscriptionCachedAt: cachedAt,
            );
          } else {
            state = state.copyWith(
              subscription: _subFromJson(subStr),
              subRemainingDays: subDays,
              subscriptionCachedAt: cachedAt,
            );
          }
        }
        // 恢复 sessionExpired 标记（token 过期但保留供重试）
        if (prefs.getBool(_keySessionExpired) == true) {
          state = state.copyWith(sessionExpired: true);
        }
      } else {
        await DatabaseService.switchAccount(null);
      }
    } catch (_) {
      // 存储数据损坏，清除后重新登录
      await DatabaseService.switchAccount(null);
      state = const AuthState();
    }
  }

  int? _userIdFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      return (payload['user_id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  // ═══ 认证操作 ═══

  /// 注册
  Future<bool> _loginInternal({
    required String username,
    required String password,
    bool showLoading = true,
    bool silent = false,
  }) async {
    if (showLoading) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    return _loginWithCredentials(
      username: username,
      password: password,
      silent: silent,
    );
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authService.register(
        username: username,
        email: email,
        password: password,
        nickname: nickname,
      );
      // 本地记录未绑定邮箱的账号（注册时即可确定）
      await NoEmailAccountStore.mark(username, email.isEmpty);
      await _loginInternal(username: username, password: password);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '网络错误：${e.toString()}');
    }
  }

  /// 带验证码的注册
  Future<void> registerWithCode({
    required String username,
    required String email,
    required String password,
    required String code,
    String? nickname,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authService.registerWithCode(
        username: username,
        email: email,
        password: password,
        code: code,
      );
      // 注册成功后直接登录
      await _loginInternal(username: username, password: password);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '网络错误：${e.toString()}');
    }
  }

  /// 登录
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.login(
        username: username,
        password: password,
        deviceId: await DeviceIdService.id,
      );

      final jwt = data['token'] as String;
      final refresh = data['refresh_token'] as String?;
      final userJson = data['user'] as Map<String, dynamic>?;

      UserProfile? user;
      if (userJson != null) {
        user = UserProfile.fromJson(userJson);
      } else {
        user = UserProfile(
          id: (data['id'] as num?)?.toInt() ?? 0,
          uuid: data['uuid'] as String? ?? '',
          username: data['username'] as String? ?? username,
          email: data['email'] as String? ?? '',
          nickname: data['nickname'] as String? ?? '',
          avatar: data['avatar_url'] as String? ?? '',
          role: data['role'] as String? ?? 'user',
          balance: (data['balance'] as num?)?.toDouble() ?? 0,
        );
      }

      await DatabaseService.switchAccount(user.id);

      _authService.setTokens(jwt: jwt, refresh: refresh);
      _storedUsername = username;
      _storedPassword = password;
      _logoutInProgress = false;
      _realtimeGeneration++;

      state = state.copyWith(
        user: user,
        jwtToken: jwt,
        refreshToken: refresh,
        apiKey: jwt,
        apiKeyId: data['id']?.toString(),
        isLoading: false,
        isLoggedIn: true,
        sessionExpired: false,
        error: null,
        clearSubscription: true,
        clearSubscriptionCache: true,
      );

      await ensureRealtimeConnection();

      await _registerCurrentDevice();

      await _reconcileAgentsWithServer();

      await _saveToStorage();
      await refreshDailyAllowance();
      await refreshUserProfile();
      await refreshSubscription();
      await _recordAccountGuard();
      _startSubCheckTimer();
      _scheduleTokenRefresh();
      unawaited(ProactiveCareAlarmScheduler.sync());
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '网络错误：${e.toString()}');
    }
  }

  /// 登录成功后向服务器查询本设备封禁状态并刷新 provider
  Future<void> _recordAccountGuard() async {
    try {
      final status = await AccountGuardService.checkBan();
      _ref.read(accountGuardProvider.notifier).state = status;
    } catch (_) {}
  }

  /// 登出
  Future<bool> _loginWithCredentials({
    required String username,
    required String password,
    bool silent = true,
  }) async {
    try {
      final data = await _authService.login(
        username: username,
        password: password,
        deviceId: await DeviceIdService.id,
      );

      final jwt = data['token'] as String;
      final refresh = data['refresh_token'] as String?;
      final userJson = data['user'] as Map<String, dynamic>?;

      UserProfile? user;
      if (userJson != null) {
        user = UserProfile.fromJson(userJson);
      } else {
        user = UserProfile(
          id: (data['id'] as num?)?.toInt() ?? 0,
          uuid: data['uuid'] as String? ?? '',
          username: data['username'] as String? ?? username,
          email: data['email'] as String? ?? '',
          nickname: data['nickname'] as String? ?? '',
          avatar: data['avatar_url'] as String? ?? '',
          role: data['role'] as String? ?? 'user',
          balance: (data['balance'] as num?)?.toDouble() ?? 0,
        );
      }

      await DatabaseService.switchAccount(user.id);

      _authService.setTokens(jwt: jwt, refresh: refresh);
      _storedUsername = username;
      _storedPassword = password;
      _logoutInProgress = false;
      _realtimeGeneration++;

      state = state.copyWith(
        user: user,
        jwtToken: jwt,
        refreshToken: refresh,
        apiKey: jwt,
        apiKeyId: data['id']?.toString(),
        isLoading: false,
        isLoggedIn: true,
        sessionExpired: false,
        error: null,
      );

      await ensureRealtimeConnection();

      await _registerCurrentDevice();

      await _reconcileAgentsWithServer();

      await _saveToStorage();
      await refreshDailyAllowance();
      await refreshUserProfile();
      await refreshSubscription();
      await _recordAccountGuard();
      _startSubCheckTimer();
      _scheduleTokenRefresh();
      unawaited(ProactiveCareAlarmScheduler.sync());
      return true;
    } on AuthException catch (e) {
      if (!silent) {
        state = state.copyWith(isLoading: false, error: e.message);
      }
    } catch (e) {
      if (!silent) {
        state = state.copyWith(isLoading: false, error: '网络错误：${e.toString()}');
      }
    }
    return false;
  }

  Future<void> logout() async {
    _logoutInProgress = true;
    _connectedRealtimeJwt = null;
    _realtimeGeneration++;
    _subCheckTimer?.cancel();
    _subCheckTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    await ProactiveCareAlarmScheduler.cancel();
    // 断开多端同步 WS
    await _realtimeConnection.disconnect();
    _authService.setTokens(jwt: null, refresh: null);
    state = const AuthState();
    await DatabaseService.switchAccount(null);
    _storedUsername = null;
    _storedPassword = null;
    final prefs = await SharedPreferences.getInstance();
    await _sessionStore.clear();
    await _sessionStore.removeLegacyAuthData(prefs);
    await prefs.remove(_keyUserJson);
    await prefs.remove(_keySubscription);
    await prefs.remove(_keySubDays);
    await prefs.remove(_keySubCachedAt);
    await prefs.remove(_keySubOwner);
    await prefs.remove(_keySessionExpired);
  }

  /// 刷新用户资料 (从服务器获取最新)
  Future<void> refreshUserProfile() async {
    try {
      final user = await _authService.getCurrentUser();
      await _updateWithBalance(user);
    } on AuthException catch (e) {
      if (e.isUnauthorized) {
        final ok = await trySilentReAuth();
        if (ok && state.jwtToken != null) {
          try {
            final user = await _authService.getCurrentUser();
            await _updateWithBalance(user);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 拉取 profile 后额外合并 balance 端点的配额字段
  Future<void> _updateWithBalance(UserProfile user) async {
    if (DatabaseService.currentUserId != user.id) {
      await DatabaseService.switchAccount(user.id);
    }
    try {
      final balanceData = await _authService.getBalance();
      final updated = user.withBalanceSnapshot(balanceData);
      state = state.copyWith(user: updated);
    } catch (_) {
      state = state.copyWith(user: user);
    }
    // 本地记录该账号是否绑定邮箱（用于找回密码入口判断）
    await NoEmailAccountStore.mark(user.username, user.email.isEmpty);
    // 后台缓存用户头像到本地（弱网/离线也能显示）
    unawaited(AvatarCacheService.refreshForUser(user.avatar));
    await _saveToStorage();
  }

  /// 更新本地用户资料
  Future<void> updateProfile({String? nickname, String? avatar}) async {
    try {
      await _updateProfileOnce(nickname: nickname, avatar: avatar);
    } on AuthException catch (e) {
      // 401：静默重登成功后重试一次
      if (e.isUnauthorized && await trySilentReAuth()) {
        try {
          await _updateProfileOnce(nickname: nickname, avatar: avatar);
          return;
        } on AuthException catch (retryError) {
          state = state.copyWith(error: retryError.message);
          return;
        } catch (_) {
          return;
        }
      }
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> _updateProfileOnce({String? nickname, String? avatar}) async {
    await _authService.updateProfile(nickname: nickname, avatar: avatar);
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(
          nickname: nickname ?? state.user!.nickname,
          avatar: avatar ?? state.user!.avatar,
        ),
      );
      // 头像更新后立即刷新本地缓存，界面即刻换图
      if (avatar != null && avatar.isNotEmpty) {
        unawaited(AvatarCacheService.refreshForUser(avatar));
      }
      await _saveToStorage();
    }
  }

  /// 更新本地余额 (供聊天计费后使用)
  void updateLocalBalance(
    double newBalance, {
    double? dailyQuotaUsed,
    double? dailyQuotaLeft,
    double? subscriptionQuotaLeft,
  }) {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(
          balance: newBalance,
          dailyQuotaUsed: dailyQuotaUsed ?? state.user!.dailyQuotaUsed,
          dailyQuotaLeft: dailyQuotaLeft ?? state.user!.dailyQuotaLeft,
          subscriptionQuotaLeft:
              subscriptionQuotaLeft ?? state.user!.subscriptionQuotaLeft,
        ),
      );
    }
  }

  /// 刷新订阅状态
  Future<void> refreshSubscription({bool isAuthRetry = false}) async {
    if (!state.isLoggedIn) return;
    _lastSubRefreshAt = DateTime.now();
    try {
      final subs = await _authService.getMySubscription();
      await applySubscriptionSnapshot(subs);
    } on AuthException catch (e) {
      // 401：静默重登成功后重试一次
      if (e.isUnauthorized && !isAuthRetry && await trySilentReAuth()) {
        await refreshSubscription(isAuthRetry: true);
      }
    } catch (_) {}
  }

  /// 应用一次服务端订阅快照并更新本地缓存。
  /// 订阅中心在自身请求成功后也调用它，避免页面数据与同步资格使用不同快照。
  Future<void> applySubscriptionSnapshot(List<dynamic> subscriptions) async {
    if (!state.isLoggedIn) return;
    final couldUseSync = state.canUseSync;
    final active = subscriptions.whereType<Map<String, dynamic>>().toList();
    final refreshedAt = DateTime.now();
    if (active.isNotEmpty) {
      // 后端已过滤 status==1 且未过期，前端保留第一条用于当前状态展示。
      final sub = active.first;
      final expiresAt = sub['expires_at']?.toString();
      final expireDate = (expiresAt != null && expiresAt.isNotEmpty)
          ? DateTime.tryParse(expiresAt)
          : null;
      final days = expireDate?.difference(refreshedAt).inDays;
      state = state.copyWith(
        subscription: sub,
        subRemainingDays: days,
        subscriptionCachedAt: refreshedAt,
      );
    } else {
      state = state.copyWith(
        clearSubscription: true,
        subscriptionCachedAt: refreshedAt,
      );
    }
    await _saveToStorage();
    if (couldUseSync != state.canUseSync) {
      _connectedRealtimeJwt = null;
      _realtimeGeneration++;
      await _realtimeConnection.disconnect();
    }
    await ensureRealtimeConnection();
  }

  DateTime? _lastSubRefreshAt;

  /// 节流刷新订阅状态：页面可见时调用，默认 60 秒内不重复请求。
  /// 刚购买订阅返回设置/账户页时能尽快拿到最新订阅，同时避免频繁请求。
  Future<void> maybeRefreshSubscription({
    Duration minInterval = const Duration(seconds: 60),
  }) async {
    final last = _lastSubRefreshAt;
    if (last != null && DateTime.now().difference(last) < minInterval) return;
    await refreshSubscription();
  }

  void _startSubCheckTimer() {
    _subCheckTimer?.cancel();
    _subCheckTimer = Timer.periodic(const Duration(hours: 6), (_) {
      refreshSubscription();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _logoutInProgress = true;
    _connectedRealtimeJwt = null;
    _realtimeGeneration++;
    _subCheckTimer?.cancel();
    _subCheckTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    // 断开多端同步 WS 连接（不销毁 singleton，hot reload 后可重连）
    unawaited(_realtimeConnection.disconnect());
    super.dispose();
  }

  /// 刷新当日免费或订阅额度。
  Future<void> refreshDailyAllowance({bool isAuthRetry = false}) async {
    if (!state.isLoggedIn || state.jwtToken == null) return;
    try {
      final data = await _authService.refreshDailyAllowance();
      final user = state.user;
      if (user == null) return;
      state = state.copyWith(
        user: user.copyWith(
          balance: (data['balance'] as num?)?.toDouble() ?? user.balance,
          dailyQuotaLeft:
              (data['daily_quota_left'] as num?)?.toDouble() ??
              user.dailyQuotaLeft,
          subscriptionQuotaLeft:
              (data['subscription_quota_left'] as num?)?.toDouble() ??
              user.subscriptionQuotaLeft,
        ),
      );
      await _saveToStorage();
    } on AuthException catch (e) {
      // 401：静默重登成功后重试一次
      if (e.isUnauthorized && !isAuthRetry && await trySilentReAuth()) {
        await refreshDailyAllowance(isAuthRetry: true);
      }
    } catch (_) {
      // 每日额度刷新失败不阻断认证和主界面。
    }
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = state.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final data = await _authService.refreshTokenApi(refreshToken);
        if (_disposed || _logoutInProgress) return false;
        final newJwt = data['token'] as String;
        final newRefresh = (data['refresh_token'] as String?) ?? newJwt;
        _authService.setTokens(jwt: newJwt, refresh: newRefresh);
        _logoutInProgress = false;
        _realtimeGeneration++;
        state = state.copyWith(
          jwtToken: newJwt,
          refreshToken: newRefresh,
          sessionExpired: false,
          isLoggedIn: true,
        );
        await ensureRealtimeConnection();
        await _registerCurrentDevice();
        await _saveToStorage();
        return true;
      } catch (_) {}
    }

    final username = _storedUsername;
    final password = _storedPassword;
    if (username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      final restored = await _loginWithCredentials(
        username: username,
        password: password,
        silent: true,
      );
      if (restored) return true;
    }

    await _markSessionExpired();
    return false;
  }

  /// 全链路 401 静默重登：先 refresh token，失败则用已存凭据静默重登。
  /// 并发多个 401 只执行一次重登，其余调用等待同一结果。
  /// 返回 true=登录态恢复；false=会话已过期（已走 [_markSessionExpired] 跳登录页流程）。
  Future<bool> trySilentReAuth() {
    final running = _silentReAuthFuture;
    if (running != null) return running;
    final future = _tryRefresh();
    _silentReAuthFuture = future;
    future.whenComplete(() => _silentReAuthFuture = null).ignore();
    return future;
  }

  /// 网络层检测到 401 时调用：尝试刷新 token，失败则触发会话过期处理。
  /// 通过 [trySilentReAuth] 的共享 Future 防止并发重复刷新。
  Future<void> reportUnauthorized() async {
    await trySilentReAuth();
  }

  /// 启动后检查：如果会话已过期（来自上次运行且刷新失败），触发跳转登录页。
  void checkAndNotifySessionExpired() {
    if (state.sessionExpired) {
      onSessionExpired?.call();
    }
  }

  Future<void> _markSessionExpired() async {
    state = state.copyWith(
      sessionExpired: true,
      isLoggedIn: false,
      isLoading: false,
    );
    await _saveToStorage();
    onSessionExpired?.call();
  }
}

/// Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
