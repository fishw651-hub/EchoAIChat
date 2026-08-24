import 'dart:html' as html;
import 'package:uuid/uuid.dart';

/// Web 端设备 ID 实现（localStorage 持久化）
class PlatformDeviceId {
  static String? _cached;
  static const _storageKey = 'aichat_device_id';

  static Future<String> getId() async {
    if (_cached != null) return _cached!;

    // 优先从 localStorage 读取
    final stored = html.window.localStorage[_storageKey];
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    // 生成新 UUID
    final newId = const Uuid().v4();
    html.window.localStorage[_storageKey] = newId;
    _cached = newId;
    return newId;
  }

  static String getDeviceName() {
    // 从 User Agent 推断设备类型
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('android')) return 'Android 浏览器';
    if (ua.contains('iphone') || ua.contains('ipad')) return 'iOS 浏览器';
    if (ua.contains('mac')) return 'Mac 浏览器';
    if (ua.contains('win')) return 'Windows 浏览器';
    if (ua.contains('linux')) return 'Linux 浏览器';
    return 'Web 浏览器';
  }
}
