import 'dart:async';

import 'package:flutter/foundation.dart';

typedef MemoryAnalysisTask = Future<void> Function();

/// 将记忆分析与聊天回复生命周期解耦，并限制同一智能体的并发任务。
class MemoryAnalysisCoordinator {
  final Map<String, Future<void>> _running = {};

  bool schedule(String agentId, MemoryAnalysisTask task) {
    if (agentId.isEmpty || _running.containsKey(agentId)) return false;

    final future = Future<void>.sync(task).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('[MemoryAI] background task failed: $error');
    });
    _running[agentId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_running[agentId], future)) {
          _running.remove(agentId);
        }
      }),
    );
    return true;
  }

  bool isRunning(String agentId) => _running.containsKey(agentId);

  @visibleForTesting
  Future<void> waitForIdle(String agentId) async {
    await _running[agentId];
  }
}
