import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

/// 顶层函数：后台通知回调（必须为 static 或 top-level）
@pragma('vm:entry-point')
void _backgroundNotificationHandler(NotificationResponse response) {
  // 后台通知点击时，系统会启动应用，回调由前台 initialize 的 onDidReceiveNotificationResponse 处理
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String planChannelId = 'plan_channel';
  static const String aiMessageChannelId = 'ai_chat_message';
  static const String proactiveCareChannelId = 'proactive_care';

  void Function(int id)? onNotificationTapped;
  void Function(String? payload)? onAiMessageTapped;

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundNotificationHandler,
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final id = response.id;
    final payload = response.payload;
    if (id != null) {
      onNotificationTapped?.call(id);
    }
    if (onAiMessageTapped != null && payload != null) {
      onAiMessageTapped!(payload);
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);
    if (tzDate.isBefore(DateTime.now())) return;

    const androidDetails = AndroidNotificationDetails(
      planChannelId,
      '计划消息',
      channelDescription: 'AI 计划消息提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDate,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      aiMessageChannelId,
      'AI 消息',
      channelDescription: 'AI 主动消息通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// 主动关心通知（仿微信）：标题=智能体名，正文=消息全文，
  /// 大图标=智能体头像文件（不存在则用默认应用图标），payload 为 proactive:agentId
  Future<void> showProactiveCareNotification({
    required int id,
    required String agentName,
    required String message,
    String? avatarPath,
    String? payload,
  }) async {
    final now = DateTime.now();
    final me = Person(name: agentName);
    final style = MessagingStyleInformation(
      me,
      messages: [Message(message, now, me)],
    );
    final androidDetails = AndroidNotificationDetails(
      proactiveCareChannelId,
      '主动关心',
      channelDescription: '智能体主动发来的关心消息',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: style,
      largeIcon:
          avatarPath != null ? FilePathAndroidBitmap(avatarPath) : null,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    try {
      await _plugin.show(id, agentName, message, details, payload: payload);
    } catch (_) {
      // MessagingStyle / 头像文件在某些机型上可能失败，退化为纯文本通知
      const fallbackDetails = AndroidNotificationDetails(
        proactiveCareChannelId,
        '主动关心',
        channelDescription: '智能体主动发来的关心消息',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        id,
        agentName,
        message,
        const NotificationDetails(
          android: fallbackDetails,
          iOS: iosDetails,
        ),
        payload: payload,
      );
    }
  }

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
