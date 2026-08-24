import 'package:uuid/uuid.dart';
import '../models/profile_entry.dart';
import 'database_service.dart';

class UserProfileService {
  final _uuid = const Uuid();

  Future<List<ProfileEntry>> getAllEntries() async {
    return await DatabaseService.getProfileEntries();
  }

  Future<List<ProfileEntry>> getEntriesByCategory(String category) async {
    return await DatabaseService.getProfileEntriesByCategory(category);
  }

  Future<ProfileEntry?> getEntry(String key, String category) async {
    return await DatabaseService.getProfileEntry(key, category);
  }

  Future<void> createEntry({
    required String category,
    required String key,
    required String value,
    int confidence = 50,
    String source = 'ai_extracted',
  }) async {
    final existing = await DatabaseService.getProfileEntry(key, category);
    if (existing != null) {
      await DatabaseService.updateProfileEntry(existing.copyWith(
        value: value,
        confidence: confidence,
        source: source,
        updatedAt: DateTime.now(),
      ));
      return;
    }
    final entry = ProfileEntry(
      id: _uuid.v4(),
      category: category,
      key: key,
      value: value,
      confidence: confidence,
      source: source,
    );
    await DatabaseService.insertProfileEntry(entry);
  }

  Future<void> updateEntry(ProfileEntry entry) async {
    await DatabaseService.updateProfileEntry(entry.copyWith(
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> deleteEntry(String id) async {
    await DatabaseService.deleteProfileEntry(id);
  }

  Future<void> deleteEntryByKey(String key, String category) async {
    final existing = await DatabaseService.getProfileEntry(key, category);
    if (existing != null) {
      await DatabaseService.deleteProfileEntry(existing.id);
    }
  }

  Future<int> getEntryCount() async {
    return await DatabaseService.getProfileEntryCount();
  }

  Future<void> clearAll() async {
    await DatabaseService.clearProfileEntries();
  }

  Map<String, List<ProfileEntry>> groupByCategory(List<ProfileEntry> entries) {
    final map = <String, List<ProfileEntry>>{};
    for (final e in entries) {
      map.putIfAbsent(e.category, () => []).add(e);
    }
    return map;
  }

  Future<Map<String, List<ProfileEntry>>> getGroupedEntries() async {
    final all = await getAllEntries();
    return groupByCategory(all);
  }
}
