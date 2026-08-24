import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/server_config.dart';
import 'client_protocol.dart';

/// 功能配额类型
enum QuotaType { ocr, realReply }

extension QuotaTypeExt on QuotaType {
  String get apiValue => this == QuotaType.ocr ? 'ocr' : 'real_reply';
  String get label => this == QuotaType.ocr ? '聊天记录识别' : '真实回复';
}

/// 单项配额使用情况
class QuotaUsage {
  final int used;
  final int quota;
  final int remaining; // -1 表示无限
  final bool unlimited;
  final int? subscriptionId; // 关联的订阅 ID（consume 返回时携带）

  const QuotaUsage({
    required this.used,
    required this.quota,
    required this.remaining,
    required this.unlimited,
    this.subscriptionId,
  });

  factory QuotaUsage.fromJson(Map<String, dynamic> j) => QuotaUsage(
    used: (j['used'] as num?)?.toInt() ?? 0,
    quota: (j['quota'] as num?)?.toInt() ?? 0,
    remaining: (j['remaining'] as num?)?.toInt() ?? 0,
    unlimited: (j['unlimited'] as bool?) ?? false,
    subscriptionId: (j['subscription_id'] as num?)?.toInt(),
  );
}

/// 单个订阅的配额视图
class SubscriptionQuota {
  final int id;
  final int planId;
  final String planName;
  final String expiresAt;
  final QuotaUsage ocr;
  final QuotaUsage realReply;

  const SubscriptionQuota({
    required this.id,
    required this.planId,
    required this.planName,
    required this.expiresAt,
    required this.ocr,
    required this.realReply,
  });

  factory SubscriptionQuota.fromJson(Map<String, dynamic> j) =>
      SubscriptionQuota(
        id: (j['id'] as num?)?.toInt() ?? 0,
        planId: (j['plan_id'] as num?)?.toInt() ?? 0,
        planName: j['plan_name'] as String? ?? '',
        expiresAt: j['expires_at'] as String? ?? '',
        ocr: QuotaUsage.fromJson(j['ocr'] as Map<String, dynamic>),
        realReply: QuotaUsage.fromJson(j['real_reply'] as Map<String, dynamic>),
      );
}

/// 配额快照（含 OCR + 真实回复 聚合视图 + 按订阅明细）
class QuotaSnapshot {
  final QuotaUsage ocr; // 聚合（用于客户端预检）
  final QuotaUsage realReply; // 聚合
  final String resetDate;
  final List<SubscriptionQuota> subscriptions; // per-subscription 明细
  final int defaultOcr; // 系统默认 OCR 配额（无订阅时使用）
  final int defaultRealReply; // 系统默认真实回复配额（无订阅时使用）

  const QuotaSnapshot({
    required this.ocr,
    required this.realReply,
    required this.resetDate,
    required this.subscriptions,
    this.defaultOcr = 3,
    this.defaultRealReply = 30,
  });

  factory QuotaSnapshot.fromJson(Map<String, dynamic> j) {
    final subsJson = j['subscriptions'] as List<dynamic>? ?? [];
    return QuotaSnapshot(
      ocr: QuotaUsage.fromJson(j['ocr'] as Map<String, dynamic>),
      realReply: QuotaUsage.fromJson(j['real_reply'] as Map<String, dynamic>),
      resetDate: j['reset_date'] as String? ?? '',
      subscriptions: subsJson
          .map((e) => SubscriptionQuota.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultOcr: (j['default_ocr'] as num?)?.toInt() ?? 3,
      defaultRealReply: (j['default_real_reply'] as num?)?.toInt() ?? 30,
    );
  }
}

/// 配额耗尽异常
class QuotaExceededException implements Exception {
  final String message;
  final QuotaType type;
  const QuotaExceededException(this.message, this.type);
  @override
  String toString() => message;
}

/// 鉴权头提供器（由上层注入 JWT）
typedef AuthHeaderProvider = Map<String, String> Function();

/// 配额缓存账号提供器（由上层注入稳定的用户标识）
typedef QuotaCacheOwnerProvider = String? Function();

/// 功能配额服务（客户端计数 + 服务端校验）
class QuotaService {
  QuotaService._({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ServerConfig.baseUrl;
  static final QuotaService instance = QuotaService._();

  @visibleForTesting
  factory QuotaService.forTesting({
    required String baseUrl,
    required http.Client client,
  }) => QuotaService._(baseUrl: baseUrl, client: client);

  final http.Client _client;
  final String _baseUrl;
  QuotaSnapshot? _lastSnapshot;
  DateTime? _lastSnapshotAt;
  String? _lastSnapshotOwner;

  /// 上层在登录后注入鉴权头提供器
  AuthHeaderProvider? authHeaderProvider;

  /// 防止切换账号后复用前一个账号的内存或本地配额缓存。
  QuotaCacheOwnerProvider? cacheOwnerProvider;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    ...ClientProtocol.currentHeaders,
    if (authHeaderProvider != null) ...authHeaderProvider!(),
  };

  String _url(String path) => '$_baseUrl$path';

  /// 拉取服务端最新配额使用情况，并同步本地缓存
  Future<QuotaSnapshot> getUsage({Duration? cacheMaxAge}) async {
    final cached = _lastSnapshot;
    final cachedAt = _lastSnapshotAt;
    final cacheOwner = _currentCacheOwner;
    if (cacheMaxAge != null &&
        cached != null &&
        cachedAt != null &&
        _lastSnapshotOwner == cacheOwner &&
        !DateTime.now().isAfter(cachedAt.add(cacheMaxAge))) {
      return cached;
    }

    final resp = await _client
        .get(Uri.parse(_url('/api/v1/quota/usage')), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || json['code'] != 0) {
      throw Exception(json['message'] as String? ?? '获取配额失败');
    }
    final snap = QuotaSnapshot.fromJson(json['data'] as Map<String, dynamic>);
    _lastSnapshot = snap;
    _lastSnapshotAt = DateTime.now();
    _lastSnapshotOwner = cacheOwner;
    await _cacheSnapshot(snap);
    return snap;
  }

  /// 服务端事件只表示权威数据已变化；清除当前账号缓存后由可见页面重新拉取。
  Future<void> invalidateCache() async {
    _invalidateSnapshot();
    final prefs = await SharedPreferences.getInstance();
    if (!_cacheBelongsToCurrentOwner(prefs)) return;
    for (final key in <String>[
      _kOcrUsed,
      _kOcrQuota,
      _kOcrUnlimited,
      _kRealUsed,
      _kRealQuota,
      _kRealUnlimited,
      _kResetDate,
    ]) {
      await prefs.remove(key);
    }
  }

  /// 消耗一次配额；返回该项最新使用情况
  /// 优先用本地缓存快速预判，再调服务端原子自增
  /// [subscriptionId] 可选：指定扣减的订阅 ID；不传由服务端按"过期最近优先"自动选择
  Future<QuotaUsage> consume(QuotaType type, {int? subscriptionId}) async {
    // 本地预检：避免明显超额还浪费一次请求
    final cached = await _loadCachedUsage(type);
    if (cached != null && !cached.unlimited && cached.remaining <= 0) {
      throw QuotaExceededException('今日${type.label}配额已用完，订阅后可获得更多次数', type);
    }

    final body = <String, dynamic>{'type': type.apiValue};
    if (subscriptionId != null) body['subscription_id'] = subscriptionId;

    final resp = await _client
        .post(
          Uri.parse(_url('/api/v1/quota/consume')),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;

    if (resp.statusCode == 400 || code != 0) {
      final msg = json['message'] as String? ?? '配额校验失败';
      if (msg.contains('配额已用完') || msg.contains('已用完')) {
        await _markExhausted(type);
        throw QuotaExceededException(msg, type);
      }
      throw Exception(msg);
    }

    final usage = QuotaUsage.fromJson(
      json['data'][type.apiValue] as Map<String, dynamic>,
    );
    await _cacheUsage(type, usage);
    _invalidateSnapshot();
    return usage;
  }

  Future<String> claimProactiveCare(String clientAgentId) async {
    final resp = await _client
        .post(
          Uri.parse(_url('/api/v1/quota/proactive/claim')),
          headers: _headers,
          body: jsonEncode({'client_agent_id': clientAgentId}),
        )
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || (json['code'] as int? ?? -1) != 0) {
      throw Exception(json['message'] as String? ?? '主动关心 claim 失败');
    }
    final token =
        (json['data'] as Map<String, dynamic>)['claim_token'] as String?;
    if (token == null || token.isEmpty) throw Exception('主动关心 claim 响应无 token');
    return token;
  }

  Future<void> releaseProactiveCare(String claimToken) async {
    try {
      await _client
          .post(
            Uri.parse(_url('/api/v1/quota/proactive/release')),
            headers: _headers,
            body: jsonEncode({'claim_token': claimToken}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  本地缓存（用于离线快速预判，权威值仍以服务端为准）
  // ═══════════════════════════════════════════

  static const _kOcrUsed = 'quota_ocr_used';
  static const _kOcrQuota = 'quota_ocr_quota';
  static const _kOcrUnlimited = 'quota_ocr_unlimited';
  static const _kRealUsed = 'quota_real_used';
  static const _kRealQuota = 'quota_real_quota';
  static const _kRealUnlimited = 'quota_real_unlimited';
  static const _kResetDate = 'quota_reset_date';
  static const _kCacheOwner = 'quota_cache_owner';

  Future<QuotaUsage?> _loadCachedUsage(QuotaType type) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_cacheBelongsToCurrentOwner(prefs)) return null;
    final today = _todayStr();
    final resetDate = prefs.getString(_kResetDate) ?? today;
    if (resetDate != today) return null; // 跨天，缓存失效

    if (type == QuotaType.ocr) {
      if (!prefs.containsKey(_kOcrQuota)) return null;
      final used = prefs.getInt(_kOcrUsed) ?? 0;
      final quota = prefs.getInt(_kOcrQuota) ?? 0;
      final unlimited = prefs.getBool(_kOcrUnlimited) ?? false;
      return QuotaUsage(
        used: used,
        quota: quota,
        remaining: unlimited ? -1 : (quota - used),
        unlimited: unlimited,
      );
    } else {
      if (!prefs.containsKey(_kRealQuota)) return null;
      final used = prefs.getInt(_kRealUsed) ?? 0;
      final quota = prefs.getInt(_kRealQuota) ?? 0;
      final unlimited = prefs.getBool(_kRealUnlimited) ?? false;
      return QuotaUsage(
        used: used,
        quota: quota,
        remaining: unlimited ? -1 : (quota - used),
        unlimited: unlimited,
      );
    }
  }

  Future<void> _cacheUsage(QuotaType type, QuotaUsage u) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveCacheOwner(prefs);
    await prefs.setString(_kResetDate, _todayStr());
    if (type == QuotaType.ocr) {
      await prefs.setInt(_kOcrUsed, u.used);
      await prefs.setInt(_kOcrQuota, u.quota);
      await prefs.setBool(_kOcrUnlimited, u.unlimited);
    } else {
      await prefs.setInt(_kRealUsed, u.used);
      await prefs.setInt(_kRealQuota, u.quota);
      await prefs.setBool(_kRealUnlimited, u.unlimited);
    }
  }

  Future<void> _cacheSnapshot(QuotaSnapshot s) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveCacheOwner(prefs);
    await prefs.setString(
      _kResetDate,
      s.resetDate.isEmpty ? _todayStr() : s.resetDate,
    );
    await prefs.setInt(_kOcrUsed, s.ocr.used);
    await prefs.setInt(_kOcrQuota, s.ocr.quota);
    await prefs.setBool(_kOcrUnlimited, s.ocr.unlimited);
    await prefs.setInt(_kRealUsed, s.realReply.used);
    await prefs.setInt(_kRealQuota, s.realReply.quota);
    await prefs.setBool(_kRealUnlimited, s.realReply.unlimited);
  }

  Future<void> _markExhausted(QuotaType type) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveCacheOwner(prefs);
    await prefs.setString(_kResetDate, _todayStr());
    if (type == QuotaType.ocr) {
      await prefs.setInt(_kOcrUsed, prefs.getInt(_kOcrQuota) ?? 0);
    } else {
      await prefs.setInt(_kRealUsed, prefs.getInt(_kRealQuota) ?? 0);
    }
  }

  String? get _currentCacheOwner {
    final owner = cacheOwnerProvider?.call()?.trim();
    return owner == null || owner.isEmpty ? null : owner;
  }

  bool _cacheBelongsToCurrentOwner(SharedPreferences prefs) {
    return prefs.getString(_kCacheOwner) == _currentCacheOwner;
  }

  Future<void> _saveCacheOwner(SharedPreferences prefs) async {
    final owner = _currentCacheOwner;
    if (owner == null) {
      await prefs.remove(_kCacheOwner);
    } else {
      await prefs.setString(_kCacheOwner, owner);
    }
  }

  void _invalidateSnapshot() {
    _lastSnapshot = null;
    _lastSnapshotAt = null;
    _lastSnapshotOwner = null;
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '-${n.month.toString().padLeft(2, '0')}'
        '-${n.day.toString().padLeft(2, '0')}';
  }
}
