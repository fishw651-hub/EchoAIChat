import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_entry.dart';
import '../services/user_profile_service.dart';

final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileService();
});

class UserProfileState {
  final Map<String, List<ProfileEntry>> grouped;
  final bool isLoading;
  final int totalCount;

  const UserProfileState({
    this.grouped = const {},
    this.isLoading = false,
    this.totalCount = 0,
  });

  UserProfileState copyWith({
    Map<String, List<ProfileEntry>>? grouped,
    bool? isLoading,
    int? totalCount,
  }) {
    return UserProfileState(
      grouped: grouped ?? this.grouped,
      isLoading: isLoading ?? this.isLoading,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

class ProfileEntryDraft {
  final String category;
  final String key;
  final String value;
  final int confidence;
  final String source;

  const ProfileEntryDraft({
    required this.category,
    required this.key,
    required this.value,
    this.confidence = 50,
    this.source = 'manual',
  });
}

class UserProfileNotifier extends StateNotifier<UserProfileState> {
  final UserProfileService _service;

  UserProfileNotifier(this._service) : super(const UserProfileState()) {
    loadProfiles();
  }

  Future<void> loadProfiles() async {
    state = state.copyWith(isLoading: true);
    final grouped = await _service.getGroupedEntries();
    final total = grouped.values.fold<int>(0, (sum, list) => sum + list.length);
    state = state.copyWith(grouped: grouped, totalCount: total, isLoading: false);
  }

  Future<void> createProfile({
    required String category,
    required String key,
    required String value,
    int confidence = 50,
    String source = 'manual',
  }) async {
    await _service.createEntry(
      category: category,
      key: key,
      value: value,
      confidence: confidence,
      source: source,
    );
    await loadProfiles();
  }

  Future<void> createProfiles(List<ProfileEntryDraft> entries) async {
    for (final entry in entries) {
      await _service.createEntry(
        category: entry.category,
        key: entry.key,
        value: entry.value,
        confidence: entry.confidence,
        source: entry.source,
      );
    }
    await loadProfiles();
  }

  Future<void> updateProfile(ProfileEntry entry) async {
    await _service.updateEntry(entry);
    await loadProfiles();
  }

  Future<void> deleteProfile(String id) async {
    await _service.deleteEntry(id);
    await loadProfiles();
  }

  Future<void> clearAll() async {
    await _service.clearAll();
    await loadProfiles();
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfileState>((ref) {
  return UserProfileNotifier(ref.read(userProfileServiceProvider));
});
