import 'package:aichat/services/adaptive_sync_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync failures back off and fast success recovers gradually', () {
    final scheduler = AdaptiveSyncScheduler(jitter: Duration.zero);
    final initial = scheduler.nextDelay(foregroundBusy: false);

    scheduler.recordFailure();
    final backedOff = scheduler.nextDelay(foregroundBusy: false);
    expect(backedOff, greaterThan(initial));

    scheduler.recordSuccess(const Duration(milliseconds: 200));
    expect(scheduler.nextDelay(foregroundBusy: false), lessThan(backedOff));
  });

  test('foreground chat always receives a quiet sync window', () {
    final scheduler = AdaptiveSyncScheduler(jitter: Duration.zero);

    expect(
      scheduler.nextDelay(foregroundBusy: true),
      greaterThanOrEqualTo(const Duration(seconds: 2)),
    );
  });

  test('sync delay remains inside safe bounds', () {
    final scheduler = AdaptiveSyncScheduler(jitter: Duration.zero);

    for (var index = 0; index < 20; index++) {
      scheduler.recordFailure();
    }
    expect(
      scheduler.nextDelay(foregroundBusy: false),
      lessThanOrEqualTo(const Duration(seconds: 8)),
    );

    for (var index = 0; index < 100; index++) {
      scheduler.recordSuccess(const Duration(milliseconds: 100));
    }
    expect(
      scheduler.nextDelay(foregroundBusy: false),
      greaterThanOrEqualTo(const Duration(milliseconds: 300)),
    );
  });

  test('jitter never pushes delay beyond the safe maximum', () {
    final scheduler = AdaptiveSyncScheduler(
      jitter: const Duration(milliseconds: 500),
    );
    for (var index = 0; index < 20; index++) {
      scheduler.recordFailure();
    }

    expect(
      scheduler.nextDelay(foregroundBusy: false),
      lessThanOrEqualTo(AdaptiveSyncScheduler.maxDelay),
    );
  });
}
