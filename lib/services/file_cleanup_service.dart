import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App 文件清理服务
///
/// 清理 app docs 目录中堆积的旧文件：
/// - 截图文件（screenshot_*.png）
/// - 智能体导出 JSON（*_export.agent.json）
/// - 配置导出 JSON（aichat_config_*.json）
/// - 数据库备份文件（aichat_backup_*.db）
///
/// 策略：保留最近 7 天的文件，更老的删除
class FileCleanupService {
  static bool _done = false;

  /// 执行一次清理（app 生命周期内只执行一次）
  static Future<void> runOnce() async {
    if (_done) return;
    _done = true;
    // Web 端无文件系统，直接跳过
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      int deletedCount = 0;

      // 需要清理的文件名前缀/模式
      final patterns = [
        'screenshot_', // 截图
        '_export.agent.json', // 智能体导出
        'aichat_config_', // 配置导出
        'aichat_backup_', // 数据库备份
      ];

      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);

        // 检查是否匹配清理模式
        bool shouldClean = false;
        for (final pattern in patterns) {
          // 仅按前缀匹配，避免 contains 误删包含子串但前缀不符的文件
          if (name.startsWith(pattern)) {
            shouldClean = true;
            break;
          }
        }
        if (!shouldClean) continue;

        // 检查文件修改时间
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
            deletedCount++;
          }
        } catch (e) {
          debugPrint('[FileCleanup] stat/delete failed for $name: $e');
        }
      }

      if (deletedCount > 0) {
        debugPrint('[FileCleanup] deleted $deletedCount old files from docs directory');
      }
    } catch (e) {
      debugPrint('[FileCleanup] failed: $e');
    }
  }
}
