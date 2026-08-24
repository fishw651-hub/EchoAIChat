import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aichat/services/quota_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主动关心使用服务端一次性 claim', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request captured;
    final service = QuotaService.forTesting(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'claim_token': 'claim-1'},
          }),
          200,
        );
      }),
    );

    expect(await service.claimProactiveCare('agent-1'), 'claim-1');
    expect(captured.url.path, '/api/v1/quota/proactive/claim');
    expect(jsonDecode(captured.body), {'client_agent_id': 'agent-1'});
  });

  test('短时间内重复打开订阅中心会复用配额快照', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final service = QuotaService.forTesting(
      baseUrl: 'https://example.test',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'ocr': {
                'used': 1,
                'quota': 3,
                'remaining': 2,
                'unlimited': false,
              },
              'real_reply': {
                'used': 2,
                'quota': 5,
                'remaining': 3,
                'unlimited': false,
              },
              'reset_date': '2026-08-16',
              'subscriptions': [],
            },
          }),
          200,
        );
      }),
    );

    await service.getUsage(cacheMaxAge: const Duration(minutes: 1));
    await service.getUsage(cacheMaxAge: const Duration(minutes: 1));

    expect(calls, 1);
  });

  test('切换账号后不会复用上一个账号的配额快照', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    var owner = 'alice';
    final service = QuotaService.forTesting(
      baseUrl: 'https://example.test',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'ocr': {
                'used': calls,
                'quota': 3,
                'remaining': 3 - calls,
                'unlimited': false,
              },
              'real_reply': {
                'used': 0,
                'quota': 5,
                'remaining': 5,
                'unlimited': false,
              },
              'reset_date': '2026-08-16',
              'subscriptions': [],
            },
          }),
          200,
        );
      }),
    )..cacheOwnerProvider = () => owner;

    final alice = await service.getUsage(
      cacheMaxAge: const Duration(minutes: 1),
    );
    owner = 'bob';
    final bob = await service.getUsage(cacheMaxAge: const Duration(minutes: 1));

    expect(calls, 2);
    expect(alice.ocr.used, 1);
    expect(bob.ocr.used, 2);
  });
}
