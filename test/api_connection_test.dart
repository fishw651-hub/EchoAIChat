import 'dart:convert';

import 'package:aichat/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    ApiService.testClient = null;
  });

  test('连接测试只校验鉴权和可用模型，不调用计费聊天接口', () async {
    final requests = <http.Request>[];
    ApiService.testClient = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/v1/user/profile':
          return http.Response(
            jsonEncode({'code': 0, 'message': 'success', 'data': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/api/v1/models':
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'success',
              'data': {
                'models': [
                  {'id': 'grok-4.6', 'name': 'grok-4.6'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });

    final result = await ApiService.testConnection(
      baseUrl: 'http://127.0.0.1:9',
      apiKey: 'test-token',
    );

    expect(result, '连接成功');
    expect(requests.map((request) => request.url.path), [
      '/api/v1/user/profile',
      '/api/v1/models',
    ]);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(requests.first.headers['Authorization'], 'Bearer test-token');
    expect(
      requests.any((request) => request.url.path.contains('chat/completions')),
      isFalse,
    );
  });

  test('连接测试在鉴权失败后不再请求模型列表', () async {
    var requestCount = 0;
    ApiService.testClient = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({'code': 40100, 'message': '未授权'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await ApiService.testConnection(
      baseUrl: 'https://example.test',
      apiKey: 'expired-token',
    );

    expect(result, 'API Key 无效或无权限');
    expect(requestCount, 1);
  });

  test('连接测试可校验指定模型是否仍然可用', () async {
    ApiService.testClient = MockClient((request) async {
      if (request.url.path == '/api/v1/user/profile') {
        return http.Response(jsonEncode({'code': 0, 'data': {}}), 200);
      }
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'models': [
              {'id': 'grok-4.6'},
            ],
          },
        }),
        200,
      );
    });

    final result = await ApiService.testConnection(
      baseUrl: 'https://example.test',
      apiKey: 'test-token',
      model: 'deepseek-v4-flash',
    );

    expect(result, '连接失败: 模型 deepseek-v4-flash 当前不可用');
  });
}
