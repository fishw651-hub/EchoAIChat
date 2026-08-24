import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';
import '../models/user_profile.dart';
import 'device_id_service.dart';

/// 认证与账户 HTTP 服务
/// 封装所有与中继站的认证、用户、额度与充值相关 API。
class AuthService {
  String? _jwtToken;

  void setTokens({String? jwt, String? refresh}) {
    _jwtToken = jwt;
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
  };

  String _url(String path) => '${ServerConfig.baseUrl}$path';

  // ═══════════════════════════════════════════════
  //  认证
  // ═══════════════════════════════════════════════

  /// 注册 → 返回 {user_id, uuid, api_key: {key_id, key_secret, key_preview}}
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
    String? code,
  }) async {
    final body = {
      'username': username,
      'email': email,
      'password': password,
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      if (code != null && code.isNotEmpty) 'code': code,
    };
    return _post('/api/v1/auth/register', body);
  }

  /// 登录 → 返回 {token, refresh_token, expires_in, user, api_key}
  /// [deviceId] 客户端设备指纹，服务器用于账号切换封禁统计
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    return _post('/api/v1/auth/login', {
      'username': username,
      'password': password,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });
  }

  /// 查询设备封禁状态（每次启动调用）→ {banned, ban_until, ban_days}
  Future<Map<String, dynamic>> getDeviceStatus(String deviceId) async {
    return _get(
      '/api/v1/auth/device-status?device_id=${Uri.encodeQueryComponent(deviceId)}',
    );
  }

  /// 刷新 Token → {token, expires_in}
  Future<Map<String, dynamic>> refreshTokenApi(String refreshToken) async {
    return _post('/api/v1/auth/refresh', {'refresh_token': refreshToken});
  }

  /// 发送验证码（purpose: register / reset）
  Future<void> sendCode(String email, String purpose) async {
    await _post('/api/v1/auth/send-code', {'email': email, 'purpose': purpose});
  }

  /// 带验证码注册
  Future<Map<String, dynamic>> registerWithCode({
    required String username,
    required String email,
    required String password,
    required String code,
  }) async {
    return _post('/api/v1/auth/register-with-code', {
      'username': username,
      'email': email,
      'password': password,
      'code': code,
    });
  }

  /// 重置密码
  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    await _post('/api/v1/auth/reset-password', {
      'email': email,
      'code': code,
      'password': newPassword,
    });
  }

  // ═══════════════════════════════════════════════
  //  用户资料
  // ═══════════════════════════════════════════════

  /// 获取当前用户信息
  Future<UserProfile> getCurrentUser() async {
    final data = await _get('/api/v1/user/profile');
    final userJson = data['user'] as Map<String, dynamic>? ?? data;
    return UserProfile.fromJson(userJson);
  }

  /// 更新资料 (nickname, avatar, phone)
  Future<void> updateProfile({
    String? nickname,
    String? avatar,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatar != null) body['avatar'] = avatar;
    if (phone != null) body['phone'] = phone;
    await _put('/api/v1/user/profile', body);
  }

  /// 上传头像 → 返回图片 URL
  Future<String> uploadAvatar(File imageFile) async {
    final uri = Uri.parse(_url('/api/v1/user/avatar'));
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer ${_jwtToken ?? ""}';
    req.files.add(await http.MultipartFile.fromPath('avatar', imageFile.path));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (resp.statusCode == 200 && json['code'] == 0) {
      return json['data']?['avatar_url'] as String? ?? '';
    }
    throw AuthException(json['message'] as String? ?? '上传失败');
  }

  // ═══════════════════════════════════════════════
  //  每日额度
  // ═══════════════════════════════════════════════

  /// 幂等刷新当天免费或订阅额度。
  Future<Map<String, dynamic>> refreshDailyAllowance() async {
    return _post('/api/v1/user/daily-allowance/refresh', const {});
  }

  // ═══════════════════════════════════════════════
  //  余额 / 交易
  // ═══════════════════════════════════════════════

  /// 获取余额
  Future<Map<String, dynamic>> getBalance() async {
    return _get('/api/v1/user/balance');
  }

  /// 获取交易记录
  Future<Map<String, dynamic>> getTransactions({
    int page = 1,
    int pageSize = 20,
    String? type,
  }) async {
    var path = '/api/v1/user/usage?page=$page&page_size=$pageSize';
    if (type != null) path += '&type=$type';
    return _get(path);
  }

  /// 使用统计
  Future<Map<String, dynamic>> getUsageStats() async {
    return _get('/api/v1/account/stats');
  }

  // ═══════════════════════════════════════════════
  //  订阅
  // ═══════════════════════════════════════════════

  /// 订阅计划列表
  Future<List<dynamic>> getSubscriptionPlans() async {
    final resp = await http
        .get(Uri.parse(_url('/api/v1/plans')), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || json['code'] != 0) {
      throw AuthException(json['message'] as String? ?? '获取计划列表失败');
    }
    final data = json['data'];
    if (data is List) return data;
    if (data is Map) return (data['list'] as List?) ?? [];
    return [];
  }

  /// 我的订阅（返回数组，空数组表示无订阅）
  Future<List<dynamic>> getMySubscription() async {
    final resp = await http
        .get(
          Uri.parse(_url('/api/v1/user/subscription')),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 401) {
      throw AuthException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200 || json['code'] != 0) {
      throw AuthException(json['message'] as String? ?? '获取订阅信息失败');
    }
    final data = json['data'];
    // 后端返回 {"subscriptions": [...], "total_quota_left": ...}
    if (data is Map<String, dynamic>) {
      final subs = data['subscriptions'];
      if (subs is List) return subs;
    }
    // 兼容旧版直接返回数组的情况
    if (data is List) return data;
    return [];
  }

  /// 订阅
  Future<Map<String, dynamic>> subscribe(
    int planId, {
    required String paymentType,
  }) async {
    return _post('/api/v1/payment/subscribe', {
      'plan_id': planId,
      'payment_type': paymentType,
    });
  }

  /// 查询订单状态（主动轮询用）
  Future<Map<String, dynamic>> getOrderStatus(String orderNo) async {
    return _get('/api/v1/payment/order/$orderNo');
  }

  /// 获取云端智能体列表
  Future<List<Map<String, dynamic>>> fetchMyAgents() async {
    final resp = await http
        .get(Uri.parse(_url('/api/v1/user/agents')), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 401) {
      throw AuthException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200 || json['code'] != 0) {
      throw AuthException(json['message'] as String? ?? '获取智能体失败');
    }
    final data = json['data'];
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  /// 保存智能体到云端（创建/更新）
  Future<Map<String, dynamic>> saveAgent({
    int? id,
    String? clientId,
    required String name,
    String gender = '',
    String description = '',
    String persona = '',
    String? openingLine,
    int avatarColor = 0xFFE8F5E9,
    String? avatarPath,
    String? chatBackground,
    String worldview = '',
    bool isSimCharacter = false,
    int maxResponseLength = 300,
    bool realInfoEnabled = false,
    bool proactiveCareEnabled = false,
    int proactiveCareDailyLimit = 1,
    int proactiveCareMinIntervalHours = 3,
  }) async {
    final body = <String, dynamic>{
      if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
      'name': name,
      'gender': gender,
      'description': description,
      'persona': persona,
      'opening_line': openingLine ?? '',
      'avatar_color': avatarColor,
      'avatar_path': avatarPath ?? '',
      'chat_background': chatBackground ?? '',
      'worldview': worldview,
      'is_sim_character': isSimCharacter,
      'max_response_length': maxResponseLength,
      'real_info_enabled': realInfoEnabled,
      'proactive_care_enabled': proactiveCareEnabled,
      'proactive_care_daily_limit': proactiveCareDailyLimit,
      'proactive_care_min_interval_hours': proactiveCareMinIntervalHours,
    };
    if (id != null) body['id'] = id;
    return _post('/api/v1/user/agents', body);
  }

  /// 删除云端智能体
  Future<void> deleteCloudAgent(int id) async {
    await _del('/api/v1/user/agents/$id');
  }

  /// 创建充值订单
  Future<Map<String, dynamic>> createRecharge({
    double? amount,
    int? packageId,
    required String paymentMethod,
  }) async {
    final body = <String, dynamic>{'payment_type': paymentMethod};
    if (packageId != null) body['package_id'] = packageId;
    if (amount != null) body['amount'] = amount;
    return _post('/api/v1/payment/zero-drop', body);
  }

  // ═══════════════════════════════════════════════
  //  API Key 管理
  // ═══════════════════════════════════════════════

  /// 列出 API Keys
  Future<List<dynamic>> listApiKeys() async {
    final data = await _get('/api/v1/keys');
    return data['list'] as List? ?? [];
  }

  /// 创建 API Key
  Future<Map<String, dynamic>> createApiKey(String name) async {
    return _post('/api/v1/keys', {'name': name});
  }

  // ═══════════════════════════════════════════════
  //  爱发电支付
  // ═══════════════════════════════════════════════

  Future<List<dynamic>> getIfdianPlans() async {
    final resp = await http
        .get(
          Uri.parse(_url('/api/v1/payment/ifdian/plans')),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || json['code'] != 0) {
      throw AuthException(json['message'] as String? ?? '获取爱发电方案失败');
    }
    final data = json['data'];
    if (data is List) return data;
    return [];
  }

  Future<Map<String, dynamic>> verifyIfdianOrder(String orderNo) async {
    return _post('/api/v1/payment/ifdian/verify', {'out_trade_no': orderNo});
  }

  // ═══════════════════════════════════════════════
  //  多端同步 - 设备管理
  // ═══════════════════════════════════════════════

  /// 注册当前设备（首次注册自动为主机）
  Future<Map<String, dynamic>> registerDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    String clientKind = 'native',
    String browser = '',
  }) async {
    return _post('/api/v1/sync/devices/register', {
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'client_kind': clientKind,
      'browser': browser,
    });
  }

  Future<Map<String, dynamic>> registerCurrentDevice() async {
    final identity = await DeviceIdService.identity;
    return registerDevice(
      deviceId: identity.id,
      deviceName: identity.displayName,
      platform: identity.platform,
      clientKind: identity.clientKind.wireName,
      browser: identity.browser ?? '',
    );
  }

  /// 获取设备列表 + full_sync 状态
  Future<Map<String, dynamic>> listDevices({String? deviceId}) async {
    var path = '/api/v1/sync/devices';
    if (deviceId != null && deviceId.isNotEmpty) {
      path += '?device_id=$deviceId';
    }
    return _get(path);
  }

  /// 设置设备角色（master/slave）
  Future<void> setDeviceRole(String deviceId, String role) async {
    await _put('/api/v1/sync/devices/$deviceId/role', {'role': role});
  }

  /// 修改设备名称
  Future<void> updateDeviceName(String deviceId, String deviceName) async {
    await _put('/api/v1/sync/devices/$deviceId/name', {
      'device_name': deviceName,
    });
  }

  /// 删除设备
  Future<void> deleteDevice(String deviceId) async {
    await _del('/api/v1/sync/devices/$deviceId');
  }

  /// 设置 100% 同步开关
  Future<void> setFullSync(bool enabled) async {
    await _put('/api/v1/sync/devices/full_sync', {'enabled': enabled});
  }

  // ═══════════════════════════════════════════════
  //  内部 HTTP 方法
  // ═══════════════════════════════════════════════

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http
        .get(Uri.parse(_url(path)), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    return _handleResponse(resp);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await http
        .post(
          Uri.parse(_url(path)),
          headers: _authHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _handleResponse(resp);
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await http
        .put(
          Uri.parse(_url(path)),
          headers: _authHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _handleResponse(resp);
  }

  Future<void> _del(String path) async {
    final resp = await http
        .delete(Uri.parse(_url(path)), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      throw AuthException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      throw AuthException(json['message'] as String? ?? '请求失败');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response resp) {
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;

    if (resp.statusCode == 401) {
      throw AuthException('登录已过期，请重新登录', isUnauthorized: true);
    }
    if (resp.statusCode != 200 || code != 0) {
      final msg = json['message'] as String? ?? '请求失败';
      // 检测余额不足
      if (msg.contains('余额不足')) {
        throw InsufficientBalanceException(msg);
      }
      throw AuthException(msg);
    }
    return json['data'] as Map<String, dynamic>? ?? {};
  }
}

/// 认证异常
class AuthException implements Exception {
  final String message;
  final bool isUnauthorized;
  const AuthException(this.message, {this.isUnauthorized = false});
  @override
  String toString() => message;
}

/// 余额不足异常
class InsufficientBalanceException implements Exception {
  final String message;
  const InsufficientBalanceException(this.message);
  @override
  String toString() => message;
}
