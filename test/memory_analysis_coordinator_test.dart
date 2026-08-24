import 'dart:async';

import 'package:aichat/services/memory_analysis_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后台记忆任务未完成时也不阻塞后续聊天任务', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final coordinator = MemoryAnalysisCoordinator();

    expect(
      coordinator.schedule('agent-a', () async {
        started.complete();
        await release.future;
      }),
      isTrue,
    );
    await started.future;

    // 同一智能体已有后台任务时跳过，不把等待传播给聊天调用方。
    expect(coordinator.schedule('agent-a', () async {}), isFalse);
    expect(coordinator.isRunning('agent-a'), isTrue);

    release.complete();
    await coordinator.waitForIdle('agent-a');
    expect(coordinator.isRunning('agent-a'), isFalse);
    expect(coordinator.schedule('agent-a', () async {}), isTrue);
    await coordinator.waitForIdle('agent-a');
  });

  test('后台记忆任务失败后释放占用并允许重试', () async {
    final coordinator = MemoryAnalysisCoordinator();
    expect(
      coordinator.schedule('agent-a', () async {
        throw StateError('memory api failed');
      }),
      isTrue,
    );
    await coordinator.waitForIdle('agent-a');
    expect(coordinator.isRunning('agent-a'), isFalse);
    expect(coordinator.schedule('agent-a', () async {}), isTrue);
    await coordinator.waitForIdle('agent-a');
  });
}
