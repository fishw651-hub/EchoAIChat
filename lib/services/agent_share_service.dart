import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';
import '../models/agent.dart';
import 'agent_export_service.dart';

/// 分享码创建结果
class AgentShareResult {
  final String code;
  final String expiresAt;

  const AgentShareResult({required this.code, required this.expiresAt});

  /// 解析后的过期时间（服务器时间字符串无法解析时为 null）
  DateTime? get expiresAtParsed => DateTime.tryParse(expiresAt);
}

/// 分享快照：承载智能体核心字段（含头像 base64 data URI）
/// 字段命名与 AgentExportService 导出格式保持一致，避免两套字段漂移
class SharedAgentSnapshot {
  final String name;
  final String gender;
  final String description;
  final String persona;
  final String? openingLine;
  final int avatarColor;
  final String? avatar; // data:image/...;base64,... 或 null
  final String? chatBackground; // #颜色 / data URI / null
  final String worldview;
  final int maxResponseLength;

  const SharedAgentSnapshot({
    required this.name,
    this.gender = '',
    this.description = '',
    required this.persona,
    this.openingLine,
    this.avatarColor = 0xFFE8F5E9,
    this.avatar,
    this.chatBackground,
    this.worldview = '',
    this.maxResponseLength = Agent.defaultResponseLength,
  });

  /// 兼容两种输入：内层 agent map，或 {version, agent: {...}} 包装
  factory SharedAgentSnapshot.fromJson(Map<String, dynamic> json) {
    final a = json['agent'] is Map<String, dynamic>
        ? json['agent'] as Map<String, dynamic>
        : json;
    return SharedAgentSnapshot(
      name: a['name'] as String? ?? '',
      gender: a['gender'] as String? ?? '',
      description: a['description'] as String? ?? '',
      persona: a['persona'] as String? ?? '',
      openingLine: a['opening_line'] as String?,
      avatarColor: a['avatar_color'] as int? ?? 0xFFE8F5E9,
      avatar: a['avatar'] as String?,
      chatBackground: a['chat_background'] as String?,
      worldview: a['worldview'] as String? ?? '',
      maxResponseLength:
          (a['max_response_length'] as num?)?.toInt() ??
          Agent.defaultResponseLength,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'gender': gender,
    'description': description,
    'persona': persona,
    'opening_line': openingLine,
    'avatar_color': avatarColor,
    'avatar': avatar,
    'chat_background': chatBackground,
    'worldview': worldview,
    'max_response_length': maxResponseLength,
  };

  /// 转为 AgentExportService.importAgent 期望的包装格式
  Map<String, dynamic> toExportData() => {'version': 1, 'agent': toJson()};
}

class AgentShareException implements Exception {
  final String message;
  final bool isUnauthorized;
  const AgentShareException(this.message, {this.isUnauthorized = false});
  @override
  String toString() => message;
}

/// 智能体分享服务
/// POST /user/share/agent 创建分享码；POST /user/share/redeem 兑换快照
class AgentShareService {
  final http.Client _client;
  final String _baseUrl;
  String? _token;

  AgentShareService({http.Client? client, String? baseUrl, String? token})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ServerConfig.baseUrl,
      _token = token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// 组装分享快照（复用导出格式）。
  /// 头像文件读取失败时降级为无头像快照，不抛异常。
  static Future<Map<String, dynamic>> buildSnapshot(Agent agent) async {
    try {
      final data = await AgentExportService.exportAgent(agent);
      // exportAgent 未写出的字段在此补全，与 importAgent 的读取口径对齐
      final a = data['agent'] as Map<String, dynamic>;
      a['opening_line'] ??= agent.openingLine;
      a['worldview'] ??= agent.worldview;
      a['is_sim_character'] ??= agent.isSimCharacter;
      a['is_group_only'] ??= agent.isGroupOnly;
      a['real_info_enabled'] ??= agent.realInfoEnabled;
      a['max_response_length'] ??= agent.maxResponseLength;
      return data;
    } catch (_) {
      return {
        'version': 1,
        'agent': {
          'name': agent.name,
          'gender': agent.gender,
          'description': agent.description,
          'persona': agent.persona,
          'opening_line': agent.openingLine,
          'avatar_color': agent.avatarColor,
          'avatar': null,
          'chat_background': (agent.chatBackground?.startsWith('#') ?? false)
              ? agent.chatBackground
              : null,
          'worldview': agent.worldview,
          'max_response_length': agent.maxResponseLength,
        },
      };
    }
  }

  /// 创建分享码（20 分钟有效，有效期内可多人兑换）
  Future<AgentShareResult> createShare(Agent agent) async {
    final snapshot = await buildSnapshot(agent);
    final data = await _post('/api/v1/user/share/agent', snapshot);
    return AgentShareResult(
      code: data['code']?.toString() ?? '',
      expiresAt: data['expires_at']?.toString() ?? '',
    );
  }

  /// 用分享码兑换智能体快照
  Future<SharedAgentSnapshot> redeemShare(String code) async {
    final data = await _post('/api/v1/user/share/redeem', {'code': code});
    final agent = data['agent'];
    if (agent is! Map<String, dynamic>) {
      throw AgentShareException('服务器响应解析失败');
    }
    return SharedAgentSnapshot.fromJson(agent);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw AgentShareException('网络连接失败，请检查网络');
    } on TimeoutException {
      throw AgentShareException('请求超时，请稍后重试');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw AgentShareException('服务器响应解析失败');
    }
    if (resp.statusCode == 401) {
      throw AgentShareException('登录已过期，请重新登录', isUnauthorized: true);
    }
    // 服务器 utils/response 包装格式：code==0 为成功
    final code = json['code'];
    if (resp.statusCode != 200 || (code is num && code != 0)) {
      throw AgentShareException(json['message']?.toString() ?? '请求失败');
    }
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    return json;
  }
}
