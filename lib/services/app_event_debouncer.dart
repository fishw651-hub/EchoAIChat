import 'dart:async';

typedef AppEventFlushCallback = void Function(Set<String> scopes);

class AppEventDebouncer {
  AppEventDebouncer({required this.delay, required this.onFlush});

  final Duration delay;
  final AppEventFlushCallback onFlush;
  final Set<String> _pendingScopes = {};
  Timer? _timer;

  void add(String scope) {
    if (scope.isEmpty) return;
    _pendingScopes.add(scope);
    _timer?.cancel();
    _timer = Timer(delay, _flush);
  }

  void _flush() {
    if (_pendingScopes.isEmpty) return;
    final scopes = Set<String>.unmodifiable(_pendingScopes);
    _pendingScopes.clear();
    onFlush(scopes);
  }

  void dispose() {
    _timer?.cancel();
    _pendingScopes.clear();
  }
}
