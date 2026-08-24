import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

/// 网络市场 HTTP 服务
/// 封装智能体/群聊市场的所有列表、详情、下载、上传、编辑、下架 API
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  String get _baseUrl => ServerConfig.baseUrl;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  /// 401 全局回调（由 UI 层设置为静默重登）：返回 true=登录态已恢复，
  /// 此时用 [tokenProvider] 取新 token 重发一次原请求；false=会话已过期。
  Future<bool> Function()? onUnauthorized;

  /// 提供当前最新 token（静默重登后 token 已变更）。
  String? Function()? tokenProvider;

  /// 测试注入点：设置后请求走该 client，不访问真实服务器。
  @visibleForTesting
  static http.Client? testClient;

  Map<String, String> _headers({bool noCache = false}) => {
    'Content-Type': 'application/json',
    if (noCache) 'Cache-Control': 'no-cache',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String _url(String path) => '$_baseUrl$path';

  // ═══════════════════════════════════════════════
  //  标签
  // ═══════════════════════════════════════════════

  /// 获取预设标签列表
  Future<List<String>> getPresetTags() async {
    final data = await _get('/api/v1/network/tags');
    final list = data['list'] as List? ?? data['tags'] as List? ?? [];
    return list.map((e) => e.toString()).toList();
  }

  // ═══════════════════════════════════════════════
  //  智能体市场
  // ═══════════════════════════════════════════════

  /// 智能体列表
  /// 返回 {list: [...], total: N, page: 1, page_size: 20}
  Future<Map<String, dynamic>> listAgents({
    String? q,
    List<String>? tags,
    int page = 1,
    int pageSize = 20,
    String sort = 'newest',
    bool forceRefresh = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      'sort': sort,
    };
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (tags != null && tags.isNotEmpty) {
      query['tags'] = tags.join(',');
    }
    if (forceRefresh) {
      query['_refresh'] = DateTime.now().microsecondsSinceEpoch.toString();
    }
    return _get(
      '/api/v1/network/agents?${_encodeQuery(query)}',
      noCache: forceRefresh,
    );
  }

  /// 智能体详情
  Future<Map<String, dynamic>> getAgentDetail(int id) async {
    return _get('/api/v1/network/agents/$id');
  }

  /// 下载智能体
  /// 返回 {type: 'agent', version: N, agent: {...}}
  Future<Map<String, dynamic>> downloadAgent(int id) async {
    return _post('/api/v1/network/agents/$id/download', {});
  }

  // ═══════════════════════════════════════════════
  //  群聊市场
  // ═══════════════════════════════════════════════

  /// 群聊列表
  /// 返回 {list: [...], total: N, page: 1, page_size: 20}
  Future<Map<String, dynamic>> listGroups({
    String? q,
    List<String>? tags,
    int page = 1,
    int pageSize = 20,
    String sort = 'newest',
    bool forceRefresh = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      'sort': sort,
    };
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (tags != null && tags.isNotEmpty) {
      query['tags'] = tags.join(',');
    }
    if (forceRefresh) {
      query['_refresh'] = DateTime.now().microsecondsSinceEpoch.toString();
    }
    return _get(
      '/api/v1/network/groups?${_encodeQuery(query)}',
      noCache: forceRefresh,
    );
  }

  /// 群聊详情
  Future<Map<String, dynamic>> getGroupDetail(int id) async {
    return _get('/api/v1/network/groups/$id');
  }

  /// 下载群聊
  /// 返回 {type: 'group', version: N, group: {...}, members: [...]}
  Future<Map<String, dynamic>> downloadGroup(int id) async {
    return _post('/api/v1/network/groups/$id/download', {});
  }

  // ═══════════════════════════════════════════════
  //  我上传的
  // ═══════════════════════════════════════════════

  /// 我上传的智能体列表
  Future<List<Map<String, dynamic>>> listMyAgentUploads() async {
    final data = await _get('/api/v1/network/my/agents');
    return _asList(data);
  }

  /// 我上传的群聊列表
  Future<List<Map<String, dynamic>>> listMyGroupUploads() async {
    final data = await _get('/api/v1/network/my/groups');
    return _asList(data);
  }

  Future<List<Map<String, dynamic>>> listMyReviewStatuses() async {
    final data = await _get('/api/v1/network/my/review-statuses');
    return _asList(data);
  }

  // ═══════════════════════════════════════════════
  //  上传 / 编辑 / 下架
  // ═══════════════════════════════════════════════

  /// 上传智能体
  Future<Map<String, dynamic>> uploadAgent(Map<String, dynamic> data) async {
    return _post('/api/v1/network/agents', data);
  }

  /// 上传群聊
  Future<Map<String, dynamic>> uploadGroup(Map<String, dynamic> data) async {
    return _post('/api/v1/network/groups', data);
  }

  /// 编辑智能体
  Future<Map<String, dynamic>> editAgent(
    int id,
    Map<String, dynamic> data,
  ) async {
    return _put('/api/v1/network/agents/$id', data);
  }

  /// 编辑群聊
  Future<Map<String, dynamic>> editGroup(
    int id,
    Map<String, dynamic> data,
  ) async {
    return _put('/api/v1/network/groups/$id', data);
  }

  /// 下架智能体
  Future<void> takeDownAgent(int id) async {
    await _del('/api/v1/network/agents/$id');
  }

  /// 下架群聊
  Future<void> takeDownGroup(int id) async {
    await _del('/api/v1/network/groups/$id');
  }

  // ═══════════════════════════════════════════════
  //  内部 HTTP 方法
  // ═══════════════════════════════════════════════

  Future<Map<String, dynamic>> _get(
    String path, {
    bool isAuthRetry = false,
    bool noCache = false,
  }) async {
    final injectedClient = testClient;
    final client = injectedClient ?? http.Client();
    try {
      final resp = await client
          .get(Uri.parse(_url(path)), headers: _headers(noCache: noCache))
          .timeout(const Duration(seconds: 15));
      return _handleResponse(resp);
    } on NetworkException catch (e) {
      if (e.isUnauthorized && !isAuthRetry && await _tryRestoreUnauthorized()) {
        return _get(path, isAuthRetry: true, noCache: noCache);
      }
      rethrow;
    } on SocketException {
      throw NetworkException('网络连接失败，请检查网络');
    } on TimeoutException {
      throw NetworkException('请求超时，请稍后重试');
    } finally {
      if (injectedClient == null) client.close();
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool isAuthRetry = false,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse(_url(path)),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(resp);
    } on NetworkException catch (e) {
      if (e.isUnauthorized && !isAuthRetry && await _tryRestoreUnauthorized()) {
        return _post(path, body, isAuthRetry: true);
      }
      rethrow;
    } on SocketException {
      throw NetworkException('网络连接失败，请检查网络');
    } on TimeoutException {
      throw NetworkException('请求超时，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body, {
    bool isAuthRetry = false,
  }) async {
    try {
      final resp = await http
          .put(
            Uri.parse(_url(path)),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(resp);
    } on NetworkException catch (e) {
      if (e.isUnauthorized && !isAuthRetry && await _tryRestoreUnauthorized()) {
        return _put(path, body, isAuthRetry: true);
      }
      rethrow;
    } on SocketException {
      throw NetworkException('网络连接失败，请检查网络');
    } on TimeoutException {
      throw NetworkException('请求超时，请稍后重试');
    }
  }

  Future<void> _del(String path, {bool isAuthRetry = false}) async {
    try {
      final resp = await http
          .delete(Uri.parse(_url(path)), headers: _headers())
          .timeout(const Duration(seconds: 15));
      _handleResponseVoid(resp);
    } on NetworkException catch (e) {
      if (e.isUnauthorized && !isAuthRetry && await _tryRestoreUnauthorized()) {
        return _del(path, isAuthRetry: true);
      }
      rethrow;
    } on SocketException {
      throw NetworkException('网络连接失败，请检查网络');
    } on TimeoutException {
      throw NetworkException('请求超时，请稍后重试');
    }
  }

  /// 401 后尝试静默重登并用最新 token 刷新本实例。返回 true=可重发一次。
  Future<bool> _tryRestoreUnauthorized() async {
    final callback = onUnauthorized;
    if (callback == null) return false;
    final restored = await callback();
    if (!restored) return false;
    final fresh = tokenProvider?.call();
    if (fresh != null && fresh.isNotEmpty) {
      _token = fresh;
    }
    return true;
  }

  Map<String, dynamic> _handleResponse(http.Response resp) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw NetworkException('服务器响应解析失败');
    }
    final code = json['code'] as int? ?? -1;

    if (resp.statusCode == 401) {
      // 由调用方（_get/_post/_put/_del）触发静默重登并重发
      throw NetworkException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200 || code != 0) {
      final msg = json['message'] as String? ?? '请求失败';
      throw NetworkException(msg);
    }
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    if (data == null) return {};
    // data 是其他类型（List 等），包装成 Map 返回
    return {'data': data};
  }

  void _handleResponseVoid(http.Response resp) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw NetworkException('服务器响应解析失败');
    }
    final code = json['code'] as int? ?? -1;
    if (resp.statusCode == 401) {
      throw NetworkException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200 || code != 0) {
      throw NetworkException(json['message'] as String? ?? '请求失败');
    }
  }

  List<Map<String, dynamic>> _asList(Map<String, dynamic> data) {
    final list = data['list'] ?? data['data'];
    if (list is List) return list.cast<Map<String, dynamic>>();
    return [];
  }

  String _encodeQuery(Map<String, String> query) {
    if (query.isEmpty) return '';
    final parts = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return parts;
  }
}

/// 网络市场异常
class NetworkException implements Exception {
  final String message;
  final bool isUnauthorized;
  const NetworkException(this.message, {this.isUnauthorized = false});
  @override
  String toString() => message;
}
