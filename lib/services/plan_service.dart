import 'dart:async';
import 'package:timezone/data/latest.dart' as tz;
import '../models/planned_message.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// 计划消息服务：解析时间、存储计划、定时触发
class PlanService {
  final NotificationService _notificationService;
  final Map<int, Timer> _timers = {};
  // 投递防重入：Timer 触发与 30s 轮询补投可能并发命中同一条计划
  final Set<int> _inflightDeliveries = {};
  String? _agentId;

  // agentId 随行：计划属于发起时的智能体，投递时按它落库而非"当前智能体"
  void Function(String message, String? agentId)? onPlanTriggered;

  PlanService({required NotificationService notificationService})
    : _notificationService = notificationService {
    tz.initializeTimeZones();
  }

  void setAgentId(String? id) => _agentId = id;

  /// 解析 send_time 字符串为 DateTime
  static DateTime parseSendTime(String sendTime) {
    // 相对时间: "30m" = 30分钟后, "2h" = 2小时后
    if (sendTime.endsWith('m')) {
      final minutes = int.tryParse(sendTime.substring(0, sendTime.length - 1));
      if (minutes != null) {
        return DateTime.now().add(Duration(minutes: minutes));
      }
    }
    if (sendTime.endsWith('h')) {
      final hours = int.tryParse(sendTime.substring(0, sendTime.length - 1));
      if (hours != null) {
        return DateTime.now().add(Duration(hours: hours));
      }
    }
    // ISO 8601 格式
    return DateTime.parse(sendTime);
  }

  /// 调度一条计划消息
  Future<int> scheduleMessage({
    required DateTime scheduledTime,
    required String message,
    String? agentId,
  }) async {
    // 归属在调度时刻固定：之后切换智能体不改变这条计划的归属
    final scheduledAgentId = agentId ?? _agentId;
    final planned = PlannedMessage(
      scheduledTime: scheduledTime,
      message: message,
      agentId: scheduledAgentId,
    );
    final id = await DatabaseService.insertPlannedMessage(planned);

    // 使用通知调度（后台/前台均可）
    await _notificationService.scheduleNotification(
      id: id,
      title: 'AI 助手',
      body: message,
      scheduledDate: scheduledTime,
    );

    // 如果延迟小于 15 分钟，同时使用 Timer 实现更精确的前台触发
    final delay = scheduledTime.difference(DateTime.now());
    if (delay.inMinutes < 15 && delay.inSeconds > 0) {
      _timers[id] = Timer(delay, () {
        _deliverMessage(id, message, scheduledAgentId);
      });
    }

    return id;
  }

  /// 触发计划消息传递
  Future<void> _deliverMessage(int id, String message, String? agentId) async {
    // 防重入：Timer 与轮询/通知点击并发命中同一条计划时只投递一次
    if (!_inflightDeliveries.add(id)) return;
    try {
      // 先落 delivered 标记再回调，避免回调期间被轮询再次拾取
      await DatabaseService.markDelivered(id);
      _timers.remove(id)?.cancel();
      onPlanTriggered?.call(message, agentId);
    } finally {
      _inflightDeliveries.remove(id);
    }
  }

  /// 从通知点击恢复时调用
  Future<void> deliverFromNotification(int id) async {
    final messages = await DatabaseService.getPlannedMessages();
    final target = messages.cast<PlannedMessage?>().firstWhere(
      (m) => m?.id == id,
      orElse: () => null,
    );
    if (target != null && !target.delivered) {
      await _deliverMessage(id, target.message, target.agentId);
    }
  }

  /// 获取所有计划消息
  Future<List<PlannedMessage>> getPlannedMessages() async {
    return await DatabaseService.getPlannedMessages(agentId: _agentId);
  }

  /// 立即触发一条计划消息
  Future<void> triggerNow(int id) async {
    final messages = await DatabaseService.getPlannedMessages();
    final target = messages.cast<PlannedMessage?>().firstWhere(
      (m) => m?.id == id,
      orElse: () => null,
    );
    // 已投递的不再重复投递
    if (target != null && !target.delivered) {
      await _deliverMessage(id, target.message, target.agentId);
    }
  }

  /// 取消一条计划
  Future<void> cancelPlan(int id) async {
    _timers.remove(id)?.cancel();
    await _notificationService.cancelNotification(id);
    await DatabaseService.deletePlannedMessage(id);
  }

  /// 释放所有定时器
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
