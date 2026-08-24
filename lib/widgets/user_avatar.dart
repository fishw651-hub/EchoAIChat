import 'package:flutter/material.dart';

import '../services/avatar_cache_service.dart';

/// 用户头像：优先本地缓存文件，未缓存时后台下载后切换为本地图。
/// [avatar] 为服务器相对路径（如 /uploads/avatars/xxx.png）或完整 URL。
class UserAvatar extends StatefulWidget {
  final String? avatar;
  final double radius;
  final Color? backgroundColor;

  /// 无头像时的占位内容（图标或首字母）
  final Widget? fallback;

  const UserAvatar({
    super.key,
    this.avatar,
    this.radius = 18,
    this.backgroundColor,
    this.fallback,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatar != widget.avatar) _resolve();
  }

  Future<void> _resolve() async {
    final img = await AvatarCacheService.resolveAvatarImage(widget.avatar);
    if (mounted) setState(() => _image = img);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor ?? scheme.primaryContainer,
      backgroundImage: _image,
      child: _image == null ? widget.fallback : null,
    );
  }
}
