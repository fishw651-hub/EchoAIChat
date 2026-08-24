import 'dart:convert';

import 'package:aichat/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    ApiService.ensureClientAgentRegistered = null;
  });

  test(
    'ApiService routes repeated requests through the injected client',
    () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'choices': [
                {
                  'message': {'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ApiService(
        baseUrl: 'https://example.test',
        apiKey: 'token',
        model: 'deepseek-v4-flash',
        client: client,
      );

      await service.chatCompletion(messages: const [], tools: const []);
      await service.chatCompletion(messages: const [], tools: const []);

      expect(requestCount, 2);
    },
  );

  test('聊天请求在发出前登记智能体且同一实例只登记一次', () async {
    final events = <String>[];
    ApiService.ensureClientAgentRegistered = (clientAgentId) async {
      events.add('register:$clientAgentId');
    };
    final client = MockClient((request) async {
      events.add('post');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'choices': [
              {
                'message': {'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = ApiService(
      baseUrl: 'https://example.test',
      apiKey: 'token',
      model: 'deepseek-v4-flash',
      clientAgentId: 'agent-a',
      client: client,
    );

    await service.chatCompletion(messages: const [], tools: const []);
    await service.chatCompletion(messages: const [], tools: const []);

    expect(events, ['register:agent-a', 'post', 'post']);
  });
}
