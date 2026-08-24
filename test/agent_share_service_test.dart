import 'dart:convert';

import 'package:aichat/models/agent.dart';
import 'package:aichat/services/agent_share_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final testAgent = Agent(
    name: '小回',
    gender: 'female',
    description: '一个测试智能体',
    persona: '温柔、耐心',
    openingLine: '你好呀',
    avatarColor: 0xFFE8F5E9,
    worldview: '现代都市',
  );

  group('SharedAgentSnapshot round-trip', () {
    test('with avatar base64', () {
      const snapshot = SharedAgentSnapshot(
        name: '小回',
        gender: 'female',
        description: '描述',
        persona: '人设',
        openingLine: '开场白',
        avatarColor: 0xFF112233,
        avatar: 'data:image/png;base64,aGVsbG8=',
        chatBackground: '#FFFFFF',
        worldview: '世界观',
      );

      final restored = SharedAgentSnapshot.fromJson(snapshot.toJson());

      expect(restored.name, snapshot.name);
      expect(restored.gender, snapshot.gender);
      expect(restored.description, snapshot.description);
      expect(restored.persona, snapshot.persona);
      expect(restored.openingLine, snapshot.openingLine);
      expect(restored.avatarColor, snapshot.avatarColor);
      expect(restored.avatar, snapshot.avatar);
      expect(restored.chatBackground, snapshot.chatBackground);
      expect(restored.worldview, snapshot.worldview);
    });

    test('without avatar', () {
      const snapshot = SharedAgentSnapshot(name: '无头像', persona: '人设');

      final restored = SharedAgentSnapshot.fromJson(snapshot.toJson());

      expect(restored.avatar, isNull);
      expect(restored.chatBackground, isNull);
      expect(restored.openingLine, isNull);
      expect(restored.avatarColor, 0xFFE8F5E9);
      expect(restored.worldview, '');
    });

    test('fromJson unwraps export wrapper {version, agent}', () {
      final wrapped = {
        'version': 1,
        'agent': {
          'name': '包装',
          'persona': '人设',
          'avatar_color': 0xFF000001,
        },
      };

      final snapshot = SharedAgentSnapshot.fromJson(wrapped);

      expect(snapshot.name, '包装');
      expect(snapshot.persona, '人设');
      expect(snapshot.avatarColor, 0xFF000001);
    });

    test('toExportData produces importAgent-compatible shape', () {
      const snapshot = SharedAgentSnapshot(name: '导入', persona: '人设');
      final data = snapshot.toExportData();

      expect(data['version'], 1);
      expect(data['agent'], isA<Map<String, dynamic>>());
      expect((data['agent'] as Map)['name'], '导入');
    });
  });

  group('AgentShareService.buildSnapshot', () {
    test('falls back to avatar-less snapshot when avatar file is missing',
        () async {
      final agent = Agent(
        name: '无文件',
        persona: '人设',
        avatarPath: '/nonexistent/path/avatar.png',
        chatBackground: '#AABBCC',
      );

      final data = await AgentShareService.buildSnapshot(agent);

      expect(data['version'], 1);
      final a = data['agent'] as Map<String, dynamic>;
      expect(a['name'], '无文件');
      expect(a['persona'], '人设');
      expect(a['avatar'], isNull);
      expect(a['chat_background'], '#AABBCC');
      expect(a['worldview'], '');
    });
  });

  group('AgentShareService HTTP', () {
    test('createShare posts snapshot and parses code/expires_at', () async {
      Map<String, dynamic>? sentBody;
      String? sentAuth;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/user/share/agent');
        sentAuth = request.headers['authorization'];
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {'code': '123456', 'expires_at': '2026-07-29 12:30:00'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AgentShareService(
        client: client,
        baseUrl: 'https://example.test',
        token: 'jwt-token',
      );

      final result = await service.createShare(testAgent);

      expect(result.code, '123456');
      expect(result.expiresAt, '2026-07-29 12:30:00');
      expect(result.expiresAtParsed, isNotNull);
      expect(sentAuth, 'Bearer jwt-token');
      expect(sentBody!['version'], 1);
      final a = sentBody!['agent'] as Map<String, dynamic>;
      expect(a['name'], '小回');
      expect(a['persona'], '温柔、耐心');
      expect(a['worldview'], '现代都市');
      // 无头像文件时 avatar 为 null，不抛异常
      expect(a['avatar'], isNull);
    });

    test('createShare surfaces server error message', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 500, 'message': '分享功能维护中'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AgentShareService(
        client: client,
        baseUrl: 'https://example.test',
        token: 'jwt-token',
      );

      expect(
        () => service.createShare(testAgent),
        throwsA(
          isA<AgentShareException>()
              .having((e) => e.message, 'message', '分享功能维护中'),
        ),
      );
    });

    test('redeemShare posts code and parses agent snapshot', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/user/share/redeem');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['code'], '654321');
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'agent': {
                'name': '兑换来的',
                'gender': '',
                'description': '描述',
                'persona': '人设',
                'opening_line': '你好',
                'avatar_color': 0xFFE8F5E9,
                'avatar': 'data:image/jpeg;base64,aGVsbG8=',
                'chat_background': null,
                'worldview': '异世界',
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AgentShareService(
        client: client,
        baseUrl: 'https://example.test',
        token: 'jwt-token',
      );

      final snapshot = await service.redeemShare('654321');

      expect(snapshot.name, '兑换来的');
      expect(snapshot.persona, '人设');
      expect(snapshot.openingLine, '你好');
      expect(snapshot.avatar, 'data:image/jpeg;base64,aGVsbG8=');
      expect(snapshot.chatBackground, isNull);
      expect(snapshot.worldview, '异世界');
    });

    test('redeemShare surfaces invalid/expired code error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 404, 'message': '分享码无效或已过期'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AgentShareService(
        client: client,
        baseUrl: 'https://example.test',
        token: 'jwt-token',
      );

      expect(
        () => service.redeemShare('000000'),
        throwsA(
          isA<AgentShareException>()
              .having((e) => e.message, 'message', '分享码无效或已过期'),
        ),
      );
    });

    test('401 marks exception as unauthorized', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 401, 'message': 'unauthorized'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AgentShareService(
        client: client,
        baseUrl: 'https://example.test',
        token: 'expired',
      );

      expect(
        () => service.redeemShare('123456'),
        throwsA(
          isA<AgentShareException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue),
        ),
      );
    });
  });
}
