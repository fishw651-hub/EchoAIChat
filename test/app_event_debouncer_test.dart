import 'dart:async';

import 'package:aichat/services/app_event_debouncer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('短时间内同类应用事件合并为一次刷新', () async {
    final batches = <Set<String>>[];
    final completed = Completer<void>();
    final debouncer = AppEventDebouncer(
      delay: const Duration(milliseconds: 10),
      onFlush: (scopes) {
        batches.add(scopes);
        completed.complete();
      },
    );
    addTearDown(debouncer.dispose);

    debouncer.add('network_agents');
    debouncer.add('network_agents');
    debouncer.add('quota');
    await completed.future.timeout(const Duration(seconds: 1));

    expect(batches, hasLength(1));
    expect(batches.single, {'network_agents', 'quota'});
  });
}
