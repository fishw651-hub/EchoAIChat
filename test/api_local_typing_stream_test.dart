import 'dart:convert';

import 'package:aichat/services/api_service.dart';
import 'package:aichat/services/chat_stream_assembler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _successData({
  String? content,
  List<Map<String, dynamic>> toolCalls = const [],
  String finishReason = 'stop',
}) {
  return {
    'code': 0,
    'message': 'success',
    'data': {
      'id': 'completion-1',
      'model': 'grok4.5',
      'choices': [
        {
          'index': 0,
          'message': {
            'role': 'assistant',
            'content': content,
            if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
          },
          'finish_reason': finishReason,
        },
      ],
      'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
      'cost': 0.001,
    },
  };
}

ApiService _service(
  http.Client client, {
  bool thinkingMode = false,
  Duration? chatRequestTimeout,
}) {
  return ApiService(
    baseUrl: 'https://example.test',
    apiKey: 'token',
    model: 'grok4.5',
    thinkingMode: thinkingMode,
    requestKind: 'utility',
    localTypingInterval: Duration.zero,
    client: client,
    chatRequestTimeout: chatRequestTimeout ?? const Duration(seconds: 180),
  );
}

void main() {
  test('默认聊天请求总时限为 180 秒', () {
    expect(ApiService.defaultChatRequestTimeout, const Duration(seconds: 180));
  });

  test('客户端超时只发出一次请求', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response('{}', 200);
    });
    final service = _service(
      client,
      chatRequestTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      service.chatCompletion(messages: const [], tools: const []),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('请求超时'),
        ),
      ),
    );
    expect(calls, 1);
  });

  group('本地非流式打字事件', () {
    test('请求非流式路径并按顺序生成完整文本事件', () async {
      late Uri requestedUri;
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        requestedUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(_successData(content: '你好，世界')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final events = await _service(
        client,
      ).chatCompletionStream(messages: const [], tools: const []).toList();

      expect(requestedUri.path, '/api/v1/chat/completions');
      expect(requestBody['stream'], isNot(true));
      final content = events
          .where((event) => event.type == ChatStreamEventType.content)
          .map((event) => event.contentDelta)
          .join();
      expect(content, '你好，世界');
      expect(
        events.map((event) => event.type).toList().sublist(events.length - 4),
        [
          ChatStreamEventType.finish,
          ChatStreamEventType.usage,
          ChatStreamEventType.cost,
          ChatStreamEventType.done,
        ],
      );
    });

    test('chat 工具参数渐进生成并可完整重组', () async {
      const arguments = '{"message":"你好👨‍👩‍👧‍👦","sticker_id":""}';
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            _successData(
              finishReason: 'tool_calls',
              toolCalls: const [
                {
                  'id': 'call-1',
                  'type': 'function',
                  'function': {'name': 'chat', 'arguments': arguments},
                },
              ],
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final events = await _service(
        client,
      ).chatCompletionStream(messages: const [], tools: const []).toList();
      final toolEvents = events
          .where((event) => event.type == ChatStreamEventType.toolCall)
          .toList();
      final assembler = ToolCallDeltaAssembler();
      for (final event in toolEvents) {
        assembler.add(
          ToolCallDelta(
            index: event.toolCallIndex!,
            id: event.toolCallId,
            name: event.toolCallName,
            argumentsDelta: event.argumentsDelta,
          ),
        );
      }

      expect(toolEvents.length, greaterThan(1));
      expect(assembler.callAt(0)?.id, 'call-1');
      expect(assembler.callAt(0)?.name, 'chat');
      expect(assembler.callAt(0)?.arguments, arguments);
    });

    test('chatgroup 工具参数渐进生成并可完整重组', () async {
      const arguments = '{"message":"群聊渐进文本"}';
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            _successData(
              finishReason: 'tool_calls',
              toolCalls: const [
                {
                  'id': 'call-group',
                  'type': 'function',
                  'function': {'name': 'chatgroup', 'arguments': arguments},
                },
              ],
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final events = await _service(
        client,
      ).chatCompletionStream(messages: const [], tools: const []).toList();
      final toolEvents = events
          .where((event) => event.type == ChatStreamEventType.toolCall)
          .toList();
      final assembler = ToolCallDeltaAssembler();
      for (final event in toolEvents) {
        assembler.add(
          ToolCallDelta(
            index: event.toolCallIndex!,
            id: event.toolCallId,
            name: event.toolCallName,
            argumentsDelta: event.argumentsDelta,
          ),
        );
      }

      expect(toolEvents.length, greaterThan(1));
      expect(assembler.callAt(0)?.id, 'call-group');
      expect(assembler.callAt(0)?.name, 'chatgroup');
      expect(assembler.callAt(0)?.arguments, arguments);
    });

    test('不可见工具参数一次生成', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(
            _successData(
              finishReason: 'tool_calls',
              toolCalls: const [
                {
                  'id': 'call-plan',
                  'type': 'function',
                  'function': {
                    'name': 'plan',
                    'arguments': '{"send_time":"30m"}',
                  },
                },
              ],
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final events = await _service(
        client,
      ).chatCompletionStream(messages: const [], tools: const []).toList();

      expect(
        events.where((event) => event.type == ChatStreamEventType.toolCall),
        hasLength(1),
      );
    });

    test('429 不触发本地动画回退请求', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
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

      await expectLater(
        _service(
          client,
          thinkingMode: true,
        ).chatCompletionStream(messages: const [], tools: const []).toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            429,
          ),
        ),
      );
      expect(calls, 1);
    });
  });
}
