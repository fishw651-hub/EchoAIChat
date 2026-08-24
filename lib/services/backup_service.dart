import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'database_service.dart';

/// 备份结果：备份文件路径、文件名、是否已复制到系统下载目录
typedef BackupResult = ({String path, String fileName, bool inDownloads});

/// 本地数据库备份/恢复（设置页）。
///
/// 封装备份文件命名与 Android 下载目录副本等平台细节，
/// screens 不直接触 DatabaseService。
class BackupService {
  /// 备份数据库到应用文档目录（aichat_backup_<时间戳>.db）。
  /// Android 上尽最大努力再复制一份到系统 Download 目录。
  Future<BackupResult> backup() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'aichat_backup_$timestamp.db';
    final dir = await getApplicationDocumentsDirectory();
    final destPath = '${dir.path}/$fileName';
    await DatabaseService.backupDatabase(destPath);

    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          await File(destPath).copy('${downloadDir.path}/$fileName');
          return (path: destPath, fileName: fileName, inDownloads: true);
        }
      }
    } catch (_) {}
    return (path: destPath, fileName: fileName, inDownloads: false);
  }

  /// 从指定备份文件恢复数据库（覆盖当前库，调用方需先弹确认）
  Future<void> restore(String sourcePath) {
    return DatabaseService.restoreDatabase(sourcePath);
  }
}
