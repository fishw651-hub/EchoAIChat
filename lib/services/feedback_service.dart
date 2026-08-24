import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';
import '../providers/auth_provider.dart';

/// 反馈分类
enum FeedbackCategory {
  feature('feature', 'Feature idea'),
  featureTweak('feature_tweak', 'Feature improvement'),
  bug('bug', 'Bug / vulnerability'),
  ui('ui', 'UI polish'),
  pricing('pricing', 'Subscription or pricing'),
  other('other', 'Other');

  final String code;
  final String label;
  const FeedbackCategory(this.code, this.label);
}

class FeedbackException implements Exception {
  final String message;
  const FeedbackException(this.message);

  @override
  String toString() => message;
}

/// 一条用户反馈（对应服务端 models.Feedback）
class FeedbackItem {
  final int id;
  final String category;
  final String content;

  /// 0=待处理 1=处理中 2=已回复 3=已关闭
  final int status;
  final String reply;
  final DateTime? createdAt;

  const FeedbackItem({
    required this.id,
    required this.category,
    required this.content,
    required this.status,
    required this.reply,
    this.createdAt,
  });

  bool get hasReply => status == 2 && reply.trim().isNotEmpty;

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? 'other',
      content: json['content']?.toString() ?? '',
      status: (json['status'] as num?)?.toInt() ?? 0,
      reply: json['reply']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class FeedbackService {
  /// 拉取本人反馈列表（含状态与开发者回复）
  ///
  /// 成功返回列表（新的在前，服务端按 ID 倒序），失败抛 [FeedbackException]
  static Future<List<FeedbackItem>> listMine({
    required AuthState auth,
    String loginRequiredMessage = '请先登录',
  }) async {
    final jwt = auth.jwtToken;
    if (jwt == null || jwt.isEmpty) {
      throw FeedbackException(loginRequiredMessage);
    }
    try {
      final resp = await http
          .get(
            Uri.parse('${ServerConfig.baseUrl}/api/v1/feedback'),
            headers: {'Authorization': 'Bearer $jwt'},
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> body;
      try {
        body = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        throw FeedbackException('服务器响应无效 (${resp.statusCode})');
      }
      if (resp.statusCode != 200 || body['code'] != 0) {
        throw FeedbackException(
          body['message']?.toString() ?? '加载失败 (${resp.statusCode})',
        );
      }
      return parseList(body['data']);
    } on FeedbackException {
      rethrow;
    } catch (e) {
      throw FeedbackException('网络错误：$e');
    }
  }

  /// 解析反馈列表（data 为 null 时视为空列表，服务端无记录时返回 null）
  static List<FeedbackItem> parseList(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => FeedbackItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// 提交反馈
  ///
  /// 返回 null 表示成功，否则返回错误信息
  static Future<String?> submit({
    required AuthState auth,
    required FeedbackCategory category,
    required String content,
    required String contact,
    String loginRequiredMessage = 'Please log in first',
    String submitFailedMessage = 'Submit failed',
    String Function(String error)? networkErrorMessage,
  }) async {
    final jwt = auth.jwtToken;
    if (jwt == null || jwt.isEmpty) return loginRequiredMessage;
    try {
      final resp = await http
          .post(
            Uri.parse('${ServerConfig.baseUrl}/api/v1/feedback'),
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'category': category.code,
              'content': content,
              'contact': contact,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['message']?.toString() ?? submitFailedMessage;
    } catch (e) {
      return networkErrorMessage?.call(e.toString()) ?? '网络错误：$e';
    }
  }
}
