typedef SubscriptionPlanLoader = Future<List<dynamic>> Function();

class SubscriptionPlanCache {
  SubscriptionPlanCache({this.maxAge = const Duration(minutes: 5)});

  static final SubscriptionPlanCache instance = SubscriptionPlanCache();

  final Duration maxAge;
  List<dynamic>? _plans;
  DateTime? _cachedAt;
  Future<List<dynamic>>? _inflight;

  Future<List<dynamic>> get(
    SubscriptionPlanLoader loader, {
    bool force = false,
  }) {
    final plans = _plans;
    final cachedAt = _cachedAt;
    if (!force &&
        plans != null &&
        cachedAt != null &&
        !DateTime.now().isAfter(cachedAt.add(maxAge))) {
      return Future.value(plans);
    }

    final inflight = _inflight;
    if (inflight != null) return inflight;

    final request = loader().then((loaded) {
      final snapshot = List<dynamic>.unmodifiable(loaded);
      _plans = snapshot;
      _cachedAt = DateTime.now();
      return snapshot;
    });
    _inflight = request;
    return request.whenComplete(() => _inflight = null);
  }
}
