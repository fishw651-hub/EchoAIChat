package database

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInitMigratesJSONOnce(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(
		filepath.Join(dir, "User.json"),
		[]byte(`[{"ID":1,"Username":"alice"}]`),
		0o600,
	); err != nil {
		t.Fatalf("write legacy data: %v", err)
	}

	if err := Init(dir); err != nil {
		t.Fatalf("initialize database: %v", err)
	}

	var user struct {
		ID       uint
		Username string
	}
	if !Get().Register("User").FindByID(1, &user) {
		t.Fatal("migrated user was not found")
	}
	if user.Username != "alice" {
		t.Fatalf("username = %q, want alice", user.Username)
	}

	if _, err := os.Stat(filepath.Join(dir, "aichat.db")); err != nil {
		t.Fatalf("sqlite database was not created: %v", err)
	}
	if err := Get().Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}

	if err := Init(dir); err != nil {
		t.Fatalf("reinitialize database: %v", err)
	}
	defer Get().Close()
	if count := Get().Register("User").Count(nil); count != 1 {
		t.Fatalf("user count = %d, want 1", count)
	}
}
