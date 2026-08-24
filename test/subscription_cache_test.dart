import 'package:aichat/models/user_profile.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/services/auth_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_realtime_connection.dart';

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

class _SubscriptionAuthService extends AuthService {
  _SubscriptionAuthService({required this.subscriptions});

  List<dynamic> subscriptions;

  @override
  Future<Map<String, dynamic>> registerCurrentDevice() async => {};

  @override
  Future<UserProfile> getCurrentUser() async => UserProfile(
    id: 7,
    uuid: 'user-7',
    username: 'cache-user',
    email: 'cache@example.com',
    nickname: 'Cache User',
    avatar: '',
    role: 'user',
    balance: 0,
  );

  @override
  Future<Map<String, dynamic>> getBalance() async => {};

  @override
  Future<Map<String, dynamic>> refreshDailyAllowance() async => {};

  @override
  Future<List<dynamic>> getMySubscription() async {
    if (subscriptions.isEmpty) {
      throw Exception('subscription endpoint unavailable');
    }
    return subscriptions;
  }
}

final _user = UserProfile(
  id: 7,
  uuid: 'user-7',
  username: 'cache-user',
  email: 'cache@example.com',
  nickname: 'Cache User',
  avatar: '',
  role: 'user',
  balance: 0,
);

ProviderContainer _container(
  _MemorySecureStorage storage,
  _SubscriptionAuthService service,
) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier(
          ref,
          sessionStore: SecureSessionStore(storage: storage),
          authService: service,
          realtimeConnection: FakeRealtimeConnection(),
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('重建后网络不可用时使用新鲜的本地同步订阅缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _MemorySecureStorage({
      SecureSessionStore.jwtKey: 'jwt',
      SecureSessionStore.usernameKey: 'cache-user',
    });
    final firstService = _SubscriptionAuthService(subscriptions: []);
    final first = _container(storage, firstService);
    addTearDown(first.dispose);
    await first.read(authProvider.notifier).ready;

    final firstNotifier = first.read(authProvider.notifier);
    firstNotifier.state = AuthState(
      user: _user,
      isLoggedIn: true,
      jwtToken: 'jwt',
    );
    await firstNotifier.applySubscriptionSnapshot([
      {'plan_name': 'Pro', 'allow_sync': true, 'expires_at': '2099-12-31'},
    ]);

    final secondService = _SubscriptionAuthService(subscriptions: []);
    final second = _container(storage, secondService);
    addTearDown(second.dispose);
    await second.read(authProvider.notifier).ready;

    expect(second.read(authProvider).canUseSync, isTrue);
  });

  test('本地同步订阅缓存过期后不再放行', () async {
    final cachedAt = DateTime.now()
        .subtract(AuthState.subscriptionCacheTtl + const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'auth_user_json':
          '{"id":7,"uuid":"user-7","username":"cache-user","email":"cache@example.com","nickname":"Cache User","avatar":"","role":"user"}',
      'auth_subscription':
          '{"plan_name":"Pro","allow_sync":true,"expires_at":"2099-12-31"}',
      'auth_sub_days': 100,
      'auth_subscription_cached_at': cachedAt,
      'auth_subscription_owner': 'cache-user',
    });
    final storage = _MemorySecureStorage({
      SecureSessionStore.jwtKey: 'jwt',
      SecureSessionStore.usernameKey: 'cache-user',
    });
    final container = _container(
      storage,
      _SubscriptionAuthService(subscriptions: []),
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    expect(container.read(authProvider).canUseSync, isFalse);
  });

  test('服务端刷新后的订阅快照会覆盖旧缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _MemorySecureStorage({
      SecureSessionStore.jwtKey: 'jwt',
      SecureSessionStore.usernameKey: 'cache-user',
    });
    final container = _container(
      storage,
      _SubscriptionAuthService(subscriptions: []),
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    final notifier = container.read(authProvider.notifier);
    notifier.state = AuthState(user: _user, isLoggedIn: true, jwtToken: 'jwt');
    await notifier.applySubscriptionSnapshot([
      {'plan_name': 'Pro', 'allow_sync': true, 'expires_at': '2099-12-31'},
    ]);
    await notifier.applySubscriptionSnapshot([
      {'plan_name': 'Basic', 'allow_sync': false, 'expires_at': '2099-12-31'},
    ]);

    expect(notifier.state.canUseSync, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_subscription'), contains('Basic'));
  });

  test('无订阅快照也会记录刷新时间用于短期负缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _MemorySecureStorage({
      SecureSessionStore.jwtKey: 'jwt',
      SecureSessionStore.usernameKey: 'cache-user',
    });
    final container = _container(
      storage,
      _SubscriptionAuthService(subscriptions: []),
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    final notifier = container.read(authProvider.notifier);
    notifier.state = AuthState(user: _user, isLoggedIn: true, jwtToken: 'jwt');
    await notifier.applySubscriptionSnapshot([]);

    expect(notifier.state.subscription, isNull);
    expect(notifier.state.subscriptionCachedAt, isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auth_subscription_cached_at'), isNotNull);
    expect(prefs.getString('auth_subscription_owner'), 'cache-user');
  });
}
