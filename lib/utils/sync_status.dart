/// 多端同步状态的纯逻辑判定与相对时间计算（无 Flutter 依赖，便于单测）。
library;

/// 同步状态类别（用于状态卡展示）。
enum SyncStatusKind {
  /// 订阅不含同步权益 / 未订阅
  unavailable,

  /// 正在上传/下载/执行同步
  syncing,

  /// 云端有新内容待同步
  cloudUpdate,

  /// 已同步过且一切正常
  synced,

  /// 可用但从未同步过
  never,
}

/// 根据同步状态快照判定当前应展示的状态类别。
/// 优先级：不可用 > 同步中 > 从未同步 > 云端有更新 > 正常。
SyncStatusKind resolveSyncStatus({
  required bool canUseSync,
  required bool isBusy,
  required bool hasCloudUpdate,
  required DateTime? lastSyncTime,
}) {
  if (!canUseSync) return SyncStatusKind.unavailable;
  if (isBusy) return SyncStatusKind.syncing;
  if (lastSyncTime == null) return SyncStatusKind.never;
  if (hasCloudUpdate) return SyncStatusKind.cloudUpdate;
  return SyncStatusKind.synced;
}

/// 相对时间类别。
enum SyncFreshness {
  /// 从未同步
  never,

  /// 1 分钟内
  justNow,

  /// N 分钟前（< 1 小时）
  minutesAgo,

  /// N 小时前（< 24 小时）
  hoursAgo,

  /// N 天前（< 7 天）
  daysAgo,

  /// 超过 7 天，界面应回退到完整日期格式
  stale,
}

/// 相对时间结果：[kind] 为类别，[count] 仅在 minutes/hours/days 时有意义。
class SyncRelativeTime {
  final SyncFreshness kind;
  final int count;

  const SyncRelativeTime(this.kind, [this.count = 0]);
}

/// 计算上次同步时间与 [now] 的相对关系。
/// 时钟回拨（lastSync 在未来）按"刚刚"处理。
SyncRelativeTime syncRelativeTime(DateTime? lastSync, DateTime now) {
  if (lastSync == null) return const SyncRelativeTime(SyncFreshness.never);
  var diff = now.difference(lastSync);
  if (diff.isNegative) diff = Duration.zero;
  if (diff.inSeconds < 60) return const SyncRelativeTime(SyncFreshness.justNow);
  if (diff.inMinutes < 60) {
    return SyncRelativeTime(SyncFreshness.minutesAgo, diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return SyncRelativeTime(SyncFreshness.hoursAgo, diff.inHours);
  }
  if (diff.inDays < 7) {
    return SyncRelativeTime(SyncFreshness.daysAgo, diff.inDays);
  }
  return const SyncRelativeTime(SyncFreshness.stale);
}
