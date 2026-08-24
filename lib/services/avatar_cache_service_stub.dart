import 'package:flutter/widgets.dart';

import '../utils/server_url.dart';

/// Web / 无 IO 平台实现：不做磁盘缓存，直接网络图
Future<ImageProvider?> resolveAvatarImage(String? raw) async {
  final url = resolveServerUrl(raw);
  return url != null ? NetworkImage(url) : null;
}

Future<void> refreshForUser(String? avatarRaw) async {}
