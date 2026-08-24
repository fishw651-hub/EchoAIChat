package com.aichat.aichat

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.aichat.aichat/app_usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasUsageStatsPermission())
                "openPermissionSettings" -> {
                    openUsageAccessSettings()
                    result.success(true)
                }
                "getTodayUsage" -> result.success(getTodayUsageStats())
                else -> result.notImplemented()
            }
        }
    }

    /// 检查是否已授予"使用情况访问"权限
    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /// 跳转到系统"使用情况访问权限"设置页
    private fun openUsageAccessSettings() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
        } catch (e: Exception) {
            // 某些设备可能没有该 Activity，回退到应用详情页
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = android.net.Uri.fromParts("package", packageName, null)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    /// 获取今日各应用使用时长
    /// 返回 List<Map<String, Any>>：[{name, package, duration_ms}, ...]
    private fun getTodayUsageStats(): List<Map<String, Any>> {
        if (!hasUsageStatsPermission()) return emptyList()

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        ) ?: return emptyList()

        // 按 packageName 聚合（同一应用可能有多个 UsageStats 记录）
        val aggregated = mutableMapOf<String, Long>()
        for (stat in stats) {
            val pkg = stat.packageName ?: continue
            aggregated[pkg] = (aggregated[pkg] ?: 0L) + stat.totalTimeInForeground
        }

        // 转为列表并排序（按时长降序）
        val pm = packageManager
        val result = mutableListOf<Map<String, Any>>()
        for ((pkg, duration) in aggregated) {
            if (duration < 60_000) continue // 跳过使用不足 1 分钟的应用
            val name = try {
                val info = pm.getApplicationInfo(pkg, 0)
                pm.getApplicationLabel(info).toString()
            } catch (e: Exception) {
                pkg
            }
            result.add(mapOf(
                "name" to name,
                "package" to pkg,
                "duration_ms" to duration
            ))
        }
        result.sortByDescending { (it["duration_ms"] as Long) }
        return result
    }
}
