import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'proactive_care_service.dart';
import 'secure_session_store.dart';

/// alarm 回调（后台 isolate 入口，必须 top-level + vm:entry-point）
@pragma('vm:entry-point')
Future<void> proactiveCareAlarmCallback() async {
  // 后台 isolate 中使用插件（sqflite/path_provider/secure_storage）前必须初始化
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await ProactiveCareService.runBackgroundCheck();
  } catch (e) {
    // 后台失败静默降级，留给前台补发
    debugPrint('[ProactiveCareAlarm] background run failed: $e');
  }
  // 每次触发后只保留下一次按需检查
  try {
    await ProactiveCareAlarmScheduler.sync();
  } catch (_) {}
}

/// 主动关心后台调度（仅 Android）：
/// 窗口期内按需安排单个 one-shot alarm，触发后再自续排。
class ProactiveCareAlarmScheduler {
  ProactiveCareAlarmScheduler._();

  static const int alarmId = 71001;
  static const int legacyWindowStartAlarmId = 71002;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static DateTime nextCheckTime({
    required DateTime now,
    required AwakeWindow window,
  }) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final windowStart = dayStart.add(
      Duration(minutes: window.startMinutes),
    );
    final windowEnd = dayStart.add(Duration(minutes: window.endMinutes));
    if (now.isBefore(windowStart)) return windowStart;
    if (!now.isBefore(windowEnd)) {
      return windowStart.add(const Duration(days: 1));
    }

    final nextPeriodicCheck = now.add(const Duration(minutes: 30));
    if (nextPeriodicCheck.isBefore(windowEnd)) return nextPeriodicCheck;
    return windowStart.add(const Duration(days: 1));
  }

  static Future<void> initialize() async {
    if (!_supported) return;
    try {
      await AndroidAlarmManager.initialize();
    } catch (e) {
      debugPrint('[ProactiveCareAlarm] initialize failed: $e');
    }
  }

  /// 兼容旧调用方：同步当前候选并安排下一次检查。
  static Future<void> schedule() async {
    await sync();
  }

  /// 根据当前是否存在启用候选，只保留一个下一次 one-shot alarm。
  static Future<void> sync() async {
    if (!_supported) return;
    DateTime next;
    try {
      final agents = await DatabaseService.getAgents();
      final session = await SecureSessionStore().read();
      final hasCandidate = agents.any(
        (agent) =>
            agent.realInfoEnabled &&
            agent.proactiveCareEnabled &&
            !agent.isGroupOnly,
      );
      if (!hasCandidate || session?.jwtToken?.isEmpty != false) {
        await cancel();
        return;
      }

      await initialize();
      final prefs = await SharedPreferences.getInstance();
      final startMinutes =
          prefs.getInt('proactive_care_window_start') ?? 8 * 60;
      final endMinutes =
          prefs.getInt('proactive_care_window_end') ?? 20 * 60;

      final now = DateTime.now();
      next = ProactiveCareAlarmScheduler.nextCheckTime(
        now: now,
        window: AwakeWindow(startMinutes, endMinutes),
      );
      await AndroidAlarmManager.cancel(alarmId);
      await AndroidAlarmManager.cancel(legacyWindowStartAlarmId);
    } catch (e) {
      debugPrint('[ProactiveCareAlarm] prepare schedule failed: $e');
      return;
    }

    try {
      await AndroidAlarmManager.oneShotAt(
        next,
        alarmId,
        proactiveCareAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    } catch (e) {
      // 精确 alarm 权限被拒（Android 12+ 可收回）时退化为非精确
      debugPrint('[ProactiveCareAlarm] exact alarm failed, fallback: $e');
      try {
        await AndroidAlarmManager.oneShotAt(
          next,
          alarmId,
          proactiveCareAlarmCallback,
          wakeup: true,
          rescheduleOnReboot: true,
        );
      } catch (_) {}
    }
  }

  static Future<void> cancel() async {
    if (!_supported) return;
    try {
      await AndroidAlarmManager.cancel(alarmId);
      await AndroidAlarmManager.cancel(legacyWindowStartAlarmId);
    } catch (_) {}
  }
}
