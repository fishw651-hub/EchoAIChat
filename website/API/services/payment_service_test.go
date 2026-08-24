package services

import (
	"testing"

	"aichat-api/database"
)

func TestPaymentServiceCreateZeroDropOrderIsDisabled(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	orderNo, payURL, amount, name, pid, sign, err := (&PaymentService{}).CreateZeroDropOrder(
		1,
		"user",
		10,
		"wxpay",
	)

	if err == nil {
		t.Fatal("CreateZeroDropOrder error = nil, want disabled error")
	}
	if orderNo != "" || payURL != "" || amount != 0 || name != "" || pid != "" || sign != "" {
		t.Fatalf("CreateZeroDropOrder returned order data for disabled zero drop")
	}
	if count := database.Get().Register("PaymentOrder").Count(nil); count != 0 {
		t.Fatalf("payment order count = %d, want 0", count)
	}
}
