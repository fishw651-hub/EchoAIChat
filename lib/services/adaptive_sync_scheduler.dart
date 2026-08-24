import 'dart:math' as math;

class AdaptiveSyncScheduler {
  AdaptiveSyncScheduler({
    this.jitter = const Duration(milliseconds: 80),
    math.Random? random,
  }) : _random = random ?? math.Random();

  static const minDelay = Duration(milliseconds: 300);
  static const maxDelay = Duration(seconds: 8);
  static const foregroundDelay = Duration(seconds: 2);

  final Duration jitter;
  final math.Random _random;
  var _delay = const Duration(milliseconds: 600);

  void recordSuccess(Duration elapsed) {
    if (elapsed <= const Duration(seconds: 2)) {
      _delay = _bounded(_delay - const Duration(milliseconds: 100));
    } else if (elapsed >= const Duration(seconds: 5)) {
      _delay = _bounded(_delay + const Duration(milliseconds: 250));
    }
  }

  void recordFailure() {
    _delay = _bounded(_delay * 2);
  }

  Duration nextDelay({required bool foregroundBusy}) {
    var delay = foregroundBusy && _delay < foregroundDelay
        ? foregroundDelay
        : _delay;
    if (jitter > Duration.zero) {
      delay += Duration(
        milliseconds: _random.nextInt(jitter.inMilliseconds + 1),
      );
    }
    return _bounded(delay);
  }

  Duration _bounded(Duration value) {
    if (value < minDelay) return minDelay;
    if (value > maxDelay) return maxDelay;
    return value;
  }
}
