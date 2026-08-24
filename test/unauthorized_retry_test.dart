import 'dart:async';
import 'dart:convert';

import 'package:aichat/models/agent.dart';
import 'package:aichat/models/short_term_message.dart';
import 'package:aichat/models/user_profile.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/providers/chat_provider.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:aichat/providers/memory_provider.dart';
import 'package:aichat/services/api_service.dart';
import 'package:aichat/services/auth_service.dart';
import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_realtime_connection.dart';
import 'helpers/isolated_test_database.dart';

// ═══ 通用辅助 ═══

Map<String, dynamic> _okChatBody(String text) => {
  'code': 0,
  'data': {
    'choices': [
      {
        'message': {
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'chat',
                'arguments': jsonEncode({'message': text}),
              },
            },
          ],
        },
        'finish_reason': 'tool_calls',
      },
    ],
  },
};

class _FakeSecureStorage implements SecureStorageBackend {
  final Map<String, String> values;
  _FakeSecureStorage(this.values);

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _ImmediateMemoryService extends MemoryService {
  @override
  Future<void> loadShortTermFromDb(int limit) async {}

  @override
  Future<ShortTermMessage> addShortTermMessage({
    required String role,
    required String content,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    return ShortTermMessage(
      id: 'immediate-${DateTime.now().microsecondsSinceEpoch}',
      role: role,
      content: content,
      agentId: agentId ?? this.agentId,
      imagePath: imagePath,
      imagePaths: imagePaths,
    );
  }
}

/// 可计数的假 AuthService：refresh / login 成功，其余用户接口返回空数据。
class _FakeAuthService extends AuthService {
  int refreshCalls = 0;
  int loginCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshTokenApi(String refreshToken) async {
    refreshCalls++;
    // 人为拉长，确保并发测试里第二次调用到达时第一次尚未完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return {'token': 'refreshed-jwt', 'refresh_token': 'refreshed-refresh'};
  }

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    loginCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return {
      'token': 'login-jwt',
      'refresh_token': 'login-refresh',
      'id': 1,
      'username': username,
    };
  }

  @override
  Future<Map<String, dynamic>> registerCurrentDevice() async => {};

  @override
  Future<UserProfile> getCurrentUser() async => UserProfile(
    id: 1,
    uuid: 'uuid',
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

  @override
  Future<List<Map<String, dynamic>>> fetchMyAgents() async => [];

  @override
  Future<Map<String, dynamic>> refreshDailyAllowance() async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.onUnauthorizedRetry = null;
    ApiService.apiKeyProvider = null;
  });

  tearDown(() {
    ApiService.onUnauthorizedRetry = null;
    ApiService.apiKeyProvider = null;
    ApiService.testClient = null;
  });

  group('ApiService 401 静默重登重发', () {
    test('40100 分支：重登成功后用新 token 重发并返回结果', () async {
      final authHeaders = <String?>[];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        authHeaders.add(request.headers['Authorization']);
        if (calls == 1) {
          return http.Response(
            jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(_okChatBody('重发成功')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      var reAuthCalls = 0;
      ApiService.onUnauthorizedRetry = () async {
        reAuthCalls++;
        return true;
      };
      ApiService.apiKeyProvider = () => 'new-key';

      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      final result = await service.chatCompletion(
        messages: const [],
        tools: const [],
      );

      expect(calls, 2);
      expect(reAuthCalls, 1);
      expect(authHeaders[0], 'Bearer old-key');
      expect(authHeaders[1], 'Bearer new-key');
      final toolCalls = ApiService.parseToolCalls(result);
      expect(toolCalls.single['name'], 'chat');
      expect((toolCalls.single['arguments'] as Map)['message'], '重发成功');
    });

    test('HTTP 401（无 envelope）分支同样触发重发', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('unauthorized', 401);
        }
        return http.Response(
          jsonEncode(_okChatBody('ok')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.onUnauthorizedRetry = () async => true;
      ApiService.apiKeyProvider = () => 'new-key';

      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      await service.chatCompletion(messages: const [], tools: const []);
      expect(calls, 2);
    });

    test('重登失败：抛原 ApiException 且不重发', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.onUnauthorizedRetry = () async => false;

      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      await expectLater(
        service.chatCompletion(messages: const [], tools: const []),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(calls, 1);
    });

    test('重登成功但服务端持续 401：只重试一次', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.onUnauthorizedRetry = () async => true;
      ApiService.apiKeyProvider = () => 'new-key';

      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      await expectLater(
        service.chatCompletion(messages: const [], tools: const []),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(calls, 2);
    });

    test('回调为空：按原样抛 401', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      await expectLater(
        service.chatCompletion(messages: const [], tools: const []),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('流式 401：重登成功后重发并流出事件', () async {
      final authHeaders = <String?>[];
      var calls = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        calls++;
        authHeaders.add(request.headers['Authorization']);
        if (calls == 1) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
              ),
            ),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '流式重发成功'},
                  },
                ],
              })}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      ApiService.onUnauthorizedRetry = () async => true;
      ApiService.apiKeyProvider = () => 'new-key';

      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );
      final events = await service
          .chatCompletionStream(messages: const [], tools: const [])
          .toList();

      expect(calls, 2);
      expect(authHeaders[1], 'Bearer new-key');
      expect(events.first.type, ChatStreamEventType.content);
      expect(events.first.contentDelta, '流式重发成功');
    });
  });

  group('trySilentReAuth 并发锁', () {
    test('并发多个 401 只重登一次，其余等待同一结果', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = _FakeAuthService();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  SecureSessionStore.jwtKey: 'old-jwt',
                  SecureSessionStore.refreshKey: 'old-refresh',
                  SecureSessionStore.apiKey: 'old-key',
                }),
              ),
              authService: fakeAuth,
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).ready;

      final notifier = container.read(authProvider.notifier);
      final results = await Future.wait([
        notifier.trySilentReAuth(),
        notifier.trySilentReAuth(),
        notifier.trySilentReAuth(),
      ]);

      expect(results, [true, true, true]);
      expect(fakeAuth.refreshCalls, 1);
      expect(container.read(authProvider).jwtToken, 'refreshed-jwt');
    });

    test('refresh 与凭据都不可用：返回 false 并标记会话过期', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = _FakeAuthService();
      var sessionExpiredNotified = false;
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  SecureSessionStore.jwtKey: 'old-jwt',
                }),
              ),
              authService: fakeAuth,
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(authProvider.notifier);
      notifier.onSessionExpired = () => sessionExpiredNotified = true;
      await notifier.ready;

      final ok = await notifier.trySilentReAuth();

      expect(ok, isFalse);
      expect(container.read(authProvider).sessionExpired, isTrue);
      expect(sessionExpiredNotified, isTrue);
      expect(fakeAuth.refreshCalls, 0);
      expect(fakeAuth.loginCalls, 0);
    });

    test('并发两个 ApiService 请求同时 401：底层只重登一次', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = _FakeAuthService();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  SecureSessionStore.jwtKey: 'old-jwt',
                  SecureSessionStore.refreshKey: 'old-refresh',
                  SecureSessionStore.apiKey: 'old-key',
                }),
              ),
              authService: fakeAuth,
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).ready;

      ApiService.onUnauthorizedRetry = () =>
          container.read(authProvider.notifier).trySilentReAuth();
      ApiService.apiKeyProvider = () => container.read(authProvider).apiKey;

      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls <= 2) {
          return http.Response(
            jsonEncode({'code': 40100, 'message': '登录已过期，请重新登录'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(_okChatBody('ok')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      ApiService makeService() => ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'old-key',
        model: 'deepseek-v4-flash',
        client: client,
      );

      final results = await Future.wait([
        makeService().chatCompletion(messages: const [], tools: const []),
        makeService().chatCompletion(messages: const [], tools: const []),
      ]);

      expect(results, hasLength(2));
      expect(fakeAuth.refreshCalls, 1);
    });
  });

  group('chat_provider 本地预检静默重登', () {
    late IsolatedTestDatabase testDatabase;

    setUpAll(() async {
      testDatabase = await IsolatedTestDatabase.open('unauthorized-retry');
    });

    tearDownAll(() => testDatabase.close());

    setUp(() async {
      final db = await DatabaseService.database;
      await db.delete('chat_messages');
      await db.delete('short_term_messages');
      await db.delete('agents');
      await DatabaseService.insertAgent(
        Agent(id: 'agent-a', name: 'A', persona: 'A', isActive: true),
      );
    });

    test('apiKey 为空：静默重登成功后继续发送', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = _FakeAuthService();
      final container = ProviderContainer(
        overrides: [
          memoryServiceProvider.overrideWithValue(_ImmediateMemoryService()),
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  // 有 jwt + 凭据，但没有 apiKey、没有 refresh token
                  SecureSessionStore.jwtKey: 'old-jwt',
                  SecureSessionStore.usernameKey: 'tester',
                  SecureSessionStore.passwordKey: 'secret',
                }),
              ),
              authService: fakeAuth,
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).ready;
      expect(container.read(authProvider).apiKey, isNull);

      for (var attempt = 0; attempt < 20; attempt++) {
        if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(agentProvider).currentAgent?.id, 'agent-a');

      final authHeaders = <String?>[];
      ApiService.testClient = MockClient.streaming((request, bodyStream) async {
        authHeaders.add(request.headers['Authorization']);
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_1',
                          'type': 'function',
                          'function': {'name': 'chat', 'arguments': '{"message":"恢复成功"}'},
                        },
                      ],
                    },
                  },
                ],
              })}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final notifier = container.read(chatProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMessage('在吗');

      // 静默重登（凭据 fallback 登录）执行了一次，登录后 apiKey 恢复
      expect(fakeAuth.loginCalls, 1);
      expect(container.read(authProvider).apiKey, 'login-jwt');

      final state = container.read(chatProvider);
      final aiMessages = state.messages.where((m) => m.isAssistant).toList();
      expect(aiMessages, hasLength(1));
      expect(aiMessages.single.content, '恢复成功');
      expect(state.error, isNull);
      // 发送用的是重登后的新 token（login-jwt 即新 apiKey）
      expect(authHeaders.single, 'Bearer login-jwt');
    });

    test('apiKey 为空且静默重登失败：置错请先登录账户', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = _FakeAuthService();
      var sessionExpiredNotified = false;
      final container = ProviderContainer(
        overrides: [
          memoryServiceProvider.overrideWithValue(_ImmediateMemoryService()),
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  // 只有 jwt，没有 refresh token、没有凭据 → 重登必失败
                  SecureSessionStore.jwtKey: 'old-jwt',
                }),
              ),
              authService: fakeAuth,
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final authNotifier = container.read(authProvider.notifier);
      authNotifier.onSessionExpired = () => sessionExpiredNotified = true;
      await authNotifier.ready;

      for (var attempt = 0; attempt < 20; attempt++) {
        if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final notifier = container.read(chatProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMessage('在吗');

      expect(container.read(chatProvider).error, '请先登录账户');
      expect(sessionExpiredNotified, isTrue);
      expect(
        container.read(chatProvider).messages.where((m) => m.isAssistant),
        isEmpty,
      );
    });
  });
}
