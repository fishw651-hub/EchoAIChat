import 'package:aichat/services/vision_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisionMessageBuilder.buildNativeContent', () {
    test('生成 text + image_url 数组型 content', () {
      final content = VisionMessageBuilder.buildNativeContent(
        userText: '看这张',
        base64Jpeg: 'QUJD',
      );

      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': '看这张'});
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url'],
        {'url': 'data:image/jpeg;base64,QUJD'},
      );
    });

    test('用户文字为空时 text 用 [图片] 占位', () {
      final content = VisionMessageBuilder.buildNativeContent(
        userText: '',
        base64Jpeg: 'QUJD',
      );

      expect(content[0]['text'], VisionMessageBuilder.imagePlaceholder);
    });
  });

  group('VisionMessageBuilder.composeDescribedContent', () {
    test('无用户文字时仅输出图片描述标记', () {
      final composed = VisionMessageBuilder.composeDescribedContent(
        userText: '',
        description: '一只猫在桌上',
      );

      expect(composed, '[用户发送了一张图片，图片内容：一只猫在桌上]');
    });

    test('有用户文字时拼接在描述标记之前', () {
      final composed = VisionMessageBuilder.composeDescribedContent(
        userText: '这是我家猫',
        description: '一只猫在桌上',
      );

      expect(composed, '这是我家猫\n[用户发送了一张图片，图片内容：一只猫在桌上]');
    });
  });

  group('VisionMessageBuilder.buildDescribeMessages', () {
    test('系统提示词强制详细描述 + 带图 user 消息', () {
      final messages = VisionMessageBuilder.buildDescribeMessages(
        userText: '',
        base64Jpeg: 'QUJD',
      );

      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      final prompt = messages[0]['content'] as String;
      expect(prompt, contains('视觉描述助手'));
      expect(prompt, contains('不要遗漏重要细节'));

      expect(messages[1]['role'], 'user');
      final content = messages[1]['content'] as List<Map<String, dynamic>>;
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url'],
        {'url': 'data:image/jpeg;base64,QUJD'},
      );
    });

    test('用户文字透传到描述请求', () {
      final messages = VisionMessageBuilder.buildDescribeMessages(
        userText: '图上写了什么？',
        base64Jpeg: 'QUJD',
      );

      final content = messages[1]['content'] as List<Map<String, dynamic>>;
      expect(content[0]['text'], '图上写了什么？');
    });
  });

  group('VisionMessageBuilder.historyPlaceholder', () {
    test('空文字时为 [图片]', () {
      expect(
        VisionMessageBuilder.historyPlaceholder(''),
        VisionMessageBuilder.imagePlaceholder,
      );
    });

    test('有文字时追加 [图片] 占位', () {
      expect(VisionMessageBuilder.historyPlaceholder('看'), '看\n[图片]');
    });
  });

  group('VisionMessageBuilder.attachImagesToMessages', () {
    Future<String?> fakeReader(String path) async => 'b64-$path';

    test('非原生视觉模型：剥离 image_path 键且内容原样不动', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {'role': 'user', 'content': '看图\n[图片]', 'image_path': '/a.jpg'},
          {'role': 'assistant', 'content': '好'},
        ],
        nativeVision: false,
        readImageBase64: fakeReader,
      );

      expect(result[0], {'role': 'user', 'content': '看图\n[图片]'});
      expect(result[1], {'role': 'assistant', 'content': '好'});
    });

    test('原生视觉：带图消息变数组型 content，尾部 [图片] 占位被移除', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {'role': 'user', 'content': '看这张\n[图片]', 'image_path': '/a.jpg'},
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content[0], {'type': 'text', 'text': '看这张'});
      expect(content[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/a.jpg',
      });
      expect(result[0].containsKey('image_path'), isFalse);
    });

    test('文本仅为 [图片] 时挂图后 text 部分仍用占位（buildNativeContent 回退）', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {'role': 'user', 'content': '[图片]', 'image_path': '/a.jpg'},
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content[0]['text'], VisionMessageBuilder.imagePlaceholder);
      expect(content, hasLength(2));
    });

    test('最多挂最近 3 张，更早的图片消息保持 [图片] 文本占位', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          for (var i = 1; i <= 5; i++)
            {'role': 'user', 'content': '图$i\n[图片]', 'image_path': '/$i.jpg'},
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      // 最早的 2 张保持文本占位
      expect(result[0]['content'], '图1\n[图片]');
      expect(result[1]['content'], '图2\n[图片]');
      // 最近 3 张挂图
      for (var i = 2; i < 5; i++) {
        final content = result[i]['content'] as List<Map<String, dynamic>>;
        expect(content[0]['text'], '图${i + 1}');
        expect(
          content[1]['image_url'],
          {'url': 'data:image/jpeg;base64,b64-/${i + 1}.jpg'},
        );
      }
    });

    test('文件读取失败（reader 返回 null）降级为原文本占位', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {'role': 'user', 'content': '[图片]', 'image_path': '/missing.jpg'},
        ],
        nativeVision: true,
        readImageBase64: (_) async => null,
      );

      expect(result[0], {'role': 'user', 'content': '[图片]'});
    });

    test('readImageBase64 为 null 时不挂图（防御）', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {'role': 'user', 'content': '[图片]', 'image_path': '/a.jpg'},
        ],
        nativeVision: true,
      );

      expect(result[0], {'role': 'user', 'content': '[图片]'});
    });

    test('多图消息（image_paths 列表）：一条消息挂多张，图片键全部剥离', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '看这些\n[图片]',
            'image_path': '/a.jpg',
            'image_paths': ['/a.jpg', '/b.jpg'],
          },
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content, hasLength(3));
      expect(content[0], {'type': 'text', 'text': '看这些'});
      expect(content[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/a.jpg',
      });
      expect(content[2]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/b.jpg',
      });
      expect(result[0].containsKey('image_path'), isFalse);
      expect(result[0].containsKey('image_paths'), isFalse);
    });

    test('image_paths 为 JSON 数组字符串时同样可挂图（DB 原样读出）', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '[图片]',
            'image_paths': '["/a.jpg","/b.jpg"]',
          },
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content, hasLength(3));
      expect(content[0]['text'], VisionMessageBuilder.imagePlaceholder);
    });

    test('image_paths 为空列表时回退 image_path 单图', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '[图片]',
            'image_path': '/a.jpg',
            'image_paths': <String>[],
          },
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content, hasLength(2));
      expect(content[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/a.jpg',
      });
    });

    test('上限按张数跨消息累计：多图消息可占多张额度，取最近的图', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '旧\n[图片]',
            'image_paths': ['/1.jpg', '/2.jpg'],
          },
          {
            'role': 'user',
            'content': '新\n[图片]',
            'image_paths': ['/3.jpg', '/4.jpg'],
          },
        ],
        nativeVision: true,
        readImageBase64: fakeReader,
      );

      // 共 4 张 > 3 上限：旧消息只挂最近的 1 张（/2.jpg），新消息 2 张全挂
      final oldContent = result[0]['content'] as List<Map<String, dynamic>>;
      expect(oldContent, hasLength(2));
      expect(oldContent[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/2.jpg',
      });
      final newContent = result[1]['content'] as List<Map<String, dynamic>>;
      expect(newContent, hasLength(3));
      expect(newContent[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/3.jpg',
      });
      expect(newContent[2]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/4.jpg',
      });
    });

    test('多图部分读取失败：成功的图照常挂上', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '看\n[图片]',
            'image_paths': ['/missing.jpg', '/b.jpg'],
          },
        ],
        nativeVision: true,
        readImageBase64: (path) async => path.contains('missing') ? null : 'b64-$path',
      );

      final content = result[0]['content'] as List<Map<String, dynamic>>;
      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': '看'});
      expect(content[1]['image_url'], {
        'url': 'data:image/jpeg;base64,b64-/b.jpg',
      });
    });

    test('多图全部读取失败：保持原文本占位降级', () async {
      final result = await VisionMessageBuilder.attachImagesToMessages(
        [
          {
            'role': 'user',
            'content': '看\n[图片]',
            'image_paths': ['/x.jpg', '/y.jpg'],
          },
        ],
        nativeVision: true,
        readImageBase64: (_) async => null,
      );

      expect(result[0], {'role': 'user', 'content': '看\n[图片]'});
    });
  });

  group('VisionMessageBuilder.composeMultiDescribedContent', () {
    test('单张描述退化为单图格式', () {
      final composed = VisionMessageBuilder.composeMultiDescribedContent(
        userText: '',
        descriptions: ['一只猫在桌上'],
      );

      expect(composed, '[用户发送了一张图片，图片内容：一只猫在桌上]');
    });

    test('多张描述合并为编号列表', () {
      final composed = VisionMessageBuilder.composeMultiDescribedContent(
        userText: '',
        descriptions: ['一只猫', '一只狗'],
      );

      expect(composed, '[用户发送了2张图片，图片内容：1. 一只猫 2. 一只狗]');
    });

    test('有用户文字时拼接在描述标记之前', () {
      final composed = VisionMessageBuilder.composeMultiDescribedContent(
        userText: '我家宠物',
        descriptions: ['一只猫', '一只狗', '一只鸟'],
      );

      expect(
        composed,
        '我家宠物\n[用户发送了3张图片，图片内容：1. 一只猫 2. 一只狗 3. 一只鸟]',
      );
    });
  });
}
