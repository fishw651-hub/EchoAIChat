package services

import "testing"

func TestNormalizeEncryptionKey(t *testing.T) {
	t.Run("pads short key to 32 bytes", func(t *testing.T) {
		got := NormalizeEncryptionKey("short-key")
		if len(got) != 32 {
			t.Fatalf("expected key length 32, got %d", len(got))
		}
		if string(got[:9]) != "short-key" {
			t.Fatalf("expected prefix to be preserved, got %q", string(got[:9]))
		}
	})

	t.Run("truncates long key to 32 bytes", func(t *testing.T) {
		src := "1234567890123456789012345678901234567890"
		got := NormalizeEncryptionKey(src)
		if len(got) != 32 {
			t.Fatalf("expected key length 32, got %d", len(got))
		}
		if string(got) != src[:32] {
			t.Fatalf("expected first 32 bytes to be kept, got %q", string(got))
		}
	})
}
