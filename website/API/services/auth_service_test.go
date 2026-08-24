package services

import (
	"testing"

	"aichat-api/database"
)

func TestAuthServiceRegisterStartsWithZeroPermanentBalance(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	user, err := (&AuthService{}).Register("new-user", "new-user@example.com", "password123")
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	if user.Balance != 0 {
		t.Fatalf("new user permanent balance = %.2f, want 0", user.Balance)
	}
}
