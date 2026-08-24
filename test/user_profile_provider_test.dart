import 'package:aichat/models/profile_entry.dart';
import 'package:aichat/providers/user_profile_provider.dart';
import 'package:aichat/services/user_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('批量创建画像后立即刷新可展示的 Provider 状态', () async {
    final service = _InMemoryUserProfileService();
    final notifier = UserProfileNotifier(service);
    await notifier.loadProfiles();

    await notifier.createProfiles([
      const ProfileEntryDraft(
        category: 'personality',
        key: '性格',
        value: '理性且有边界感',
        confidence: 95,
        source: 'init_wizard',
      ),
    ]);

    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.totalCount, 1);
    expect(notifier.state.grouped['personality']!.single.value, '理性且有边界感');
  });
}

class _InMemoryUserProfileService extends UserProfileService {
  final List<ProfileEntry> _entries = [];

  @override
  Future<List<ProfileEntry>> getAllEntries() async => List.of(_entries);

  @override
  Future<void> createEntry({
    required String category,
    required String key,
    required String value,
    int confidence = 50,
    String source = 'ai_extracted',
  }) async {
    _entries.add(ProfileEntry(
      id: '${category}_$key',
      category: category,
      key: key,
      value: value,
      confidence: confidence,
      source: source,
    ));
  }
}
