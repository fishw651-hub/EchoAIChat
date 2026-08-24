import 'package:aichat/models/short_term_message.dart';
import 'package:aichat/services/image_paths_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImagePathsCodec', () {
    test('encode/decode 往返一致', () {
      final encoded = ImagePathsCodec.encode(['/a.jpg', '/b.jpg']);
      expect(encoded, '["/a.jpg","/b.jpg"]');
      expect(ImagePathsCodec.decode(encoded), ['/a.jpg', '/b.jpg']);
    });

    test('encode 空列表/null 返回 null（列保持 NULL 回退 image_path）', () {
      expect(ImagePathsCodec.encode(null), isNull);
      expect(ImagePathsCodec.encode(const []), isNull);
    });

    test('decode 非法 JSON/空值容错返回空列表', () {
      expect(ImagePathsCodec.decode(null), isEmpty);
      expect(ImagePathsCodec.decode(''), isEmpty);
      expect(ImagePathsCodec.decode('not-json'), isEmpty);
      expect(ImagePathsCodec.decode('{"a":1}'), isEmpty);
    });

    test('resolve 优先 image_paths，为空回退 image_path 单图', () {
      expect(
        ImagePathsCodec.resolve(
          imagePathsRaw: '["/a.jpg","/b.jpg"]',
          imagePath: '/old.jpg',
        ),
        ['/a.jpg', '/b.jpg'],
      );
      expect(
        ImagePathsCodec.resolve(imagePathsRaw: null, imagePath: '/old.jpg'),
        ['/old.jpg'],
      );
      expect(
        ImagePathsCodec.resolve(imagePathsRaw: '', imagePath: '/old.jpg'),
        ['/old.jpg'],
      );
      expect(
        ImagePathsCodec.resolve(imagePathsRaw: null, imagePath: null),
        isEmpty,
      );
    });
  });

  group('ShortTermMessage image_paths 存取兼容', () {
    test('fromMap：新列为空时回退旧 image_path 列', () {
      final msg = ShortTermMessage.fromMap({
        'id': 'S-1',
        'role': 'user',
        'content': '[图片]',
        'agent_id': 'a1',
        'image_path': '/old.jpg',
        'image_paths': null,
        'timestamp': 1000,
      });

      expect(msg.imagePath, '/old.jpg');
      expect(msg.imagePaths, ['/old.jpg']);
    });

    test('fromMap：新列优先，解码完整多图列表', () {
      final msg = ShortTermMessage.fromMap({
        'id': 'S-2',
        'role': 'user',
        'content': '看\n[图片]',
        'agent_id': 'a1',
        'image_path': '/a.jpg',
        'image_paths': '["/a.jpg","/b.jpg"]',
        'timestamp': 1000,
      });

      expect(msg.imagePaths, ['/a.jpg', '/b.jpg']);
    });

    test('fromMap：无图消息 imagePaths 为 null', () {
      final msg = ShortTermMessage.fromMap({
        'id': 'S-3',
        'role': 'user',
        'content': '你好',
        'agent_id': 'a1',
        'image_path': null,
        'image_paths': null,
        'timestamp': 1000,
      });

      expect(msg.imagePath, isNull);
      expect(msg.imagePaths, isNull);
    });

    test('toMap：多图写 image_paths JSON 且 image_path 填首图', () {
      final map = ShortTermMessage(
        id: 'S-4',
        role: 'user',
        content: '[图片]',
        agentId: 'a1',
        imagePaths: const ['/a.jpg', '/b.jpg'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ).toMap();

      expect(map['image_paths'], '["/a.jpg","/b.jpg"]');
      expect(map['image_path'], '/a.jpg');
    });

    test('toMap：单图 imagePath 不写 image_paths（保持 NULL）', () {
      final map = ShortTermMessage(
        id: 'S-5',
        role: 'user',
        content: '[图片]',
        agentId: 'a1',
        imagePath: '/a.jpg',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ).toMap();

      expect(map['image_path'], '/a.jpg');
      expect(map['image_paths'], isNull);
    });

    test('toMap/fromMap 往返：多图列表完整保留', () {
      final roundTrip = ShortTermMessage.fromMap(
        ShortTermMessage(
          id: 'S-6',
          role: 'user',
          content: '[图片]',
          agentId: 'a1',
          imagePaths: const ['/a.jpg', '/b.jpg', '/c.jpg'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ).toMap(),
      );

      expect(roundTrip.imagePaths, ['/a.jpg', '/b.jpg', '/c.jpg']);
      expect(roundTrip.imagePath, '/a.jpg');
    });
  });
}
