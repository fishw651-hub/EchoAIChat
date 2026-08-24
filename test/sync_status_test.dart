import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/utils/sync_status.dart';

void main() {
  group('resolveSyncStatus', () {
    test('订阅不可用优先级最高', () {
      expect(
        resolveSyncStatus(
          canUseSync: false,
          isBusy: true,
          hasCloudUpdate: true,
          lastSyncTime: DateTime.now(),
        ),
        SyncStatusKind.unavailable,
      );
    });

    test('同步中优先于云端更新与正常', () {
      expect(
        resolveSyncStatus(
          canUseSync: true,
          isBusy: true,
          hasCloudUpdate: true,
          lastSyncTime: DateTime.now(),
        ),
        SyncStatusKind.syncing,
      );
    });

    test('可用但从未同步 → never（即使云端有更新标记）', () {
      expect(
        resolveSyncStatus(
          canUseSync: true,
          isBusy: false,
          hasCloudUpdate: true,
          lastSyncTime: null,
        ),
        SyncStatusKind.never,
      );
    });

    test('已同步且云端有更新 → cloudUpdate', () {
      expect(
        resolveSyncStatus(
          canUseSync: true,
          isBusy: false,
          hasCloudUpdate: true,
          lastSyncTime: DateTime.now(),
        ),
        SyncStatusKind.cloudUpdate,
      );
    });

    test('已同步且无云端更新 → synced', () {
      expect(
        resolveSyncStatus(
          canUseSync: true,
          isBusy: false,
          hasCloudUpdate: false,
          lastSyncTime: DateTime.now(),
        ),
        SyncStatusKind.synced,
      );
    });
  });

  group('syncRelativeTime', () {
    final now = DateTime(2026, 8, 2, 12, 0, 0);

    test('null → never', () {
      expect(syncRelativeTime(null, now).kind, SyncFreshness.never);
    });

    test('59 秒内 → justNow', () {
      final rel = syncRelativeTime(now.subtract(const Duration(seconds: 59)), now);
      expect(rel.kind, SyncFreshness.justNow);
    });

    test('时钟回拨（未来时间）→ justNow', () {
      final rel = syncRelativeTime(now.add(const Duration(minutes: 5)), now);
      expect(rel.kind, SyncFreshness.justNow);
    });

    test('3 分钟前 → minutesAgo(3)', () {
      final rel = syncRelativeTime(now.subtract(const Duration(minutes: 3)), now);
      expect(rel.kind, SyncFreshness.minutesAgo);
      expect(rel.count, 3);
    });

    test('59 分钟 → minutesAgo，60 分钟 → hoursAgo', () {
      expect(
        syncRelativeTime(now.subtract(const Duration(minutes: 59)), now).kind,
        SyncFreshness.minutesAgo,
      );
      final rel = syncRelativeTime(now.subtract(const Duration(hours: 1)), now);
      expect(rel.kind, SyncFreshness.hoursAgo);
      expect(rel.count, 1);
    });

    test('23 小时 → hoursAgo，24 小时 → daysAgo', () {
      expect(
        syncRelativeTime(now.subtract(const Duration(hours: 23)), now).kind,
        SyncFreshness.hoursAgo,
      );
      final rel = syncRelativeTime(now.subtract(const Duration(days: 2)), now);
      expect(rel.kind, SyncFreshness.daysAgo);
      expect(rel.count, 2);
    });

    test('7 天及以上 → stale（回退完整日期）', () {
      expect(
        syncRelativeTime(now.subtract(const Duration(days: 7)), now).kind,
        SyncFreshness.stale,
      );
    });
  });
}
