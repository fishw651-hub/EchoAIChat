import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_usage_service.dart';

class RealInfoService {
  // 地点/天气缓存：网络失败时用最近一次成功结果兜底，
  // 确保每次 AI 调用都能拿到地点和天气
  static const _keyLocationCache = 'realinfo_location_cache';
  static const _keyWeatherCache = 'realinfo_weather_cache';
  static const _locationTtl = Duration(hours: 24);
  static const _weatherTtl = Duration(minutes: 30);

  static Future<Map<String, String>> collectAll() async {
    final results = await Future.wait([
      _getTimeInfo(),
      _getLocation(),
      _getAppUsage(),
    ]);

    final info = <String, String>{};
    for (final r in results) {
      info.addAll(r);
    }

    final city = info['city'] ?? '';
    if (city.isNotEmpty) {
      final weatherInfo = await _getWeather(city);
      info.addAll(weatherInfo);
    } else {
      // 无城市时仍尝试用缓存天气（缓存里有城市名）
      final cached = await readCache(_keyWeatherCache, _weatherTtl);
      if (cached != null && (cached['weather'] ?? '').isNotEmpty) {
        info['weather'] = cached['weather']!;
      }
    }

    info.addAll(_getDeviceInfo());
    return info;
  }

  /// 读缓存（JSON: {..., 'ts': millisecondsSinceEpoch}），过期返回 null
  @visibleForTesting
  static Future<Map<String, String>?> readCache(String key, Duration ttl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final ts = (data['ts'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (ts <= 0 || age > ttl.inMilliseconds) return null;
      return data.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return null;
    }
  }

  /// 写缓存（附带时间戳）
  @visibleForTesting
  static Future<void> writeCache(
    String key,
    Map<String, String> values,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode({
        ...values,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  static Future<Map<String, String>> _getTimeInfo() async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final weekStr = weekdays[now.weekday - 1];

    final tzOffset = now.timeZoneOffset;
    final tzHours = tzOffset.inHours;
    final tzSign = tzHours >= 0 ? '+' : '';
    final tzName = now.timeZoneName;

    final month = now.month;
    String season;
    if (month >= 3 && month <= 5) {
      season = '春季';
    } else if (month >= 6 && month <= 8) {
      season = '夏季';
    } else if (month >= 9 && month <= 11) {
      season = '秋季';
    } else {
      season = '冬季';
    }

    final holiday = _getHoliday(now);

    return {
      'time': '$timeStr（星期$weekStr）',
      'timezone': 'UTC$tzSign$tzHours $tzName',
      'season': season,
      'holiday': holiday,
    };
  }

  static String _getHoliday(DateTime now) {
    final lunarHolidays = {
      '0101': '春节',
      '0115': '元宵节',
      '0505': '端午节',
      '0707': '七夕节',
      '0715': '中元节',
      '0815': '中秋节',
      '0909': '重阳节',
      '1208': '腊八节',
      '1230': '除夕',
    };

    final solarHolidays = {
      '0101': '元旦',
      '0214': '情人节',
      '0308': '妇女节',
      '0312': '植树节',
      '0401': '愚人节',
      '0501': '劳动节',
      '0601': '儿童节',
      '0701': '建党节',
      '0801': '建军节',
      '0910': '教师节',
      '1001': '国庆节',
      '1225': '圣诞节',
    };

    final mmdd = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    if (solarHolidays.containsKey(mmdd)) {
      return '今天是${solarHolidays[mmdd]}';
    }
    if (lunarHolidays.containsKey(mmdd)) {
      return '今天是${lunarHolidays[mmdd]}（农历）';
    }
    return '';
  }

  static Future<Map<String, String>> _getLocation() async {
    try {
      // 注意：ip-api.com 免费版不支持 HTTPS（仅 HTTP），HTTPS 会返回 403。
      // 此处保留明文 HTTP 以维持定位功能；失败时优雅降级为空地点，不阻塞主流程。
      // TODO：后续可替换为支持 HTTPS 的免费定位服务（如 ipapi.co）。
      final response = await http.get(
        Uri.parse('http://ip-api.com/json'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final city = (data['city'] as String? ?? '').trim();
        final region = (data['regionName'] as String? ?? '').trim();
        final country = (data['country'] as String? ?? '');

        final locationParts = <String>[country];
        if (region.isNotEmpty && region != country) locationParts.add(region);
        if (city.isNotEmpty && city != region) locationParts.add(city);

        final result = {
          'city': city,
          'location': locationParts.join(' · '),
        };
        if (city.isNotEmpty) {
          await writeCache(_keyLocationCache, result);
        }
        return result;
      }
    } catch (e) {
      debugPrint('[RealInfo] Location fetch failed: $e');
    }
    // 网络失败：用最近一次成功的定位缓存兜底
    final cached = await readCache(_keyLocationCache, _locationTtl);
    if (cached != null) {
      return {
        'city': cached['city'] ?? '',
        'location': cached['location'] ?? '',
      };
    }
    return {'city': '', 'location': ''};
  }

  static Future<Map<String, String>> _getWeather(String city) async {
    if (city.isEmpty) return {};
    try {
      final encoded = Uri.encodeComponent(city);
      final response = await http.get(
        Uri.parse('https://wttr.in/$encoded?format=j1'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final current = data['current_condition'] as List?;
        if (current != null && current.isNotEmpty) {
          final c = current[0] as Map<String, dynamic>;
          final temp = c['temp_C'] as String? ?? '';
          final desc = c['weatherDesc'] as List?;
          final weatherText = desc != null && desc.isNotEmpty
              ? (desc[0] as Map<String, dynamic>)['value'] as String?
              : '';
          final result = {
            'city': city,
            'weather': '$weatherText $temp°C',
          };
          await writeCache(_keyWeatherCache, result);
          return {'weather': result['weather']!};
        }
      }
    } catch (e) {
      debugPrint('[RealInfo] Weather fetch failed for "$city": $e');
    }
    // 网络失败：同城缓存天气兜底
    final cached = await readCache(_keyWeatherCache, _weatherTtl);
    if (cached != null && cached['city'] == city) {
      return {'weather': cached['weather'] ?? ''};
    }
    return {'weather': ''};
  }

  static Future<Map<String, String>> _getAppUsage() async {
    try {
      final summary = await AppUsageService.getTodaySummary();
      if (summary.isEmpty) return {};
      return {'app_usage': summary};
    } catch (e) {
      debugPrint('[RealInfo] App usage fetch failed: $e');
      return {};
    }
  }

  static Map<String, String> _getDeviceInfo() {
    String deviceType;
    try {
      final os = Platform.operatingSystem;
      final version = Platform.operatingSystemVersion;
      if (os == 'android') {
        deviceType = 'Android 手机';
      } else if (os == 'ios') {
        deviceType = 'iPhone';
      } else if (os == 'macos') {
        deviceType = 'macOS 桌面端';
      } else if (os == 'windows') {
        deviceType = 'Windows 桌面端';
      } else if (os == 'linux') {
        deviceType = 'Linux 桌面端';
      } else {
        deviceType = os;
      }
      return {
        'device': deviceType,
        'os_version': version,
      };
    } catch (e) {
      return {'device': '', 'os_version': ''};
    }
  }

  static String formatPrompt(Map<String, String> info) {
    final buf = StringBuffer('\n## 环境信息\n');

    // 时间已在 system prompt 开头注入，此处跳过避免重复
    if (info.containsKey('timezone') && info['timezone']!.isNotEmpty) {
      buf.writeln('【时区】${info['timezone']}');
    }
    if (info.containsKey('location') && info['location']!.isNotEmpty) {
      buf.writeln('【地点】${info['location']}');
    }
    if (info.containsKey('weather') && info['weather']!.isNotEmpty) {
      buf.writeln('【天气】${info['weather']}');
    }
    if (info.containsKey('device') && info['device']!.isNotEmpty) {
      buf.writeln('【设备】${info['device']}');
    }
    if (info.containsKey('season') && info['season']!.isNotEmpty) {
      buf.writeln('【季节】${info['season']}');
    }
    if (info.containsKey('holiday') && info['holiday']!.isNotEmpty) {
      buf.writeln('【${info['holiday']}】');
    }
    if (info.containsKey('app_usage') && info['app_usage']!.isNotEmpty) {
      buf.writeln('【应用使用】${info['app_usage']}');
    }

    return buf.toString();
  }
}
