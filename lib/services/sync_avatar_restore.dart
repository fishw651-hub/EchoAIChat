import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:sqflite/sqflite.dart';

/// 多端同步后还原智能体头像。
///
/// 同步行中的 `avatar_path` 是源设备的本地路径，对端不存在；
/// 真正的头像数据在 `avatar_data`（base64）列中：
/// - avatar_data 非空且本地文件缺失 → 解码落盘并回写 avatar_path
/// - avatar_data 为空且 avatar_path 指向不存在文件 → 清空 avatar_path（头像已移除）
/// 已有本地文件时跳过，避免覆盖本机较新的头像。
Future<void> restoreSyncedAgentAvatars(Database db) async {
  if (kIsWeb) return;
  try {
    final rows = await db.query(
      'agents',
      columns: ['id', 'avatar_path', 'avatar_data'],
    );
    if (rows.isEmpty) return;
    final dir = await pp.getApplicationDocumentsDirectory();
    final avatarDir = Directory('${dir.path}/synced_avatars');
    if (!await avatarDir.exists()) await avatarDir.create(recursive: true);

    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final data = row['avatar_data']?.toString() ?? '';
      final path = row['avatar_path']?.toString() ?? '';
      final localExists = path.isNotEmpty && File(path).existsSync();

      if (data.isNotEmpty) {
        if (localExists) continue; // 本机已有头像，不覆盖
        try {
          final bytes = base64Decode(data);
          if (bytes.isEmpty) continue;
          final file = File('${avatarDir.path}/avatar_$id.png');
          await file.writeAsBytes(bytes, flush: true);
          await db.update(
            'agents',
            {'avatar_path': file.path},
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (_) {}
      } else if (path.isNotEmpty && !localExists) {
        // 源设备已移除头像，本端路径无效，清空回退到色块头像
        await db.update(
          'agents',
          {'avatar_path': null},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  } catch (_) {}
}
