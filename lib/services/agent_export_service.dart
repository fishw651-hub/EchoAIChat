import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as pp;
import '../config/server_config.dart';
import '../models/agent.dart';
import 'database_service.dart';
import 'network_copy_policy.dart';

class AgentExportService {
  static Future<Map<String, dynamic>> exportAgent(Agent agent) async {
    final Map<String, dynamic> data = {
      'version': 1,
      'agent': {
        'name': agent.name,
        'gender': agent.gender,
        'description': agent.description,
        'persona': agent.persona,
        'opening_line': agent.openingLine,
        'worldview': agent.worldview,
        'is_sim_character': agent.isSimCharacter,
        'is_group_only': agent.isGroupOnly,
        'real_info_enabled': agent.realInfoEnabled,
        'max_response_length': agent.maxResponseLength,
        'avatar_color': agent.avatarColor,
        'avatar': null,
        'chat_background': null,
      },
    };

    if (agent.avatarPath != null &&
        agent.avatarPath!.isNotEmpty &&
        File(agent.avatarPath!).existsSync()) {
      final bytes = await File(agent.avatarPath!).readAsBytes();
      final ext = agent.avatarPath!.split('.').last;
      data['agent']['avatar'] =
          'data:image/${ext == 'png' ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
    }

    if (agent.chatBackground != null && agent.chatBackground!.isNotEmpty) {
      if (agent.chatBackground!.startsWith('#')) {
        data['agent']['chat_background'] = agent.chatBackground;
      } else if (File(agent.chatBackground!).existsSync()) {
        final bytes = await File(agent.chatBackground!).readAsBytes();
        final ext = agent.chatBackground!.split('.').last;
        data['agent']['chat_background'] =
            'data:image/${ext == 'png' ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
      }
    }

    return data;
  }

  static Future<Agent> importAgent(Map<String, dynamic> data) async {
    final a = data['agent'] as Map<String, dynamic>;
    final dir = await pp.getApplicationDocumentsDirectory();

    String? avatarPath;
    final avatarData = a['avatar'] as String?;
    if (avatarData != null && avatarData.startsWith('data:image/')) {
      final parts = avatarData.split(';base64,');
      if (parts.length == 2) {
        final mime = parts[0].replaceFirst('data:', '');
        final ext = mime.contains('png') ? 'png' : 'jpg';
        final bytes = base64Decode(parts[1]);
        final path =
            '${dir.path}/avatar_import_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(path).writeAsBytes(bytes);
        avatarPath = path;
      }
    }

    String? chatBg;
    final bgData = a['chat_background'] as String?;
    if (bgData != null) {
      if (bgData.startsWith('#')) {
        chatBg = bgData;
      } else if (bgData.startsWith('data:image/')) {
        final parts = bgData.split(';base64,');
        if (parts.length == 2) {
          final mime = parts[0].replaceFirst('data:', '');
          final ext = mime.contains('png') ? 'png' : 'jpg';
          final bytes = base64Decode(parts[1]);
          final path =
              '${dir.path}/bg_import_${DateTime.now().millisecondsSinceEpoch}.$ext';
          await File(path).writeAsBytes(bytes);
          chatBg = path;
        }
      }
    }

    return Agent(
      name: a['name'] as String? ?? 'Imported',
      gender: a['gender'] as String? ?? '',
      description: a['description'] as String? ?? '',
      persona: a['persona'] as String? ?? '',
      openingLine: a['opening_line'] as String?,
      avatarColor: a['avatar_color'] as int? ?? 0xFFE8F5E9,
      avatarPath: avatarPath,
      chatBackground: chatBg,
      worldview: a['worldview'] as String? ?? '',
      isSimCharacter: a['is_sim_character'] as bool? ?? false,
      isGroupOnly: a['is_group_only'] as bool? ?? false,
      realInfoEnabled: a['real_info_enabled'] as bool? ?? false,
      maxResponseLength:
          (a['max_response_length'] as num?)?.toInt() ??
          Agent.defaultResponseLength,
    );
  }

  // ═══════════════════════════════════════════════
  //  网络市场专用方法（独立格式，不破坏 v1 兼容）
  // ═══════════════════════════════════════════════

  /// 序列化智能体为上传格式
  /// 上传格式不含 version 字段（由服务端管理）
  /// avatar 读取本地文件转 base64 data URI
  static Future<Map<String, dynamic>> serializeForUpload(Agent agent) async {
    final data = <String, dynamic>{
      'name': agent.name,
      'gender': agent.gender,
      'description': agent.description,
      'persona': agent.persona,
      'opening_line': agent.openingLine ?? '',
      'worldview': agent.worldview,
      'max_response_length': agent.maxResponseLength,
      'avatar_color': agent.avatarColor,
      'avatar_path': agent.avatarPath ?? '',
      'chat_background': agent.chatBackground ?? '',
      'tags': <String>[], // 由调用方填充
    };

    // avatar 读取本地文件转 base64 data URI
    final avatarBase64 = await _encodeAvatarBase64(agent.avatarPath);
    if (avatarBase64 != null) {
      data['avatar'] = avatarBase64;
    }

    // chat_background: 颜色直接保留；本地文件转 base64
    final bg = agent.chatBackground;
    if (bg != null &&
        bg.isNotEmpty &&
        !bg.startsWith('#') &&
        !bg.startsWith('data:image/')) {
      final bgBase64 = await _encodeFileBase64(bg);
      if (bgBase64 != null) {
        data['chat_background'] = bgBase64;
      }
    }

    return data;
  }

  /// 反序列化下载的智能体数据，写入本地数据库
  /// 返回新创建、已存在或被完整市场数据修复的 Agent。
  /// data 格式：{type: 'agent', version: N, agent: {...}}
  static Future<Agent> deserializeDownloaded(Map<String, dynamic> data) async {
    final a = data['agent'] as Map<String, dynamic>? ?? data;

    final name = a['name'] as String? ?? '导入的智能体';
    final persona = a['persona'] as String? ?? '';
    final openingLine = a['opening_line'] as String?;
    final networkId = (a['id'] as num?)?.toInt();
    final networkUploaderId = (a['uploader_id'] as num?)?.toInt();
    final networkVersion =
        (data['version'] as num?)?.toInt() ?? (a['version'] as num?)?.toInt();

    // 只按网络作品 ID 去重，不能复用同名本地原创，否则会绕过下载副本禁传规则。
    Agent? existing;
    if (networkId != null) {
      existing = await findDownloadedAgent(networkId);
      if (existing != null && hasCompleteDownloadedContent(existing)) {
        return existing;
      }
    }

    if (persona.trim().isEmpty ||
        openingLine == null ||
        openingLine.trim().isEmpty) {
      throw const FormatException('下载内容缺少人设或开场白，请稍后重试');
    }

    // 下载 avatar 到本地：优先 base64，其次 avatar_path 相对路径
    final avatarSource = (a['avatar'] as String?)?.isNotEmpty == true
        ? a['avatar'] as String?
        : a['avatar_path'] as String?;
    final avatarPath = await _downloadAvatar(avatarSource);

    // 处理 chat_background
    String? chatBg;
    final bgRaw = a['chat_background'] as String?;
    if (bgRaw != null && bgRaw.isNotEmpty) {
      if (bgRaw.startsWith('#')) {
        chatBg = bgRaw;
      } else if (bgRaw.startsWith('data:image/')) {
        chatBg = await _saveBase64ToFile(bgRaw, 'bg');
      } else if (bgRaw.startsWith('http://') || bgRaw.startsWith('https://')) {
        chatBg = await _downloadUrlToFile(bgRaw, 'bg');
      } else if (bgRaw.startsWith('/')) {
        // 服务端相对路径（/uploads/...）拼接 baseUrl 下载
        chatBg = await _downloadUrlToFile(
          '${ServerConfig.baseUrl}$bgRaw',
          'bg',
        );
      }
    }

    final agent = Agent(
      id: existing?.id,
      name: name,
      gender: a['gender'] as String? ?? '',
      description: a['description'] as String? ?? '',
      persona: persona,
      openingLine: openingLine,
      avatarColor: a['avatar_color'] as int? ?? 0xFFE8F5E9,
      avatarPath: avatarPath ?? existing?.avatarPath,
      chatBackground: chatBg ?? existing?.chatBackground,
      worldview: a['worldview'] as String? ?? '',
      maxResponseLength:
          (a['max_response_length'] as num?)?.toInt() ??
          Agent.defaultResponseLength,
      isActive: existing?.isActive ?? false,
      networkId: networkId,
      networkUploaderId: networkUploaderId ?? existing?.networkUploaderId,
      networkSource: NetworkCopySource.downloaded,
      networkVersion: networkVersion ?? existing?.networkVersion,
      // 网络市场内容不得自动获得本地用户画像或真实信息。
      realInfoEnabled: false,
      proactiveCareEnabled: false,
      createdAt: existing?.createdAt,
    );

    if (existing == null) {
      await DatabaseService.insertAgent(agent);
    } else {
      await DatabaseService.updateAgent(agent);
    }
    return agent;
  }

  static bool hasCompleteDownloadedContent(Agent agent) {
    return agent.persona.trim().isNotEmpty &&
        agent.openingLine?.trim().isNotEmpty == true;
  }

  /// 返回本地已下载的同一网络智能体；本地原创同名智能体不会匹配。
  static Future<Agent?> findDownloadedAgent(int networkId) async {
    final agents = await DatabaseService.getAgents();
    for (final agent in agents) {
      if (agent.networkSource == NetworkCopySource.downloaded &&
          agent.networkId == networkId) {
        return agent;
      }
    }
    return null;
  }

  /// 读取本地文件转 base64 data URI
  static Future<String?> _encodeAvatarBase64(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _encodeFileBase64(path);
  }

  static Future<String?> _encodeFileBase64(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  /// 下载头像到本地文件
  /// 支持 data:image/...;base64,... 和 http(s):// URL 与相对路径
  static Future<String?> _downloadAvatar(String? source) async {
    if (source == null || source.isEmpty) return null;
    return _downloadSourceToFile(source, 'avatar');
  }

  static Future<String?> _downloadSourceToFile(
    String source,
    String prefix,
  ) async {
    final dir = await pp.getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // data:image/...;base64,...
    if (source.startsWith('data:image/')) {
      final parts = source.split(';base64,');
      if (parts.length == 2) {
        final mime = parts[0].replaceFirst('data:', '');
        final ext = mime.contains('png') ? 'png' : 'jpg';
        try {
          final bytes = base64Decode(parts[1]);
          final path = '${dir.path}/${prefix}_$ts.$ext';
          await File(path).writeAsBytes(bytes);
          return path;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    // http(s):// URL
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return _downloadUrlToFile(source, prefix);
    }

    // 相对路径（基于 baseUrl）：/uploads/... 或 uploads/...
    if (source.startsWith('/')) {
      try {
        final url = '${ServerConfig.baseUrl}$source';
        return await _downloadUrlToFile(url, prefix);
      } catch (_) {
        return null;
      }
    }
    try {
      final url = '${ServerConfig.baseUrl}/$source';
      return await _downloadUrlToFile(url, prefix);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _downloadUrlToFile(String url, String prefix) async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final dir = await pp.getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final contentType = resp.headers['content-type'] ?? '';
        final ext = contentType.contains('png') ? 'png' : 'jpg';
        final path = '${dir.path}/${prefix}_$ts.$ext';
        await File(path).writeAsBytes(resp.bodyBytes);
        return path;
      }
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<String?> _saveBase64ToFile(
    String dataUri,
    String prefix,
  ) async {
    final parts = dataUri.split(';base64,');
    if (parts.length != 2) return null;
    final mime = parts[0].replaceFirst('data:', '');
    final ext = mime.contains('png') ? 'png' : 'jpg';
    try {
      final dir = await pp.getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final bytes = base64Decode(parts[1]);
      final path = '${dir.path}/${prefix}_$ts.$ext';
      await File(path).writeAsBytes(bytes);
      return path;
    } catch (_) {
      return null;
    }
  }
}
