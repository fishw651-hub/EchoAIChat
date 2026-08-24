import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/services/avatar_cache_service_io.dart';

void main() {
  group('avatarCacheFileName', () {
    test('取路径最后一段作为文件名', () {
      expect(
        avatarCacheFileName('/uploads/avatars/abc123.png'),
        'abc123.png',
      );
    });

    test('去掉查询参数', () {
      expect(
        avatarCacheFileName('/uploads/avatars/abc.png?v=2'),
        'abc.png',
      );
    });

    test('非法字符替换为下划线', () {
      expect(avatarCacheFileName('/a/b c/d#e.jpg'), 'd_e.jpg');
    });

    test('空段回退为 avatar', () {
      expect(avatarCacheFileName('/'), 'avatar');
      expect(avatarCacheFileName(''), 'avatar');
    });
  });
}
