import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;
import 'package:uuid/uuid.dart';

import '../models/sticker.dart';
import 'database_service.dart';

class StickerService {
  static const _uuid = Uuid();

  static Future<List<Sticker>> listActive() async {
    final rows = await DatabaseService.getStickers();
    return rows.map(Sticker.fromMap).toList(growable: false);
  }

  static Future<Sticker> add({
    required String sourcePath,
    required String description,
  }) async {
    final trimmed = description.trim();
    if (trimmed.isEmpty) throw ArgumentError('表情描述不能为空');
    if (trimmed.length > 30) throw ArgumentError('表情描述最多 30 个字符');
    final source = File(sourcePath);
    if (!await source.exists()) throw ArgumentError('图片文件不存在');

    final id = _uuid.v4();
    final now = DateTime.now();
    final directory = await pp.getApplicationDocumentsDirectory();
    final targetDirectory = Directory(p.join(directory.path, 'sticker_assets'));
    await targetDirectory.create(recursive: true);
    final extension = p.extension(sourcePath).toLowerCase();
    final target = File(p.join(targetDirectory.path, '$id$extension'));
    await source.copy(target.path);
    try {
      await DatabaseService.insertSticker(
        id: id,
        description: trimmed,
        imagePath: target.path,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
    return Sticker(
      id: id,
      description: trimmed,
      imagePath: target.path,
      createdAt: now,
      updatedAt: now,
    );
  }

  static Future<void> updateDescription(String id, String description) async {
    final trimmed = description.trim();
    if (trimmed.isEmpty) throw ArgumentError('表情描述不能为空');
    if (trimmed.length > 30) throw ArgumentError('表情描述最多 30 个字符');
    await DatabaseService.updateSticker(
      id: id,
      description: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> delete(String id) async {
    await DatabaseService.softDeleteSticker(
      id,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
