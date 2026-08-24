import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as pp;

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 图片裁剪工具：选图后进入全屏裁剪页，取消/确认按钮位于底部。
///
/// 纯 Flutter 实现（crop_your_image），Android/iOS/Windows/Web 行为一致。
class AvatarCropper {
  /// 裁剪 [sourcePath]。
  ///
  /// [aspectRatio] 默认 1:1（头像）；传 null 为自由比例（如聊天背景）。
  /// 返回裁剪后的临时文件；用户取消或裁剪失败时返回 null（调用方应放弃本次选择）。
  static Future<File?> cropAvatar(
    BuildContext context,
    String sourcePath, {
    required String title,
    double? aspectRatio = 1,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    if (!context.mounted) return null;
    final croppedBytes = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AvatarCropPage(
          imageBytes: bytes,
          title: title,
          aspectRatio: aspectRatio,
        ),
      ),
    );
    if (croppedBytes == null) return null;
    final dir = await pp.getTemporaryDirectory();
    final file = File(
      '${dir.path}/avatar_crop_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(croppedBytes, flush: true);
    return file;
  }
}

class _AvatarCropPage extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;
  final double? aspectRatio;

  const _AvatarCropPage({
    required this.imageBytes,
    required this.title,
    this.aspectRatio = 1,
  });

  @override
  State<_AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<_AvatarCropPage> {
  final CropController _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              aspectRatio: widget.aspectRatio,
              baseColor: scheme.surface,
              maskColor: scheme.onSurface.withValues(alpha: 0.4),
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure():
                    Navigator.of(context).pop(null);
                }
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cropping
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.get('cancel')),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space3),
                  Expanded(
                    child: FilledButton(
                      onPressed: _cropping
                          ? null
                          : () {
                              setState(() => _cropping = true);
                              _controller.crop();
                            },
                      child: Text(l10n.get('confirm')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
