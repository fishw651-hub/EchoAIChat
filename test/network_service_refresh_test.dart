import 'dart:convert';

import 'package:aichat/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NetworkService market refresh', () {
    tearDown(() {
      NetworkService.testClient = null;
    });

    test('forceRefresh bypasses cached agent lists', () async {
      http.BaseRequest? capturedRequest;
      NetworkService.testClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'list': <Map<String, dynamic>>[], 'total': 0},
          }),
          200,
        );
      });

      await NetworkService().listAgents(forceRefresh: true);

      final request = capturedRequest;
      expect(request, isNotNull);
      expect(request!.headers['cache-control'], 'no-cache');
      expect(request.url.queryParameters.containsKey('_refresh'), isTrue);
    });
  });
}
