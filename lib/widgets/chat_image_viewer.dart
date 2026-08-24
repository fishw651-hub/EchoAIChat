import 'dart:io';

import 'package:flutter/material.dart';

/// 大图查看：PageView 左右滑动切换 + 双指缩放，右上角关闭
void showChatImageViewer(
  BuildContext context,
  List<String> paths,
  int initialIndex,
) {
  final scheme = Theme.of(context).colorScheme;
  showDialog(
    context: context,
    barrierColor: scheme.scrim.withValues(alpha: 0.85),
    builder: (ctx) {
      return Dialog(
        backgroundColor: scheme.surfaceContainerLowest,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: paths.length,
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(child: Image.file(File(paths[i]))),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(Icons.close, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      );
    },
  );
}
