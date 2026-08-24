import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后台/自启动权限申请服务
///
/// 在 Android 上，flutter_local_notifications 的 `zonedSchedule` 仅能依赖系统 AlarmManager
/// 触发通知。但国产 ROM（MIUI/EMUI/ColorOS/OriginOS 等）默认会限制应用后台运行和自启动，
/// 导致应用被杀后计划消息通知无法触发。本服务在用户首次进入"计划消息"面板时引导授权：
/// 1. 通知权限（Android 13+ 需运行时申请）
/// 2. 精确闹钟权限（Android 12+ 用于 `setExactAndAllowWhileIdle`）
/// 3. 电池优化白名单（避免 Doze 模式延迟）
/// 4. 自启动权限（国产 ROM 专属，无标准 API，弹系统设置页引导用户手动开启）
class PermissionService {
  static const _prefKey = 'plan_permission_requested_v1';

  /// 是否已经引导过权限（true 表示已申请过，不重复弹窗）
  static Future<bool> hasRequested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) == true;
  }

  static Future<void> _markRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  /// 首次进入计划消息面板时调用，引导用户授予所有必要权限
  /// 返回 true 表示核心权限已就绪；false 表示用户拒绝部分权限（仍可使用，但后台不可靠）
  static Future<bool> requestPlanPermissions() async {
    // 检查核心权限（通知）实际状态：已授予则跳过，未授予则继续申请。
    // 不再仅凭"曾经申请过"就返回 true，否则被拒绝后永远不会重新引导。
    try {
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isGranted) return true;
    } catch (e) {
      debugPrint('[Permission] notification status check failed: $e');
    }
    await _markRequested();

    bool allOk = true;

    // 1. 通知权限（Android 13+ / iOS）
    try {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) allOk = false;
      }
    } catch (e) {
      debugPrint('[Permission] notification request failed: $e');
    }

    // 2. 精确闹钟权限（Android 12+）
    // permission_handler 11.x 提供 Permission.scheduleExactAlarm
    try {
      final alarmStatus = await Permission.scheduleExactAlarm.status;
      if (!alarmStatus.isGranted) {
        final result = await Permission.scheduleExactAlarm.request();
        if (!result.isGranted) allOk = false;
      }
    } catch (e) {
      debugPrint('[Permission] scheduleExactAlarm request failed: $e');
    }

    // 3. 电池优化白名单（Android）
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        final result = await Permission.ignoreBatteryOptimizations.request();
        if (!result.isGranted) allOk = false;
      }
    } catch (e) {
      debugPrint('[Permission] ignoreBatteryOptimizations request failed: $e');
    }

    // 4. 自启动权限（国产 ROM）：permission_handler 不直接支持
    //    留给 UI 层通过 package URI 引导用户跳转系统设置页

    return allOk;
  }

  /// 是否需要引导用户手动开启自启动（国产 ROM）
  /// 通过设备品牌粗略判断
  static bool get needsAutoStartGuide {
    // 简单返回 true：所有 Android 设备都建议引导用户检查自启动权限
    // 国产 ROM 普遍限制后台，让用户自行确认是否需要开启
    return defaultTargetPlatform == TargetPlatform.android;
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});
