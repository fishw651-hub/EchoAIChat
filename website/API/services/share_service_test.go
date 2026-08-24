package services

import (
	"errors"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

func setupShareTestDB(t *testing.T) {
	t.Helper()
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}

func TestCreateAndRedeemShareCode(t *testing.T) {
	setupShareTestDB(t)

	snapshot := []byte(`{"name":"测试智能体","persona":"温柔","avatar":"data:image/png;base64,AAAA"}`)
	code, expiresAt, err := CreateShareCode(1, snapshot)
	if err != nil {
		t.Fatalf("CreateShareCode: %v", err)
	}
	if len(code) != 6 {
		t.Fatalf("code = %q, want 6 digits", code)
	}
	for _, ch := range code {
		if ch < '0' || ch > '9' {
			t.Fatalf("code = %q contains non-digit", code)
		}
	}
	if !expiresAt.After(time.Now()) || expiresAt.After(time.Now().Add(ShareCodeTTL+time.Minute)) {
		t.Fatalf("expiresAt = %v, want about now+20min", expiresAt)
	}

	got, err := RedeemShareCode(code)
	if err != nil {
		t.Fatalf("RedeemShareCode: %v", err)
	}
	if string(got) != string(snapshot) {
		t.Fatalf("snapshot round-trip mismatch:\n got %s\nwant %s", got, snapshot)
	}
}

func TestRedeemShareCodeRejectsExpired(t *testing.T) {
	setupShareTestDB(t)

	// 直接插入一条已过期的记录
	if err := database.Get().Register("ShareCode").Insert(&models.ShareCode{
		Code:        "111111",
		OwnerUserID: 1,
		Snapshot:    `{"name":"旧"}`,
		ExpiresAt:   time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatalf("insert expired record: %v", err)
	}

	_, err := RedeemShareCode("111111")
	if !errors.Is(err, ErrShareCodeExpired) {
		t.Fatalf("err = %v, want ErrShareCodeExpired", err)
	}
}

func TestRedeemShareCodeRejectsUnknown(t *testing.T) {
	setupShareTestDB(t)

	_, err := RedeemShareCode("999999")
	if !errors.Is(err, ErrShareCodeNotFound) {
		t.Fatalf("err = %v, want ErrShareCodeNotFound", err)
	}
}

func TestRedeemShareCodeRepeatable(t *testing.T) {
	setupShareTestDB(t)

	snapshot := []byte(`{"name":"多人兑换"}`)
	code, _, err := CreateShareCode(2, snapshot)
	if err != nil {
		t.Fatalf("CreateShareCode: %v", err)
	}
	for i := 0; i < 3; i++ {
		got, err := RedeemShareCode(code)
		if err != nil {
			t.Fatalf("redeem #%d: %v", i+1, err)
		}
		if string(got) != string(snapshot) {
			t.Fatalf("redeem #%d mismatch", i+1)
		}
	}
}

func TestRedeemRateLimit(t *testing.T) {
	setupShareTestDB(t)

	userID := uint(90001)
	// 窗口内连续失败 RedeemMaxFailures 次后被拒
	for i := 0; i < RedeemMaxFailures; i++ {
		if err := CheckRedeemRateLimit(userID); err != nil {
			t.Fatalf("failure #%d should still be allowed, got %v", i+1, err)
		}
		RecordRedeemFailure(userID)
	}
	if err := CheckRedeemRateLimit(userID); !errors.Is(err, ErrRedeemRateLimited) {
		t.Fatalf("err = %v, want ErrRedeemRateLimited", err)
	}

	// 其他用户不受影响
	if err := CheckRedeemRateLimit(90002); err != nil {
		t.Fatalf("other user should not be limited: %v", err)
	}
}

func TestCreateShareCodeRejectsOversize(t *testing.T) {
	setupShareTestDB(t)

	oversize := make([]byte, shareMaxSnapshotBytes+1)
	_, _, err := CreateShareCode(1, oversize)
	if !errors.Is(err, ErrShareSnapshotTooLarge) {
		t.Fatalf("err = %v, want ErrShareSnapshotTooLarge", err)
	}

	_, _, err = CreateShareCode(1, nil)
	if !errors.Is(err, ErrShareSnapshotEmpty) {
		t.Fatalf("err = %v, want ErrShareSnapshotEmpty", err)
	}
}
