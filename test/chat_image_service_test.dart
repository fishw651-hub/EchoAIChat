import 'dart:convert';

import 'package:aichat/services/api_service.dart';
import 'package:aichat/services/chat_image_service.dart';
import 'package:aichat/services/vision_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ChatImageService.readImageBase64', () {
    test('读取成功返回 base64 编码', () async {
      final service = ChatImageService(
        readBytes: (_) async => utf8.encode('fake-image'),
      );
      expect(
        await service.readImageBase64('/tmp/a.jpg'),
        base64Encode(utf8.encode('fake-image')),
      );
    });

    test('读取失败返回 null（调用方降级 [图片] 占位）', () async {
      final service = ChatImageService(
        readBytes: (_) => throw Exception('file missing'),
      );
      expect(await service.readImageBase64('/tmp/missing.jpg'), isNull);
    });
  });

  group('ChatImageService.describeImage', () {
    test('正常路径：返回裁剪后的描述，请求带系统提示词与 base64 图片', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '  一只橘猫趴在窗台上晒太阳  '},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ChatImageService(
        readBytes: (_) async => utf8.encode('jpeg-bytes'),
        apiFactory: ({required model, required apiKey, required baseUrl}) =>
            ApiService(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              client: client,
            ),
      );

      final description = await service.describeImage(
        visionModelId: 'vision-x',
        apiKey: 'key',
        baseUrl: 'https://example.test',
        userText: '看这只猫',
        imagePath: '/tmp/cat.jpg',
      );

      expect(description, '一只橘猫趴在窗台上晒太阳');

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['model'], 'vision-x');
      expect(body['tool_choice'], 'none');
      final messages = body['messages'] as List<dynamic>;
      expect(
        (messages[0] as Map)['content'],
        VisionMessageBuilder.describeSystemPrompt,
      );
      final userContent = (messages[1] as Map)['content'] as List<dynamic>;
      expect((userContent[0] as Map)['text'], '看这只猫');
      expect(
        (userContent[1] as Map)['image_url']['url'],
        'data:image/jpeg;base64,${base64Encode(utf8.encode('jpeg-bytes'))}',
      );
    });

    test('用户无文字时 text 部分用默认引导语', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '描述'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ChatImageService(
        readBytes: (_) async => [1, 2, 3],
        apiFactory: ({required model, required apiKey, required baseUrl}) =>
            ApiService(baseUrl: baseUrl, apiKey: apiKey, model: model, client: client),
      );
      await service.describeImage(
        visionModelId: 'vision-x',
        apiKey: 'key',
        baseUrl: 'https://example.test',
        userText: '',
        imagePath: '/tmp/a.jpg',
      );
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final userContent =
          ((body['messages'] as List)[1] as Map)['content'] as List<dynamic>;
      expect((userContent[0] as Map)['text'], '请描述这张图片。');
    });

    test('视觉模型返回空内容时抛 ApiException', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '   '},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ChatImageService(
        readBytes: (_) async => [1],
        apiFactory: ({required model, required apiKey, required baseUrl}) =>
            ApiService(baseUrl: baseUrl, apiKey: apiKey, model: model, client: client),
      );
      expect(
        () => service.describeImage(
          visionModelId: 'vision-x',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          userText: '',
          imagePath: '/tmp/a.jpg',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.toString(),
            'message',
            contains('图片识别失败'),
          ),
        ),
      );
    });

    test('图片读取失败时异常上抛（不静默吞）', () {
      final service = ChatImageService(
        readBytes: (_) => throw Exception('io error'),
      );
      expect(
        () => service.describeImage(
          visionModelId: 'vision-x',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          userText: '',
          imagePath: '/tmp/broken.jpg',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ChatImageService.describeImages 多图', () {
    test('逐张串行描述并按序返回', () async {
      final requestedUrls = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final content =
            ((body['messages'] as List)[1] as Map)['content'] as List<dynamic>;
        requestedUrls.add((content[1] as Map)['image_url']['url'] as String);
        // 按图片字节区分描述
        final isFirst = requestedUrls.last.contains(
          base64Encode(utf8.encode('img-1')),
        );
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': isFirst ? '描述一' : '描述二'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ChatImageService(
        readBytes: (path) async =>
            utf8.encode(path.endsWith('1.jpg') ? 'img-1' : 'img-2'),
        apiFactory: ({required model, required apiKey, required baseUrl}) =>
            ApiService(baseUrl: baseUrl, apiKey: apiKey, model: model, client: client),
      );

      final descriptions = await service.describeImages(
        visionModelId: 'vision-x',
        apiKey: 'key',
        baseUrl: 'https://example.test',
        userText: '',
        imagePaths: ['/tmp/1.jpg', '/tmp/2.jpg'],
      );

      expect(descriptions, ['描述一', '描述二']);
      expect(requestedUrls.length, 2);
    });

    test('任一张失败整体抛异常', () async {
      var apiCalled = false;
      final client = MockClient((request) async {
        apiCalled = true;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '描述一'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ChatImageService(
        readBytes: (path) async =>
            path.endsWith('bad.jpg') ? throw Exception('io error') : [1],
        apiFactory: ({required model, required apiKey, required baseUrl}) =>
            ApiService(baseUrl: baseUrl, apiKey: apiKey, model: model, client: client),
      );
      await expectLater(
        () => service.describeImages(
          visionModelId: 'vision-x',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          userText: '',
          imagePaths: ['/tmp/ok.jpg', '/tmp/bad.jpg'],
        ),
        throwsA(isA<Exception>()),
      );
      // 第一张成功调用过视觉 API，第二张 IO 失败即整体抛出
      expect(apiCalled, isTrue);
    });
  });
}
