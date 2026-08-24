import 'dart:async';
import 'dart:convert';

import 'package:aichat/models/agent.dart';
import 'package:aichat/models/base_memory.dart';
import 'package:aichat/models/long_term_memory.dart';
import 'package:aichat/models/short_term_message.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/providers/chat_provider.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:aichat/providers/memory_provider.dart';
import 'package:aichat/services/api_service.dart';
import 'package:aichat/services/chat_stream_assembler.dart';
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
import 'helpers/offline_auth_service.dart';

Map<String, dynamic> _completionEnvelope({
  String? content,
  String? toolName,
  String? toolArguments,
  String toolCallId = 'call_1',
  String? finishReason,
}) {
  return {
    'code': 0,
    'data': {
      'model': 'deepseek-v4-flash',
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': content,
            if (toolName != null)
              'tool_calls': [
                {
                  'id': toolCallId,
                  'type': 'function',
                  'function': {
                    'name': toolName,
                    'arguments': toolArguments ?? '{}',
                  },
                },
              ],
          },
          'finish_reason':
              finishReason ?? (toolName == null ? 'stop' : 'tool_calls'),
        },
      ],
      'usage': {'prompt_tokens': 12, 'completion_tokens': 7},
      'cost': 0.0,
    },
  };
}

http.StreamedResponse _streamedCompletionResponse({
  String? content,
  String? toolName,
  String? toolArguments,
  String toolCallId = 'call_1',
}) {
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(
        jsonEncode(
          _completionEnvelope(
            content: content,
            toolName: toolName,
            toolArguments: toolArguments,
            toolCallId: toolCallId,
          ),
        ),
      ),
    ),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('extractStreamingMessage', () {
    test('完整 JSON 提取 message', () {
      expect(
        extractStreamingMessage('{"message":"你好","sticker_id":"s1"}'),
        '你好',
      );
    });

    test('半截字符串返回已收到部分', () {
      expect(extractStreamingMessage('{"message":"你好，今天'), '你好，今天');
    });

    test('message 键尚未到达返回空串', () {
      expect(extractStreamingMessage('{"mes'), '');
      expect(extractStreamingMessage(''), '');
    });

    test('无 message 键返回空串', () {
      expect(extractStreamingMessage('{"send_time":"30m","x":1}'), '');
    });

    test('message 不是最后一个字段（后面还有 sticker_id）', () {
      expect(
        extractStreamingMessage('{"message":"hi","sticker_id":"x"}'),
        'hi',
      );
    });

    test('转义引号与反斜杠', () {
      expect(extractStreamingMessage('{"message":"他说\\"你好\\"呢"}'), '他说"你好"呢');
      expect(extractStreamingMessage('{"message":"a\\\\b"}'), 'a\\b');
    });

    test('换行等转义', () {
      expect(extractStreamingMessage('{"message":"a\\nb\\tc"}'), 'a\nb\tc');
    });

    test('末尾半截反斜杠暂不输出', () {
      expect(extractStreamingMessage('{"message":"abc\\'), 'abc');
    });

    test(r'\uXXXX 解码', () {
      expect(extractStreamingMessage('{"message":"\\u4f60\\u597d"}'), '你好');
    });

    test(r'\u 跨分片：不完整部分暂不输出', () {
      expect(extractStreamingMessage('{"message":"A\\u4f'), 'A');
      expect(extractStreamingMessage('{"message":"A\\u'), 'A');
      expect(extractStreamingMessage('{"message":"A\\'), 'A');
    });
  });

  group('ToolCallDeltaAssembler', () {
    test('多 tool call 交错 index 正确归组', () {
      final assembler = ToolCallDeltaAssembler();
      assembler.add(
        const ToolCallDelta(
          index: 0,
          id: 'call_a',
          name: 'chat',
          argumentsDelta: '{"me',
        ),
      );
      assembler.add(
        const ToolCallDelta(
          index: 1,
          id: 'call_b',
          name: 'plan',
          argumentsDelta: '{"send',
        ),
      );
      assembler.add(
        const ToolCallDelta(index: 0, argumentsDelta: 'ssage":"hi"}'),
      );
      assembler.add(
        const ToolCallDelta(index: 1, argumentsDelta: '_time":"30m"}'),
      );

      expect(assembler.callAt(0)!.id, 'call_a');
      expect(assembler.callAt(0)!.name, 'chat');
      expect(assembler.callAt(0)!.arguments, '{"message":"hi"}');
      expect(assembler.callAt(1)!.id, 'call_b');
      expect(assembler.callAt(1)!.name, 'plan');
      expect(assembler.callAt(1)!.arguments, '{"send_time":"30m"}');
      expect(assembler.calls.map((c) => c.index), [0, 1]);
    });
  });

  group('chatCompletion 本地事件', () {
    test('400 参数降级：剥离 tool_choice/thinking 后重试一次', () async {
      final requestBodies = <String>[];
      var callCount = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        callCount++;
        requestBodies.add(await bodyStream.bytesToString());
        if (callCount == 1) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                '{"error":{"message":"does not support tool_choice"}}',
              ),
            ),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        return _streamedCompletionResponse(content: 'ok');
      });
      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'token',
        model: 'deepseek-v4-flash',
        thinkingMode: true,
        requestKind: 'utility',
        localTypingInterval: Duration.zero,
        client: client,
      );

      final events = await service
          .chatCompletionStream(
            messages: const [],
            tools: const [],
            toolChoice: 'required',
          )
          .toList();

      expect(callCount, 2);
      final firstBody = jsonDecode(requestBodies[0]) as Map<String, dynamic>;
      expect(firstBody['tool_choice'], 'required');
      expect(firstBody.containsKey('thinking'), isTrue);
      final retryBody = jsonDecode(requestBodies[1]) as Map<String, dynamic>;
      expect(retryBody.containsKey('tool_choice'), isFalse);
      expect(retryBody.containsKey('thinking'), isFalse);
      expect(retryBody.containsKey('reasoning_effort'), isFalse);
      expect(
        events
            .where((event) => event.type == ChatStreamEventType.content)
            .map((event) => event.contentDelta)
            .join(),
        'ok',
      );
    });
  });

  group('私聊 provider 本地打字路径', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late IsolatedTestDatabase testDatabase;

    setUpAll(() async {
      testDatabase = await IsolatedTestDatabase.open('chat-stream');
    });

    tearDownAll(() => testDatabase.close());

    setUp(() async {
      final db = await DatabaseService.database;
      await db.delete('chat_messages');
      await db.delete('short_term_messages');
      await db.delete('agents');
      await DatabaseService.insertAgent(
        Agent(id: 'agent-a', name: 'A', persona: 'A角色专属人设', isActive: true),
      );
      await DatabaseService.insertAgent(
        Agent(id: 'agent-b', name: 'B', persona: 'B角色专属人设'),
      );
    });

    tearDown(() {
      ApiService.testClient = null;
    });

    Future<ProviderContainer> makeContainer({
      MemoryService? memoryService,
      Map<String, Object> initialPreferences = const {},
      Duration memoryTimeout = const Duration(seconds: 1),
      ScopedMemoryServiceFactory? scopedMemoryServiceFactory,
    }) async {
      SharedPreferences.setMockInitialValues(initialPreferences);
      final container = ProviderContainer(
        overrides: [
          chatMemoryTimeoutProvider.overrideWithValue(memoryTimeout),
          if (scopedMemoryServiceFactory != null)
            scopedMemoryServiceFactoryProvider.overrideWithValue(
              scopedMemoryServiceFactory,
            ),
          memoryServiceProvider.overrideWithValue(
            memoryService ?? _ImmediateMemoryService(),
          ),
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _FakeSecureStorage({
                  SecureSessionStore.jwtKey: 'fake-jwt',
                  SecureSessionStore.apiKey: 'test-key',
                }),
              ),
              authService: OfflineAuthService(),
              realtimeConnection: FakeRealtimeConnection(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).ready;
      for (var attempt = 0; attempt < 20; attempt++) {
        if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(agentProvider).currentAgent?.id, 'agent-a');
      return container;
    }

    test('记忆 AI 阻塞时主聊天回复仍完成并解除 loading', () async {
      var apiCalls = 0;
      final blockedMemoryResponse = Completer<http.StreamedResponse>();
      ApiService.testClient = MockClient.streaming((request, bodyStream) async {
        apiCalls++;
        if (apiCalls > 1) return blockedMemoryResponse.future;
        return _streamedCompletionResponse(
          toolName: 'chat',
          toolArguments: '{"message":"不会被记忆任务卡住"}',
        );
      });

      final container = await makeContainer(
        memoryService: MemoryService(),
        initialPreferences: {'memory_ai_rounds_agent-a': 4},
      );
      final notifier = container.read(chatProvider.notifier);

      final sent = await notifier
          .sendMessage('请回复')
          .timeout(const Duration(seconds: 2));

      expect(sent, isTrue);
      expect(container.read(chatProvider).isLoading, isFalse);
      expect(
        container.read(chatProvider).messages.map((m) => m.content),
        contains('不会被记忆任务卡住'),
      );
      for (var attempt = 0; attempt < 20 && apiCalls < 2; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(apiCalls, 2, reason: '主回复完成后应在后台启动记忆分析');
    });

    test('本地非流式补全遇到 429 时只请求一次', () async {
      var apiCalls = 0;
      ApiService.testClient = MockClient((request) async {
        apiCalls++;
        return http.Response(
          jsonEncode({
            'code': 42900,
            'message': '上游请求过于频繁，请稍后重试',
            'data': null,
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = await makeContainer();
      final sent = await container
          .read(chatProvider.notifier)
          .sendMessage('测试限流')
          .timeout(const Duration(seconds: 2));

      expect(sent, isFalse);
      expect(apiCalls, 1, reason: '本地模拟前失败不得重复请求补全');
      expect(container.read(chatProvider).isLoading, isFalse);
    });

    test('基础记忆读取挂起时降级为无记忆上下文并继续回复', () async {
      ApiService.testClient = _singleReplyClient('基础记忆不可用时仍回复');
      final memoryService = _BlockingBaseMemoryService();
      final container = await makeContainer(
        memoryService: memoryService,
        memoryTimeout: const Duration(milliseconds: 20),
        scopedMemoryServiceFactory:
            ({
              required agentId,
              required shortTermMessages,
              required maxShortTermRounds,
            }) => memoryService,
      );

      final sent = await container
          .read(chatProvider.notifier)
          .sendMessage('请继续')
          .timeout(const Duration(seconds: 1));

      expect(sent, isTrue);
      expect(container.read(chatProvider).isLoading, isFalse);
      expect(
        container.read(chatProvider).messages.map((message) => message.content),
        contains('基础记忆不可用时仍回复'),
      );
    });

    test('记忆压缩挂起时跳过压缩并继续回复', () async {
      ApiService.testClient = _singleReplyClient('压缩不可用时仍回复');
      final memoryService = _BlockingCompressionMemoryService();
      final container = await makeContainer(
        memoryService: memoryService,
        memoryTimeout: const Duration(milliseconds: 20),
        scopedMemoryServiceFactory:
            ({
              required agentId,
              required shortTermMessages,
              required maxShortTermRounds,
            }) => memoryService,
      );

      final sent = await container
          .read(chatProvider.notifier)
          .sendMessage('请继续')
          .timeout(const Duration(seconds: 1));

      expect(sent, isTrue);
      expect(container.read(chatProvider).isLoading, isFalse);
      expect(
        container.read(chatProvider).messages.map((message) => message.content),
        contains('压缩不可用时仍回复'),
      );
    });

    test('切换智能体后仍为发起智能体完成回复并落库', () async {
      var apiCalls = 0;
      ApiService.testClient = MockClient.streaming((request, bodyStream) async {
        apiCalls++;
        return _streamedCompletionResponse(
          toolName: 'chat',
          toolArguments: '{"message":"原会话回复"}',
        );
      });

      final memoryService = _BlockingUserMessageMemoryService();
      final container = await makeContainer(memoryService: memoryService);
      final notifier = container.read(chatProvider.notifier);
      final sending = notifier.sendMessage('切换前发送');
      await memoryService.userMessageStarted.future;

      await container.read(agentProvider.notifier).setActiveAgent('agent-b');
      memoryService.releaseUserMessage();

      expect(await sending, isTrue);
      expect(apiCalls, 1);

      final agentAMessages = await DatabaseService.getChatMessages(
        agentId: 'agent-a',
      );
      final agentBMessages = await DatabaseService.getChatMessages(
        agentId: 'agent-b',
      );
      expect(
        agentAMessages
            .where((row) => row['role'] == 'assistant')
            .map((row) => row['content']),
        contains('原会话回复'),
      );
      expect(
        agentBMessages.where((row) => row['role'] == 'assistant'),
        isEmpty,
      );
    });

    test('重新生成期间切换智能体仍使用发起会话上下文并落库', () async {
      final requestBodies = <String>[];
      var apiCalls = 0;
      ApiService.testClient = MockClient.streaming((request, bodyStream) async {
        apiCalls++;
        requestBodies.add(await bodyStream.bytesToString());
        final reply = apiCalls == 1 ? '首次回复' : '重新生成回复';
        return _streamedCompletionResponse(
          toolName: 'chat',
          toolArguments: jsonEncode({'message': reply}),
          toolCallId: 'call_$apiCalls',
        );
      });

      final gate = _RegenerateMemoryGate();
      final memoryService = _GatedMemoryService(gate);
      final container = await makeContainer(
        memoryService: memoryService,
        scopedMemoryServiceFactory:
            ({
              required agentId,
              required shortTermMessages,
              required maxShortTermRounds,
            }) => _GatedScopedMemoryService(
              gate: gate,
              agentId: agentId,
              shortTermMessages: shortTermMessages,
              maxShortTermRounds: maxShortTermRounds,
            ),
      );
      final notifier = container.read(chatProvider.notifier);
      expect(await notifier.sendMessage('只属于 A 的提问'), isTrue);

      final replyIndex = container
          .read(chatProvider)
          .messages
          .indexWhere((message) => message.content == '首次回复');
      expect(replyIndex, isNonNegative);

      gate.enable();
      final regenerating = notifier.regenerateMessage(replyIndex);
      await gate.started.future.timeout(const Duration(seconds: 1));
      await container.read(agentProvider.notifier).setActiveAgent('agent-b');
      gate.release();
      await regenerating.timeout(const Duration(seconds: 2));

      expect(apiCalls, 2);
      final regenerateBody = jsonDecode(requestBodies[1]);
      final regenerateMessages = jsonEncode(regenerateBody['messages']);
      expect(regenerateMessages, contains('A角色专属人设'));
      expect(regenerateMessages, contains('只属于 A 的提问'));
      expect(regenerateMessages, isNot(contains('B角色专属人设')));

      final agentAMessages = await DatabaseService.getChatMessages(
        agentId: 'agent-a',
      );
      final agentBMessages = await DatabaseService.getChatMessages(
        agentId: 'agent-b',
      );
      expect(
        agentAMessages
            .where((row) => row['role'] == 'assistant')
            .map((row) => row['content']),
        contains('重新生成回复'),
      );
      expect(
        agentAMessages
            .where((row) => row['role'] == 'assistant')
            .map((row) => row['content']),
        isNot(contains('首次回复')),
      );
      expect(agentBMessages, isEmpty);
    });

    test('本地打字增量更新占位消息并最终落库', () async {
      ApiService.testClient = MockClient.streaming((request, bodyStream) async {
        return _streamedCompletionResponse(
          toolName: 'chat',
          toolArguments: '{"message":"你好，世界"}',
        );
      });

      final container = await makeContainer();
      final partials = <String>[];
      container.listen(chatProvider, (_, next) {
        for (final m in next.messages) {
          if (m.isStreaming && m.content.isNotEmpty) {
            if (partials.isEmpty || partials.last != m.content) {
              partials.add(m.content);
            }
          }
        }
      }, fireImmediately: false);

      final notifier = container.read(chatProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMessage('在吗');

      // 本地打字渲染已节流（50ms flush，对齐群聊）：假异步测试时间内中间增量
      // 不保证逐帧出现；观察到的增量必须是最终文本的前缀，且最终完整落库
      for (final p in partials) {
        expect('你好，世界'.startsWith(p), isTrue, reason: '增量 $p 应为最终文本前缀');
      }

      final state = container.read(chatProvider);
      final aiMessages = state.messages.where((m) => m.isAssistant).toList();
      expect(aiMessages, hasLength(1));
      expect(aiMessages.single.content, '你好，世界');
      expect(aiMessages.single.isStreaming, isFalse);
      expect(state.isLoading, isFalse);

      final rows = await DatabaseService.getChatMessages(agentId: 'agent-a');
      expect(
        rows.where((r) => r['role'] == 'assistant').map((r) => r['content']),
        contains('你好，世界'),
      );
    });
  });
}

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

class _BlockingUserMessageMemoryService extends MemoryService {
  final userMessageStarted = Completer<void>();
  final _releaseUserMessage = Completer<void>();
  var _blocked = false;

  void releaseUserMessage() {
    if (!_releaseUserMessage.isCompleted) _releaseUserMessage.complete();
  }

  @override
  Future<ShortTermMessage> addShortTermMessage({
    required String role,
    required String content,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    if (role == 'user' && !_blocked) {
      _blocked = true;
      userMessageStarted.complete();
      await _releaseUserMessage.future;
    }
    return super.addShortTermMessage(
      role: role,
      content: content,
      agentId: agentId,
      imagePath: imagePath,
      imagePaths: imagePaths,
    );
  }
}

MockClient _singleReplyClient(String reply) {
  return MockClient.streaming((request, bodyStream) async {
    return _streamedCompletionResponse(
      toolName: 'chat',
      toolArguments: jsonEncode({'message': reply}),
    );
  });
}

class _BlockingBaseMemoryService extends _ImmediateMemoryService {
  final Completer<List<BaseMemory>> _baseMemories = Completer();

  @override
  Future<int> estimateContextTokens() async => 0;

  @override
  Future<List<LongTermMemory>> getLongTermMemories() async => const [];

  @override
  Future<List<BaseMemory>> getBaseMemories() => _baseMemories.future;
}

class _BlockingCompressionMemoryService extends _ImmediateMemoryService {
  final Completer<List<LongTermMemory>> _compressed = Completer();

  @override
  Future<int> estimateContextTokens() async => 7001;

  @override
  Future<List<LongTermMemory>> compressLongTerm(int keepCount) {
    return _compressed.future;
  }

  @override
  Future<List<LongTermMemory>> getLongTermMemories() async => const [];

  @override
  Future<List<BaseMemory>> getBaseMemories() async => const [];
}

class _RegenerateMemoryGate {
  final started = Completer<void>();
  final _released = Completer<void>();
  var _enabled = false;

  void enable() => _enabled = true;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Future<void> waitIfEnabled() async {
    if (!_enabled) return;
    if (!started.isCompleted) started.complete();
    await _released.future;
  }
}

class _GatedMemoryService extends MemoryService {
  final _RegenerateMemoryGate gate;

  _GatedMemoryService(this.gate);

  @override
  Future<List<BaseMemory>> getBaseMemories() async {
    await gate.waitIfEnabled();
    return super.getBaseMemories();
  }
}

class _GatedScopedMemoryService extends MemoryService {
  final _RegenerateMemoryGate gate;

  _GatedScopedMemoryService({
    required this.gate,
    required super.agentId,
    required super.shortTermMessages,
    required super.maxShortTermRounds,
  }) : super.scoped();

  @override
  Future<List<BaseMemory>> getBaseMemories() async {
    await gate.waitIfEnabled();
    return super.getBaseMemories();
  }
}
