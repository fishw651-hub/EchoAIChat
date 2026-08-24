import 'dart:io';

import '../models/device_identity.dart';
import 'platform_device_id.dart';

class PlatformDeviceIdentity {
  static Future<DeviceIdentity> getIdentity() async {
    final platform = Platform.operatingSystem;
    return DeviceIdentity(
      id: await PlatformDeviceId.getId(),
      displayName: PlatformDeviceId.getDeviceName(),
      clientKind: DeviceClientKind.native,
      platform: platform,
    );
  }
}
