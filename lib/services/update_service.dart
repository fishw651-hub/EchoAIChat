import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/server_config.dart';

class UpdateInfo {
  final String downloadUrl;
  final String releaseNotes;
  final String version;
  final int versionCode;
  final int fileSize;
  final bool isForce;
  const UpdateInfo({
    required this.downloadUrl,
    required this.releaseNotes,
    required this.version,
    required this.versionCode,
    this.fileSize = 0,
    this.isForce = false,
  });

  /// 文件大小展示（MB）
  String get fileSizeLabel {
    if (fileSize <= 0) return '';
    return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
  }
}

class UpdateService {
  static const _prefSkippedVersion = 'skipped_update_version';
  static bool _checked = false;

  static UpdateInfo? availableUpdate;

  /// 多监听列表：_AppShell 用于全屏强制更新拦截，chat_screen 用于非强制更新弹窗
  static final List<VoidCallback> _listeners = [];

  /// 注册状态变化监听
  static void addListener(VoidCallback cb) {
    if (!_listeners.contains(cb)) _listeners.add(cb);
  }

  /// 注销状态变化监听
  static void removeListener(VoidCallback cb) {
    _listeners.remove(cb);
  }

  static void _notify() {
    for (final cb in List.of(_listeners)) {
      try {
        cb();
      } catch (e) {
        debugPrint('[Update] listener error: $e');
      }
    }
  }

  /// 是否处于强制更新状态（不可进入主界面）
  static bool get isForceUpdateActive =>
      availableUpdate != null && availableUpdate!.isForce;

  static Future<void> checkUpdate() async {
    if (_checked) return;
    if (kIsWeb) {
      // Web 端无需检查更新，云端即最新
      _checked = true;
      return;
    }

    try {
      final localVersionCode = await _loadLocalVersionCode();
      if (localVersionCode == 0) {
        // 本地配置异常，无需重试
        _checked = true;
        return;
      }

      final url = '${ServerConfig.baseUrl}/api/v1/update/check?platform=${Platform.operatingSystem}&version_code=$localVersionCode';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        // 请求失败，不标记 _checked，允许下次重试
        return;
      }
      // 请求成功，标记已检查（无论是否有更新）
      _checked = true;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] != 0) return;

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null || data['has_update'] != true) return;

      final remoteVersionCode = data['version_code'] as int? ?? 0;
      final isForce = data['is_force'] as bool? ?? false;

      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getString(_prefSkippedVersion) ?? '';
      if (!isForce && skipped == '$remoteVersionCode') return;

      availableUpdate = UpdateInfo(
        downloadUrl: data['download_url'] as String? ?? '',
        releaseNotes: data['release_notes'] as String? ?? '',
        version: data['version'] as String? ?? '',
        versionCode: remoteVersionCode,
        fileSize: (data['file_size'] as num?)?.toInt() ?? 0,
        isForce: isForce,
      );
      _notify();
      debugPrint('[Update] New version available: v${data['version']} (code=$remoteVersionCode) isForce=$isForce');
    } catch (e) {
      debugPrint('[Update] check failed: $e');
      // 异常时不标记 _checked，允许下次重试
    }
  }

  /// 跳过本次更新提示（仅对非强制更新有效）
  static Future<void> skipUpdate() async {
    if (availableUpdate == null) return;
    if (availableUpdate!.isForce) return; // 强制更新不可跳过
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSkippedVersion, '${availableUpdate!.versionCode}');
    availableUpdate = null;
    _notify();
  }

  /// 关闭更新提示（仅对非强制更新有效）
  static void dismiss() {
    if (availableUpdate != null && availableUpdate!.isForce) return; // 强制更新不可关闭
    availableUpdate = null;
    _notify();
  }

  /// 调用系统浏览器下载 APK
  /// 服务端会自动处理：有外部直链时 302 重定向，无直链时返回文件流
  static Future<bool> downloadViaBrowser() async {
    final update = availableUpdate;
    if (update == null || update.downloadUrl.isEmpty) return false;

    final fullUrl = '${ServerConfig.baseUrl}${update.downloadUrl}';
    final uri = Uri.parse(fullUrl);

    try {
      // 优先用外部浏览器打开（会触发系统下载管理器）
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        debugPrint('[Update] Browser launched: $fullUrl');
        // 非强制更新时，启动浏览器后清除提示
        if (!update.isForce) {
          availableUpdate = null;
          _notify();
        }
        return true;
      }
      debugPrint('[Update] launchUrl returned false');
      return false;
    } catch (e) {
      debugPrint('[Update] launch browser failed: $e');
      return false;
    }
  }

  static void reset() {
    _checked = false;
    availableUpdate = null;
    _notify();
  }

  static Future<int> _loadLocalVersionCode() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vision.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return (data['version_code'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
