import 'package:flutter_test/flutter_test.dart';

import 'package:aichat/services/subscription_plan_cache.dart';

void main() {
  test('有效期内复用订阅方案并允许强制刷新', () async {
    var calls = 0;
    final cache = SubscriptionPlanCache();

    Future<List<dynamic>> load() async {
      calls++;
      return <dynamic>[
        <String, dynamic>{'id': calls},
      ];
    }

    final first = await cache.get(load);
    final cached = await cache.get(load);
    final refreshed = await cache.get(load, force: true);

    expect(calls, 2);
    expect(first.single['id'], 1);
    expect(cached.single['id'], 1);
    expect(refreshed.single['id'], 2);
  });
}
