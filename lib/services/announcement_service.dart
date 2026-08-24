import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_config.dart';

/// 公告弹出频率
///
/// - [once]：只弹一次（内容更新后重新弹）
/// - [daily]：每天最多弹一次
/// - [always]：每次进入首页都弹
enum AnnouncementFrequency { once, daily, always }

/// 公告目标人群
enum AnnouncementAudience { all, subscriber, free }

/// 服务端公告（`GET /api/v1/announcements/active`，content 为 Markdown）
class Announcement {
  final String id;
  final String title;
  final String content;
  final AnnouncementFrequency frequency;
  final AnnouncementAudience audience;
  final String startAt;
  final String endAt;

  /// 内容最后更新时间；once 公告据此判断"内容更新过 → 重新弹"
  final String updatedAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.frequency = AnnouncementFrequency.always,
    this.audience = AnnouncementAudience.all,
    this.startAt = '',
    this.endAt = '',
    this.updatedAt = '',
  });

  /// 容错解析：字段缺失/类型不符给默认值，不抛异常
  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        frequency: _parseFrequency(j['frequency']),
        audience: _parseAudience(j['audience']),
        startAt: j['start_at'] as String? ?? '',
        endAt: j['end_at'] as String? ?? '',
        updatedAt: j['updated_at'] as String? ?? '',
      );

  static AnnouncementFrequency _parseFrequency(dynamic v) {
    switch (v) {
      case 'once':
        return AnnouncementFrequency.once;
      case 'daily':
        return AnnouncementFrequency.daily;
      case 'always':
        return AnnouncementFrequency.always;
      default:
        // 未知频率按 always 处理：宁可多弹，不漏弹
        return AnnouncementFrequency.always;
    }
  }

  static AnnouncementAudience _parseAudience(dynamic v) {
    switch (v) {
      case 'subscriber':
        return AnnouncementAudience.subscriber;
      case 'free':
        return AnnouncementAudience.free;
      default:
        return AnnouncementAudience.all;
    }
  }
}

/// 公告服务：拉取 + 频率控制 + 目标过滤（纯静态方法，便于单测）
class AnnouncementService {
  AnnouncementService._();

  // SharedPreferences key（与已批准设计一致，前缀保留 "annonce" 拼写）
  static String _onceKey(String id) => 'annonce_once_$id';
  static String _dailyKey(String id) => 'annonce_daily_$id';

  /// 拉取当前生效公告；任何失败（网络/非 200/信封异常/解析失败）返回空列表
  /// —— 公告不阻塞正常使用
  static Future<List<Announcement>> fetchActive(String jwt) async {
    try {
      final resp = await http
          .get(
            Uri.parse('${ServerConfig.baseUrl}/api/v1/announcements/active'),
            headers: {'Authorization': 'Bearer $jwt'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return const [];
      if (json['code'] != 0) return const [];
      final data = json['data'];
      if (data is! List) return const [];
      final result = <Announcement>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final a = Announcement.fromJson(item);
        if (a.id.isEmpty) continue; // 无 id 无法做频率记录，跳过
        result.add(a);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// 目标过滤：subscriber 仅订阅用户，free 仅非订阅用户，all 全部可见
  static bool matchesAudience(
    Announcement a, {
    required bool hasActiveSubscription,
  }) {
    switch (a.audience) {
      case AnnouncementAudience.all:
        return true;
      case AnnouncementAudience.subscriber:
        return hasActiveSubscription;
      case AnnouncementAudience.free:
        return !hasActiveSubscription;
    }
  }

  /// 频率判断：本条公告现在是否应该弹出
  static bool shouldShow(
    Announcement a,
    SharedPreferences prefs, {
    DateTime? now,
  }) {
    switch (a.frequency) {
      case AnnouncementFrequency.always:
        return true;
      case AnnouncementFrequency.once:
        final seen = prefs.getString(_onceKey(a.id));
        // 记录值与当前 updated_at 一致 → 已读过这版内容，不弹；
        // updated_at 变化（内容更新）→ 视为新公告重新弹
        return seen == null || seen != a.updatedAt;
      case AnnouncementFrequency.daily:
        final day = prefs.getString(_dailyKey(a.id));
        return day != _dayStr(now ?? DateTime.now());
    }
  }

  /// 记录"已展示"：once 写 updated_at，daily 写今天日期，always 不写
  static Future<void> markShown(
    Announcement a,
    SharedPreferences prefs, {
    DateTime? now,
  }) async {
    switch (a.frequency) {
      case AnnouncementFrequency.once:
        await prefs.setString(_onceKey(a.id), a.updatedAt);
      case AnnouncementFrequency.daily:
        await prefs.setString(_dailyKey(a.id), _dayStr(now ?? DateTime.now()));
      case AnnouncementFrequency.always:
        break; // always 不落任何记录
    }
  }

  /// 弹窗关闭后的统一记录逻辑：
  /// - once：任一按钮（含「关闭」「今天不再提示」）都写 once 记录
  /// - daily：仅「今天不再提示」写 daily 记录；「关闭」不写，下次启动还弹
  /// - always：不写任何记录（下次进入首页仍弹）
  static Future<void> recordDismiss(
    Announcement a, {
    required bool dontShowToday,
    required SharedPreferences prefs,
    DateTime? now,
  }) async {
    switch (a.frequency) {
      case AnnouncementFrequency.once:
        await markShown(a, prefs, now: now);
      case AnnouncementFrequency.daily:
        if (dontShowToday) await markShown(a, prefs, now: now);
      case AnnouncementFrequency.always:
        break;
    }
  }

  /// yyyy-MM-dd（本地时区，与 QuotaService 的当日口径一致）
  static String _dayStr(DateTime n) =>
      '${n.year.toString().padLeft(4, '0')}'
      '-${n.month.toString().padLeft(2, '0')}'
      '-${n.day.toString().padLeft(2, '0')}';
}
