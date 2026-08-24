enum DeviceClientKind {
  native('native'),
  web('web');

  const DeviceClientKind(this.wireName);

  final String wireName;
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.displayName,
    required this.clientKind,
    required this.platform,
    this.browser,
  });

  factory DeviceIdentity.web({required String id, required String userAgent}) {
    final browser = browserFromUserAgent(userAgent);
    final platform = platformFromUserAgent(userAgent);
    return DeviceIdentity(
      id: id,
      displayName: '$platform · $browser',
      clientKind: DeviceClientKind.web,
      platform: platform,
      browser: browser,
    );
  }

  final String id;
  final String displayName;
  final DeviceClientKind clientKind;
  final String platform;
  final String? browser;

  Map<String, dynamic> toRegistrationJson() => {
    'device_id': id,
    'device_name': displayName,
    'client_kind': clientKind.wireName,
    'platform': platform,
    'browser': browser ?? '',
  };

  static String browserFromUserAgent(String userAgent) {
    final normalized = userAgent.toLowerCase();
    if (normalized.contains('edg/')) return 'Edge';
    if (normalized.contains('firefox/')) return 'Firefox';
    if (normalized.contains('opr/') || normalized.contains('opera/')) {
      return 'Opera';
    }
    if (normalized.contains('chrome/') || normalized.contains('crios/')) {
      return 'Chrome';
    }
    if (normalized.contains('safari/')) return 'Safari';
    return '浏览器';
  }

  static String platformFromUserAgent(String userAgent) {
    final normalized = userAgent.toLowerCase();
    if (normalized.contains('windows')) return 'Windows';
    if (normalized.contains('android')) return 'Android';
    if (normalized.contains('iphone') ||
        normalized.contains('ipad') ||
        normalized.contains('ios')) {
      return 'iOS';
    }
    if (normalized.contains('macintosh') || normalized.contains('mac os')) {
      return 'macOS';
    }
    if (normalized.contains('linux')) return 'Linux';
    return 'Web';
  }
}
