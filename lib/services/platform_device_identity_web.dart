import 'dart:html' as html;

import '../models/device_identity.dart';
import 'platform_device_id.dart';

class PlatformDeviceIdentity {
  static Future<DeviceIdentity> getIdentity() async {
    return DeviceIdentity.web(
      id: await PlatformDeviceId.getId(),
      userAgent: html.window.navigator.userAgent,
    );
  }
}
