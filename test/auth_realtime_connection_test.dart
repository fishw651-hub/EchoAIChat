import 'dart:async';

import 'package:aichat/models/agent.dart';
import 'package:aichat/models/user_profile.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/services/auth_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_realtime_connection.dart';
import 'helpers/isolated_test_database.dart';

class _MemorySecureStorage implements SecureStorageBackend {
  _MemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _OfflineAuthService extends AuthService {
  @override
  Future<Map<String, dynamic>> registerCurrentDevice() async => {};

  @override
  Future<Map<String, dynamic>> refreshDailyAllowance() async => {};

  @override
  Future<UserProfile> getCurrentUser() async => UserProfile(
    id: 1,
    uuid: 'user-1',
    username: 'tester',
    email: '',
    nickname: '',
    avatar: '',
    role: 'user',
    balance: 0,
  );

  @override
  Future<Map<String, dynamic>> getBalance() async => {};

  @override
  Future<List<dynamic>> getMySubscription() async => [];
}

class _LoginAuthService extends _OfflineAuthService {
  _LoginAuthService({this.failSubscriptionRequest = false, this.refreshJwt});

  final bool failSubscriptionRequest;
  final String? refreshJwt;
  int loginCalls = 0;
  final List<Map<String, dynamic>> savedAgents = [];

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    loginCalls++;
    return {
      'token': 'login-jwt-$loginCalls',
      'refresh_token': 'login-refresh-$loginCalls',
      'user': {
        'id': 1,
        'uuid': 'user-1',
        'username': username,
        'email': '',
        'nickname': '',
        'avatar': '',
        'role': 'user',
        'balance': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
    String? code,
  }) async => {};

  @override
  Future<Map<String, dynamic>> refreshTokenApi(String refreshToken) async {
    final token = refreshJwt;
    if (token == null) {
      throw const AuthException('refresh token unavailable');
    }
    return {'token': token, 'refresh_token': '$token-refresh'};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMyAgents() async =>
      throw const AuthException('cloud agents unavailable');

  @override
  Future<Map<String, dynamic>> saveAgent({
    int? id,
    String? clientId,
    required String name,
    String gender = '',
    String description = '',
    String persona = '',
    String? openingLine,
    int avatarColor = 0xFFE8F5E9,
    String? avatarPath,
    String? chatBackground,
    String worldview = '',
    bool isSimCharacter = false,
    int maxResponseLength = 300,
    bool realInfoEnabled = false,
    bool proactiveCareEnabled = false,
    int proactiveCareDailyLimit = 1,
    int proactiveCareMinIntervalHours = 3,
  }) async {
    savedAgents.add({
      'client_id': clientId,
      'name': name,
      'real_info_enabled': realInfoEnabled,
      'proactive_care_enabled': proactiveCareEnabled,
      'proactive_care_daily_limit': proactiveCareDailyLimit,
      'proactive_care_min_interval_hours': proactiveCareMinIntervalHours,
    });
    return {'id': 1};
  }

  @override
  Future<List<dynamic>> getMySubscription() async {
    if (failSubscriptionRequest) {
      throw const AuthException('subscription unavailable');
    }
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('auth-realtime-connection');
  });

  tearDownAll(() => testDatabase.close());

  test('认证初始化和销毁使用注入的实时连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(
              storage: _MemorySecureStorage({
                SecureSessionStore.jwtKey: 'test-jwt',
                SecureSessionStore.usernameKey: 'tester',
              }),
            ),
            authService: _OfflineAuthService(),
            realtimeConnection: realtime,
          ),
        ),
      ],
    );

    await container.read(authProvider.notifier).ready;
    await Future<void>.delayed(Duration.zero);

    expect(realtime.connectCalls, 1);
    expect(realtime.jwt, 'test-jwt');

    await container.read(authProvider.notifier).ensureRealtimeConnection();
    expect(realtime.connectCalls, 1);

    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(realtime.disconnectCalls, 1);
  });

  test('销毁发生在设备信息查询期间时不会建立陈旧连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final loaderStarted = Completer<void>();
    final deviceName = Completer<String>();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: _OfflineAuthService(),
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () {
              loaderStarted.complete();
              return deviceName.future;
            },
          ),
        ),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    notifier.state = const AuthState(isLoggedIn: true, jwtToken: 'stale-jwt');

    final connecting = notifier.ensureRealtimeConnection();
    await loaderStarted.future;
    container.dispose();
    deviceName.complete('Test Device');
    await connecting;

    expect(realtime.connectCalls, 0);
    expect(realtime.disconnectCalls, 1);
  });

  test('登出清理尚未完成时拒绝新的旧账号连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: _OfflineAuthService(),
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () async => 'Test Device',
          ),
        ),
      ],
    );
    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    notifier.state = const AuthState(
      isLoggedIn: true,
      jwtToken: 'logging-out-jwt',
    );

    final logout = notifier.logout();
    await notifier.ensureRealtimeConnection();
    await logout;

    expect(realtime.connectCalls, 0);
    container.dispose();
  });

  test('同步权限变化时强制重连，权限不变时复用当前连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(
              storage: _MemorySecureStorage({
                SecureSessionStore.jwtKey: 'test-jwt',
                SecureSessionStore.usernameKey: 'tester',
              }),
            ),
            authService: _OfflineAuthService(),
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () async => 'Test Device',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.canUseSync, isFalse);
    expect(realtime.connectCalls, 1);

    final syncEnabled = <String, dynamic>{
      'plan_name': 'Pro',
      'allow_sync': true,
      'expires_at': '2099-12-31',
    };
    await notifier.applySubscriptionSnapshot([syncEnabled]);
    expect(realtime.disconnectCalls, 1);
    expect(realtime.connectCalls, 2);

    await notifier.applySubscriptionSnapshot([syncEnabled]);
    expect(realtime.disconnectCalls, 1);
    expect(realtime.connectCalls, 2);

    await notifier.applySubscriptionSnapshot([
      {'plan_name': 'Basic', 'allow_sync': false, 'expires_at': '2099-12-31'},
    ]);
    expect(realtime.disconnectCalls, 2);
    expect(realtime.connectCalls, 3);
  });

  test('普通登录在订阅请求失败时仍建立实时连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final service = _LoginAuthService(failSubscriptionRequest: true);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: service,
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () async => 'Test Device',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    await notifier.login(username: 'tester', password: 'password');

    expect(notifier.state.isLoggedIn, isTrue);
    expect(realtime.connectCalls, 1);
    expect(realtime.jwt, 'login-jwt-1');
  });

  test('注册后的内部凭据登录在订阅请求失败时仍建立实时连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final service = _LoginAuthService(failSubscriptionRequest: true);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: service,
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () async => 'Test Device',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    await notifier.register(
      username: 'tester',
      email: '',
      password: 'password',
    );

    expect(notifier.state.isLoggedIn, isTrue);
    expect(service.loginCalls, 1);
    expect(realtime.connectCalls, 1);
    expect(realtime.jwt, 'login-jwt-1');
  });

  test('JWT 刷新成功后独立建立最新实时连接', () async {
    SharedPreferences.setMockInitialValues({});
    final realtime = FakeRealtimeConnection();
    final service = _LoginAuthService(refreshJwt: 'refreshed-jwt');
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: service,
            realtimeConnection: realtime,
            realtimeDeviceNameLoader: () async => 'Test Device',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    notifier.state = const AuthState(
      isLoggedIn: true,
      jwtToken: 'stale-jwt',
      refreshToken: 'stale-refresh',
    );

    expect(await notifier.trySilentReAuth(), isTrue);
    expect(notifier.state.jwtToken, 'refreshed-jwt');
    expect(realtime.connectCalls, 1);
    expect(realtime.jwt, 'refreshed-jwt');
  });

  test('聊天前登记会完整上传智能体归属与服务端配额配置', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _LoginAuthService();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _MemorySecureStorage({})),
            authService: service,
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(authProvider.notifier);
    await notifier.ready;
    notifier.state = const AuthState(isLoggedIn: true, jwtToken: 'test-jwt');

    await notifier.ensureAgentRegistered(
      Agent(
        id: 'agent-a',
        name: 'A',
        persona: 'persona',
        realInfoEnabled: true,
        proactiveCareEnabled: true,
        proactiveCareDailyLimit: 4,
        proactiveCareMinIntervalHours: 6,
      ),
    );

    expect(service.savedAgents.single, {
      'client_id': 'agent-a',
      'name': 'A',
      'real_info_enabled': true,
      'proactive_care_enabled': true,
      'proactive_care_daily_limit': 4,
      'proactive_care_min_interval_hours': 6,
    });
  });
}
