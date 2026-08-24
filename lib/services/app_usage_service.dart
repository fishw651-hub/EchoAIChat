import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用使用时长服务
///
/// 仅 Android 支持。通过 MethodChannel 调用原生 UsageStatsManager，
/// 需要"使用情况访问权限"（PACKAGE_USAGE_STATS，特殊权限，需引导用户去系统设置授权）。
class AppUsageService {
  static const _channel = MethodChannel('com.aichat.aichat/app_usage');

  /// 检查是否已获得"使用情况访问权限"
  static Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('[AppUsage] hasPermission failed: $e');
      return false;
    }
  }

  /// 打开系统"使用情况访问权限"设置页
  static Future<void> openPermissionSettings() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openPermissionSettings');
    } catch (e) {
      debugPrint('[AppUsage] openPermissionSettings failed: $e');
    }
  }

  /// 获取今日各应用使用时长
  ///
  /// 返回 List<{name, package, duration_ms}>，按时长降序。
  /// 无权限或非 Android 平台返回空列表。
  static Future<List<AppUsageInfo>> getTodayUsage() async {
    if (kIsWeb) return [];
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getTodayUsage');
      if (result == null) return [];
      return result
          .map((e) => AppUsageInfo.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('[AppUsage] getTodayUsage failed: $e');
      return [];
    }
  }

  /// 获取格式化的今日使用摘要（用于真实信息注入）
  ///
  /// 示例输出：
  /// - 今日屏幕时间 3小时20分钟，Top: 微信(1h12m)、抖音(45m)、B站(28m)
  /// - 今日屏幕时间 12分钟，Top: 微信(8m)、设置(4m)
  /// - 今日屏幕时间 3小时20分钟
  /// - （无数据时返回空字符串）
  static Future<String> getTodaySummary({int topCount = 3}) async {
    if (kIsWeb) return '';
    final apps = await getTodayUsage();
    if (apps.isEmpty) return '';

    final totalMs = apps.fold<int>(0, (sum, a) => sum + a.durationMs);
    final total = _formatDuration(totalMs);

    final top = apps.take(topCount).toList();
    if (top.isEmpty) return '今日屏幕时间 $total';

    final topStr = top.map((a) => '${a.name}(${_formatDuration(a.durationMs)})').join('、');
    return '今日屏幕时间 $total，Top: $topStr';
  }

  /// 将毫秒时长格式化为 "1h12m" 或 "8m" 或 "45s"
  static String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainMinutes = minutes % 60;
    if (remainMinutes == 0) return '${hours}h';
    return '${hours}h${remainMinutes}m';
  }
}

/// 单个应用的使用信息
class AppUsageInfo {
  final String name;
  final String packageName;
  final int durationMs;

  const AppUsageInfo({
    required this.name,
    required this.packageName,
    required this.durationMs,
  });

  factory AppUsageInfo.fromMap(Map<String, dynamic> map) {
    return AppUsageInfo(
      name: (map['name'] as String?) ?? '',
      packageName: (map['package'] as String?) ?? '',
      durationMs: (map['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }
}
