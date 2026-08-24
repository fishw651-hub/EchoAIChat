import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AgentAvatar extends StatelessWidget {
  final String? name;
  final int avatarColor;
  final String? avatarPath;
  final double size;
  final double radius;
  final double fontSize;
  final bool showShadow;
  final String fallbackText;

  const AgentAvatar({
    super.key,
    this.name,
    required this.avatarColor,
    this.avatarPath,
    this.size = 56,
    this.radius = 28,
    this.fontSize = 24,
    this.showShadow = true,
    this.fallbackText = '?',
  });

  static Color onColor(int colorValue) {
    final color = Color(colorValue);
    final brightness = ThemeData.estimateBrightnessForColor(color);
    return brightness == Brightness.light ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Color(avatarColor);
    final child = _buildContent(backgroundColor, _displayText);

    if (!showShadow) {
      return child;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // 文件存在性进程级缓存：头像组件在列表/聊天页大量 build，
  // 每次 existsSync 都是同步系统调用。头像文件删除后路径会换新（uuid 文件名），
  // 缓存陈旧风险极低。
  static final Map<String, bool> _existsCache = {};

  Widget _buildContent(Color backgroundColor, String displayText) {
    if (avatarPath != null &&
        avatarPath!.isNotEmpty &&
        !kIsWeb &&
        _existsCache.putIfAbsent(
          avatarPath!,
          () => File(avatarPath!).existsSync(),
        )) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(avatarPath!),
          width: size,
          height: size,
          cacheWidth: (size * 2).round(),
          cacheHeight: (size * 2).round(),
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        alignment: Alignment.center,
        child: Text(
          displayText,
          style: TextStyle(
            color: onColor(avatarColor),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String get _displayText {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return fallbackText;
    return trimmed.characters.first.toUpperCase();
  }
}
