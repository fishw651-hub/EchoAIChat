import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 移动端设备 ID 实现
class PlatformDeviceId {
  static String? _cached;
  static const _key = 'device_id';

  static Future<String> getId() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var did = prefs.getString(_key);
    if (did == null || did.isEmpty) {
      did = const Uuid().v4();
      await prefs.setString(_key, did);
    }
    _cached = did;
    return did;
  }

  static String getDeviceName() {
    final os = Platform.operatingSystem;
    if (os == 'ios') return 'iOS 设备';
    return '${os[0].toUpperCase()}${os.substring(1)} 设备';
  }
}
