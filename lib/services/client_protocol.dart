import 'package:flutter/foundation.dart';

abstract final class ClientProtocol {
  static const versionCode = 67;
  static const platformHeader = 'X-Client-Platform';
  static const versionHeader = 'X-Client-Version-Code';

  static String get currentPlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static Map<String, String> headers(String platform) => {
    versionHeader: '$versionCode',
    platformHeader: platform,
  };

  static Map<String, String> get currentHeaders => headers(currentPlatform);
}
