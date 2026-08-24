package services

import (
	"testing"
	"time"
)

func TestNewerSyncItemUsesNormalizedUpdatedAt(t *testing.T) {
	older := map[string]interface{}{"value": "old", "sync_updated_at": int64(100)}
	newer := map[string]interface{}{"value": "new", "updated_at": int64(200)}

	winner, conflict := NewerSyncItem(older, newer)
	if winner["value"] != "new" || !conflict {
		t.Fatalf("winner/conflict = %#v/%v, want new/true", winner, conflict)
	}
}

func TestNewerSyncItemParsesRFC3339AndKeepsCloudOnTie(t *testing.T) {
	timestamp := time.Date(2026, 7, 15, 1, 2, 3, 0, time.UTC).Format(time.RFC3339Nano)
	local := map[string]interface{}{"value": "local", "updated_at": timestamp}
	cloud := map[string]interface{}{"value": "cloud", "updated_at": timestamp}

	winner, conflict := NewerSyncItem(local, cloud)
	if winner["value"] != "cloud" || conflict {
		t.Fatalf("winner/conflict = %#v/%v, want cloud/false", winner, conflict)
	}
}

func TestNewerSyncItemComparesFlutterMillisecondsWithRFC3339(t *testing.T) {
	newerTime := time.Date(2026, 7, 15, 3, 0, 0, 0, time.UTC)
	olderTime := newerTime.Add(-time.Minute)
	local := map[string]interface{}{
		"value": "local-new", "updated_at": newerTime.UnixMilli(),
	}
	cloud := map[string]interface{}{
		"value": "cloud-old", "updated_at": olderTime.Format(time.RFC3339Nano),
	}

	winner, _ := NewerSyncItem(local, cloud)
	if winner["value"] != "local-new" {
		t.Fatalf("winner = %#v, want Flutter millisecond record", winner)
	}
}

func TestSyncTombstoneWinsOnlyWhenNewerThanCloudRecord(t *testing.T) {
	cloud := map[string]interface{}{"updated_at": int64(200)}
	if SyncTombstoneWins(map[string]interface{}{"created_at": int64(100)}, cloud) {
		t.Fatal("older tombstone deleted a newer cloud record")
	}
	if !SyncTombstoneWins(map[string]interface{}{"created_at": int64(300)}, cloud) {
		t.Fatal("newer tombstone did not delete the older cloud record")
	}
}
