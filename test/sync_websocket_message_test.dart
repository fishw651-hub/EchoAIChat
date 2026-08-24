import 'dart:async';

import 'package:aichat/services/sync_websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync notification keeps source device agent and policy version', () {
    final message = SyncWSMessage.fromJson({
      'type': 'sync_notify',
      'message': 'chat_messages',
      'device_id': 'source-device',
      'agent_id': 'agent-a',
      'policy_version': 7,
    });

    expect(message.deviceId, 'source-device');
    expect(message.agentId, 'agent-a');
    expect(message.policyVersion, 7);
  });

  test('app event keeps invalidation and private review fields', () {
    final message = SyncWSMessage.fromJson({
      'type': 'app_event',
      'scope': 'my_uploads',
      'resource_type': 'agent',
      'resource_id': 12,
      'status': 'rejected',
      'reason': '人设包含违规内容',
      'version': 3,
      'event_id': 'agent:12:3:rejected',
      'timestamp': 1786810000,
    });

    expect(message.scope, 'my_uploads');
    expect(message.resourceType, 'agent');
    expect(message.resourceId, 12);
    expect(message.status, 'rejected');
    expect(message.reason, '人设包含违规内容');
    expect(message.version, 3);
    expect(message.eventId, 'agent:12:3:rejected');
  });

  test('ready message exposes sync permission separately from connection', () {
    final message = SyncWSMessage.fromJson({
      'type': 'ready',
      'sync_enabled': false,
    });

    expect(message.type, 'ready');
    expect(message.syncEnabled, isFalse);
  });

  test(
    'disconnect invalidates delayed connects and older account generations',
    () {
      final epoch = RealtimeConnectionEpoch();
      final firstAccount = epoch.begin();

      epoch.invalidate();
      expect(epoch.accepts(firstAccount), isFalse);

      final secondAccount = epoch.begin();
      expect(epoch.accepts(firstAccount), isFalse);
      expect(epoch.accepts(secondAccount), isTrue);
    },
  );

  test('disconnect during device id lookup never creates a socket', () async {
    final loaderStarted = Completer<void>();
    final deviceId = Completer<String>();
    var socketAttempts = 0;
    final service = SyncWebSocketService.forTesting(
      deviceIdLoader: () {
        loaderStarted.complete();
        return deviceId.future;
      },
      channelFactory: (uri, {required useHeaderToken, required jwt}) {
        socketAttempts++;
        throw StateError('stale connection reached socket factory');
      },
    );

    final connecting = service.connect(jwt: 'old-jwt', deviceName: 'old');
    await loaderStarted.future;
    await service.disconnect();
    deviceId.complete('device-1');
    await connecting;

    expect(socketAttempts, 0);
    service.dispose();
  });

  test(
    'chat lock request waits for acknowledgement and rejects conflicts',
    () async {
      final tracker = ChatLockRequestTracker(
        timeout: const Duration(milliseconds: 30),
      );

      var completed = false;
      final acknowledged = tracker.begin('a:agent-a')
        ..then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      tracker.resolve('a:agent-a', true);
      expect(await acknowledged, isTrue);

      final conflicted = tracker.begin('a:agent-a');
      tracker.resolve('a:agent-a', false);
      expect(await conflicted, isFalse);

      expect(await tracker.begin('g:group-a'), isFalse, reason: '确认超时必须拒绝发送');
    },
  );

  test('disconnect cancels every pending chat lock request', () async {
    final tracker = ChatLockRequestTracker(timeout: const Duration(seconds: 1));
    final first = tracker.begin('a:agent-a');
    final second = tracker.begin('g:group-a');

    tracker.cancelAll();

    expect(await first, isFalse);
    expect(await second, isFalse);
  });
}
