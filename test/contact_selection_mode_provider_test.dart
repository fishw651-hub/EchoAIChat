import 'package:aichat/providers/home_tab_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contactSelectionModeProvider defaults to false and toggles', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(contactSelectionModeProvider), isFalse);

    // 进入多选
    container.read(contactSelectionModeProvider.notifier).state = true;
    expect(container.read(contactSelectionModeProvider), isTrue);

    // 退出多选
    container.read(contactSelectionModeProvider.notifier).state = false;
    expect(container.read(contactSelectionModeProvider), isFalse);
  });
}
