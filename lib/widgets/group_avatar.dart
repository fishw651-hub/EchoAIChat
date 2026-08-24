import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;

/// 群聊头像 - 统一渲染逻辑
///
/// 显示规则：
/// - 若 [avatarPath] 非空且文件存在，显示本地图片（PNG/JPG）
/// - 否则根据 [avatarIcon] 显示对应 Material Icon（默认 group），背景纯色 [avatarColor]
class GroupAvatar extends StatelessWidget {
  final int avatarColor;
  final String? avatarIcon;
  final String? avatarPath;
  final double size;
  final double radius;
  final double iconSize;

  const GroupAvatar({
    super.key,
    required this.avatarColor,
    this.avatarIcon,
    this.avatarPath,
    this.size = 50,
    this.radius = 12,
    this.iconSize = 24,
  });

  /// 预设图标映射（与 GroupAvatarPicker 保持一致）
  static const Map<String, IconData> presetIcons = {
    'group': Icons.group,
    'groups': Icons.groups,
    'people': Icons.people,
    'family': Icons.family_restroom,
    'school': Icons.school,
    'work': Icons.work,
    'game': Icons.sports_esports,
    'theater': Icons.theater_comedy,
    'book': Icons.auto_stories,
    'psychology': Icons.psychology,
    'cafe': Icons.local_cafe,
    'party': Icons.celebration,
    'heart': Icons.favorite,
    'public': Icons.public,
    'flight': Icons.flight,
    'spa': Icons.spa,
    'music': Icons.music_note,
    'movie': Icons.movie,
    'pets': Icons.pets,
    'travel': Icons.luggage,
  };

  /// 默认图标名（avatarIcon 为 null 时使用）
  static const String defaultIconName = 'group';

  static IconData iconFor(String? name) {
    if (name == null || name.isEmpty) return presetIcons[defaultIconName]!;
    return presetIcons[name] ?? presetIcons[defaultIconName]!;
  }

  /// 根据背景色亮度选择前景色（黑/白）
  static Color onColor(int colorValue) {
    final c = Color(colorValue);
    final luminance = 0.299 * (c.r * 255.0).round() +
        0.587 * (c.g * 255.0).round() +
        0.114 * (c.b * 255.0).round();
    return luminance > 150 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    // 优先显示本地图片
    if (avatarPath != null && avatarPath!.isNotEmpty && !kIsWeb && File(avatarPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(avatarPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(avatarColor),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(
          iconFor(avatarIcon),
          color: onColor(avatarColor),
          size: iconSize,
        ),
      ),
    );
  }
}

/// 群聊头像选择器 - 图片上传 + 图标 + 颜色
class GroupAvatarPicker extends StatelessWidget {
  final String? selectedIcon;
  final int selectedColor;
  final String? selectedAvatarPath;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<String?> onAvatarPathChanged;

  const GroupAvatarPicker({
    super.key,
    this.selectedIcon,
    required this.selectedColor,
    this.selectedAvatarPath,
    required this.onIconChanged,
    required this.onColorChanged,
    required this.onAvatarPathChanged,
  });

  static const _colors = [
    0xFFE8F5E9,
    0xFFFFF3E0,
    0xFFFCE4EC,
    0xFFE3F2FD,
    0xFFF3E5F5,
    0xFFE0F2F1,
    0xFFFFF8E1,
    0xFFFBE9E7,
    0xFFE1F5FE,
    0xFFF1F8E9,
    0xFFFFEBEE,
    0xFFEDE7F6,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveIcon = selectedIcon ?? GroupAvatar.defaultIconName;
    final hasImage = selectedAvatarPath != null &&
        selectedAvatarPath!.isNotEmpty &&
        !kIsWeb &&
        File(selectedAvatarPath!).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── 自定义图片上传 ───
        Text('自定义头像',
            style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(children: [
          // 预览
          GroupAvatar(
            avatarColor: selectedColor,
            avatarIcon: effectiveIcon,
            avatarPath: selectedAvatarPath,
            size: 56,
            radius: 12,
            iconSize: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              TextButton.icon(
                icon: const Icon(Icons.photo_library, size: 16),
                label: const Text('相册', style: TextStyle(fontSize: 12)),
                onPressed: () => _pickImage(context, ImageSource.gallery),
              ),
              TextButton.icon(
                icon: const Icon(Icons.camera_alt, size: 16),
                label: const Text('拍照', style: TextStyle(fontSize: 12)),
                onPressed: () => _pickImage(context, ImageSource.camera),
              ),
              if (hasImage)
                TextButton.icon(
                  icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
                  label: Text('移除', style: TextStyle(fontSize: 12, color: scheme.error)),
                  onPressed: () => onAvatarPathChanged(null),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),

        // ─── 图标选择（仅当未上传图片时生效） ───
        Text('选择图标',
            style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
          children: GroupAvatar.presetIcons.keys.map((name) {
            final icon = GroupAvatar.presetIcons[name]!;
            final isSelected = effectiveIcon == name;
            return GestureDetector(
              onTap: () => onIconChanged(name),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(selectedColor),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Icon(icon,
                    color: GroupAvatar.onColor(selectedColor), size: 22),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('选择颜色',
            style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colors.map((c) {
            final isSelected = selectedColor == c;
            return GestureDetector(
              onTap: () => onColorChanged(c),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? scheme.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
          source: source, maxWidth: 512, maxHeight: 512);
      if (img == null) return;
      final dir = await pp.getApplicationDocumentsDirectory();
      final destPath =
          '${dir.path}/group_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(img.path).copy(destPath);
      onAvatarPathChanged(destPath);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片选择失败: $e')),
        );
      }
    }
  }
}
