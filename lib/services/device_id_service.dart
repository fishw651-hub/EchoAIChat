import '../models/device_identity.dart';
import 'platform_device_id.dart';
import 'platform_device_identity.dart';

/// 设备 ID 服务（条件导入委托给平台实现）
class DeviceIdService {
  DeviceIdService._();

  static Future<String> get id async => PlatformDeviceId.getId();

  static Future<DeviceIdentity> get identity async =>
      PlatformDeviceIdentity.getIdentity();

  static String get deviceName => PlatformDeviceId.getDeviceName();
}
