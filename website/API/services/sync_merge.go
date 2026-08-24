package services

import (
	"encoding/json"
	"strconv"
	"time"
)

func NewerSyncItem(local, cloud map[string]interface{}) (map[string]interface{}, bool) {
	localTime := syncItemTimestamp(local)
	cloudTime := syncItemTimestamp(cloud)
	if localTime > cloudTime {
		return cloneSyncItem(local), localTime != cloudTime
	}
	return cloneSyncItem(cloud), localTime != cloudTime
}

func SyncTombstoneWins(tombstone, cloud map[string]interface{}) bool {
	tombstoneTime := syncItemTimestamp(tombstone)
	cloudTime := syncItemTimestamp(cloud)
	if tombstoneTime == 0 && cloudTime == 0 {
		return true
	}
	return tombstoneTime > cloudTime
}

func syncItemTimestamp(item map[string]interface{}) int64 {
	for _, key := range []string{
		"sync_updated_at", "SyncUpdatedAt", "updated_at", "UpdatedAt",
		"timestamp", "Timestamp", "created_at", "CreatedAt",
	} {
		value, ok := item[key]
		if !ok || value == nil {
			continue
		}
		if timestamp, ok := normalizeSyncTimestamp(value); ok {
			return timestamp
		}
	}
	return 0
}

func normalizeSyncTimestamp(value interface{}) (int64, bool) {
	switch number := value.(type) {
	case int:
		return normalizeEpochNumber(int64(number)), true
	case int64:
		return normalizeEpochNumber(number), true
	case uint64:
		if number > uint64(^uint64(0)>>1) {
			return 0, false
		}
		return normalizeEpochNumber(int64(number)), true
	case float64:
		return normalizeEpochNumber(int64(number)), true
	case json.Number:
		parsed, err := number.Int64()
		return normalizeEpochNumber(parsed), err == nil
	case string:
		if parsed, err := time.Parse(time.RFC3339Nano, number); err == nil {
			return parsed.UnixNano(), true
		}
		parsed, err := strconv.ParseInt(number, 10, 64)
		return normalizeEpochNumber(parsed), err == nil
	default:
		return 0, false
	}
}

func normalizeEpochNumber(number int64) int64 {
	switch {
	case number >= 100_000_000_000_000_000:
		return number
	case number >= 100_000_000_000_000:
		return number * int64(time.Microsecond)
	case number >= 100_000_000_000:
		return number * int64(time.Millisecond)
	case number >= 1_000_000_000:
		return number * int64(time.Second)
	default:
		return number
	}
}
