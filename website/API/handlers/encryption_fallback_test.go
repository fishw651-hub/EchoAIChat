package handlers

import (
	"strings"
	"testing"

	"aichat-api/config"
	"aichat-api/services"
)

func TestDecryptFieldUsesLegacyConfigKeyFallback(t *testing.T) {
	primaryKey := strings.Repeat("p", 48)
	fallbackKey := strings.Repeat("f", 48)
	config.AppConfig = &config.Config{
		Encryption: config.EncryptionConfig{Key: primaryKey},
	}
	config.EncryptionFallbackKeys = []string{fallbackKey}
	services.ConfigureRuntime(services.RuntimeConfig{
		EncryptionKey:          func() string { return config.AppConfig.Encryption.Key },
		EncryptionFallbackKeys: func() []string { return config.EncryptionFallbackKeys },
	})
	t.Cleanup(func() { config.EncryptionFallbackKeys = nil })

	encrypted, err := services.Encrypt(
		"developer persona",
		services.NormalizeEncryptionKey(fallbackKey),
	)
	if err != nil {
		t.Fatalf("encrypt fixture: %v", err)
	}

	if got := decryptField(encrypted); got != "developer persona" {
		t.Fatalf("decryptField() = %q, want developer persona", got)
	}
}
