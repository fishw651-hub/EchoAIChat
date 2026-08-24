import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planned_message.dart';
import '../services/plan_service.dart';
import 'chat_provider.dart' show planServiceProvider;

class PlanState {
  final List<PlannedMessage> plannedMessages;
  final bool isLoading;

  const PlanState({this.plannedMessages = const [], this.isLoading = false});

  PlanState copyWith({List<PlannedMessage>? plannedMessages, bool? isLoading}) {
    return PlanState(
      plannedMessages: plannedMessages ?? this.plannedMessages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PlanNotifier extends StateNotifier<PlanState> {
  final PlanService _planService;
  Timer? _pollTimer;
  Timer? _rescheduleTimer;

  PlanNotifier(this._planService) : super(const PlanState()) {
    loadPlans();
    // 每 30 秒轮询一次数据库，检测是否有到时间但未投递的计划消息
    // 这样即使通知被系统延迟或错过，前台时仍能补投
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollAndDeliver());
    // 每 5 分钟重新加载列表（同步状态）
    _rescheduleTimer = Timer.periodic(const Duration(minutes: 5), (_) => loadPlans());
  }

  Future<void> loadPlans() async {
    state = state.copyWith(isLoading: true);
    final plans = await _planService.getPlannedMessages();
    state = state.copyWith(plannedMessages: plans, isLoading: false);
  }

  Future<void> cancelPlan(int id) async {
    await _planService.cancelPlan(id);
    await loadPlans();
  }

  Future<void> triggerNow(int id) async {
    await _planService.triggerNow(id);
    await loadPlans();
  }

  /// 轮询：检查是否有到时间但未投递的消息，触发投递
  Future<void> _pollAndDeliver() async {
    final plans = state.plannedMessages;
    final now = DateTime.now();
    bool changed = false;
    for (final p in plans) {
      if (!p.delivered && p.scheduledTime.isBefore(now)) {
        // 时间已到但未投递 → 立即投递
        await _planService.triggerNow(p.id!);
        changed = true;
      }
    }
    if (changed) await loadPlans();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _rescheduleTimer?.cancel();
    super.dispose();
  }
}

final planProvider =
    StateNotifierProvider<PlanNotifier, PlanState>((ref) {
  return PlanNotifier(ref.read(planServiceProvider));
});
