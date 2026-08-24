import 'package:flutter/widgets.dart';

import 'avatar_cache_service_stub.dart'
    if (dart.library.io) 'avatar_cache_service_io.dart' as impl;

/// 用户头像本地缓存服务（facade，按平台条件导入）。
///
/// IO 平台：头像下载到应用文档目录 `avatar_cache/`，显示优先本地文件，
/// 离线/弱网也能立即展示；Web 平台：直接用 NetworkImage。
class AvatarCacheService {
  /// 解析头像为 ImageProvider：本地缓存文件 > 重新下载缓存 > 网络图
  static Future<ImageProvider?> resolveAvatarImage(String? raw) =>
      impl.resolveAvatarImage(raw);

  /// 登录/资料刷新后调用：缓存当前头像并清理旧缓存文件
  static Future<void> refreshForUser(String? avatarRaw) =>
      impl.refreshForUser(avatarRaw);
}
