package config

import "testing"

func TestValidateJWTSecret(t *testing.T) {
	weak := []string{
		"",
		"   ",
		"change-this-to-a-strong-random-secret",
		"CHANGE-THIS-TO-A-STRONG-RANDOM-SECRET",
		"secret",
		"changeme",
		"short-key",
		"exactly-31-characters-long-xxxx",
	}
	for _, secret := range weak {
		if err := ValidateJWTSecret(secret); err == nil {
			t.Errorf("ValidateJWTSecret(%q) = nil, want error", secret)
		}
	}

	strong := []string{
		"exactly-32-characters-long-xxxxx",
		"a-very-strong-random-secret-with-plenty-of-entropy-0123456789",
	}
	for _, secret := range strong {
		if err := ValidateJWTSecret(secret); err != nil {
			t.Errorf("ValidateJWTSecret(%q) = %v, want nil", secret, err)
		}
	}
}
