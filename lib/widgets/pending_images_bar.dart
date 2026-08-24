import 'dart:io';

import 'package:flutter/material.dart';

/// 图片暂存区（仿微信）：选图后不立即发送，缩略图横排挂在输入栏上方，
/// 右上角 × 删除；点发送后图文作为一条消息一起发出。
class PendingImagesBar extends StatelessWidget {
  /// 暂存图片的本地路径（压缩后）
  final List<String> paths;

  /// 点缩略图右上角 × 删除该张（index 为 paths 下标）
  final void Function(int index) onRemove;

  const PendingImagesBar({
    super.key,
    required this.paths,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: _buildThumb,
          ),
        ),
      ),
    );
  }

  /// 暂存区单张缩略图：56-64px 圆角小图 + 右上角 × 删除按钮
  Widget _buildThumb(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(paths[index]), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => onRemove(index),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.inverseSurface.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: scheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
