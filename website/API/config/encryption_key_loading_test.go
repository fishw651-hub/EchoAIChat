package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigAssignsPriorityEncryptionKeyToRuntimeConfig(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", "")
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.yaml")
	fileKey := strings.Repeat("f", 48)
	configKey := strings.Repeat("c", 48)

	configYAML := "jwt:\n" +
		"  secret: " + strings.Repeat("j", 32) + "\n" +
		"encryption:\n" +
		"  key: " + configKey + "\n"
	if err := os.WriteFile(configPath, []byte(configYAML), 0600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".encryption_key"), []byte(fileKey), 0600); err != nil {
		t.Fatalf("write key file: %v", err)
	}

	LoadConfig(configPath)

	if AppConfig.Encryption.Key != fileKey {
		t.Fatalf("runtime encryption key did not use priority key file")
	}
	if len(EncryptionFallbackKeys) != 1 || EncryptionFallbackKeys[0] != configKey {
		t.Fatalf("previous config key was not retained as a decryption fallback")
	}
}
