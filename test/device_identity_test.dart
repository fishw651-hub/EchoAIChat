import 'package:aichat/models/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceIdentity', () {
    test('detects Edge before Chrome from user agent', () {
      const userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';

      final identity = DeviceIdentity.web(
        id: 'edge-profile-id',
        userAgent: userAgent,
      );

      expect(identity.id, 'edge-profile-id');
      expect(identity.clientKind, DeviceClientKind.web);
      expect(identity.browser, 'Edge');
      expect(identity.platform, 'Windows');
      expect(identity.displayName, 'Windows · Edge');
    });

    test('distinguishes Chrome and Firefox browser profiles', () {
      final chrome = DeviceIdentity.web(
        id: 'chrome-profile-id',
        userAgent:
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
            'Chrome/126.0.0.0 Safari/537.36',
      );
      final firefox = DeviceIdentity.web(
        id: 'firefox-profile-id',
        userAgent:
            'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) '
            'Gecko/20100101 Firefox/128.0',
      );

      expect(chrome.id, isNot(firefox.id));
      expect(chrome.browser, 'Chrome');
      expect(firefox.browser, 'Firefox');
    });

    test('serializes complete registration payload', () {
      const identity = DeviceIdentity(
        id: 'native-install-id',
        displayName: 'Android 设备',
        clientKind: DeviceClientKind.native,
        platform: 'android',
      );

      expect(identity.toRegistrationJson(), {
        'device_id': 'native-install-id',
        'device_name': 'Android 设备',
        'client_kind': 'native',
        'platform': 'android',
        'browser': '',
      });
    });
  });
}
