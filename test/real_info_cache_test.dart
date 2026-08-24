import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aichat/services/real_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RealInfoService 缓存读写', () {
    test('写入后读取返回原值（含时间戳）', () async {
      SharedPreferences.setMockInitialValues({});
      await RealInfoService.writeCache('test_key', {
        'city': '上海',
        'weather': 'Sunny 30°C',
      });
      final got = await RealInfoService.readCache(
        'test_key',
        const Duration(minutes: 30),
      );
      expect(got, isNotNull);
      expect(got!['city'], '上海');
      expect(got['weather'], 'Sunny 30°C');
      expect(got['ts'], isNotEmpty);
    });

    test('过期缓存返回 null', () async {
      final old = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'test_key':
            '{"city":"北京","weather":"Cloudy 20°C","ts":$old}',
      });
      final got = await RealInfoService.readCache(
        'test_key',
        const Duration(minutes: 30),
      );
      expect(got, isNull);
    });

    test('缓存不存在或损坏返回 null', () async {
      SharedPreferences.setMockInitialValues({'test_key': 'not-json'});
      expect(
        await RealInfoService.readCache('test_key', const Duration(minutes: 1)),
        isNull,
      );
      expect(
        await RealInfoService.readCache('missing', const Duration(minutes: 1)),
        isNull,
      );
    });
  });
}
