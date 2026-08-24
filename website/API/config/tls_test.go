package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/viper"
)

func TestTLSConfigValidateRequiresCompleteManualCertificate(t *testing.T) {
	if err := (TLSConfig{Enabled: true, CertFile: "server.crt"}).Validate(); err == nil {
		t.Fatal("expected missing key error")
	}
	if err := (TLSConfig{Enabled: true, CertFile: "server.crt", KeyFile: "server.key"}).Validate(); err != nil {
		t.Fatalf("valid manual certificate rejected: %v", err)
	}
}

func TestTLSConfigValidateRequiresACMEDomain(t *testing.T) {
	cfg := TLSConfig{Enabled: true, AutoACME: true, ACMEEmail: "admin@example.com"}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected missing ACME domain error")
	}
	cfg.ACMEDomains = []string{"example.com"}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("valid ACME config rejected: %v", err)
	}
}

func TestTLSConfigAcceptsAdminSnakeCaseJSON(t *testing.T) {
	var cfg TLSConfig
	err := json.Unmarshal([]byte(`{"enabled":true,"auto_acme":true,"acme_domains":["example.com"],"cache_dir":"./acme"}`), &cfg)
	if err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !cfg.Enabled || !cfg.AutoACME || len(cfg.ACMEDomains) != 1 || cfg.CacheDir != "./acme" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestGetTLSConfigReturnsIndependentDomainSlice(t *testing.T) {
	originalConfig := AppConfig
	AppConfig = &Config{TLS: TLSConfig{ACMEDomains: []string{"example.com"}}}
	t.Cleanup(func() { AppConfig = originalConfig })

	got := GetTLSConfig()
	got.ACMEDomains[0] = "changed.example.com"
	if AppConfig.TLS.ACMEDomains[0] != "example.com" {
		t.Fatalf("GetTLSConfig exposed the runtime domain slice: %+v", AppConfig.TLS.ACMEDomains)
	}
}

func TestSaveTLSConfigKeepsSnakeCaseAndOtherSettings(t *testing.T) {
	viper.Reset()
	originalConfig := AppConfig
	t.Cleanup(func() {
		viper.Reset()
		AppConfig = originalConfig
	})

	configPath := filepath.Join(t.TempDir(), "config.yaml")
	initial := []byte("server:\n  port: 8080\ntls:\n  enabled: false\n")
	if err := os.WriteFile(configPath, initial, 0o600); err != nil {
		t.Fatalf("write initial config: %v", err)
	}
	viper.SetConfigFile(configPath)
	if err := viper.ReadInConfig(); err != nil {
		t.Fatalf("read initial config: %v", err)
	}
	AppConfig = &Config{}

	want := TLSConfig{
		Enabled:     true,
		Port:        8443,
		AutoACME:    true,
		ACMEEmail:   "admin@example.com",
		ACMEDomains: []string{"Example.COM"},
		CacheDir:    "./acme-cache",
	}
	if err := SaveTLSConfig(want); err != nil {
		t.Fatalf("save TLS config: %v", err)
	}

	written, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read saved config: %v", err)
	}
	text := string(written)
	for _, key := range []string{"auto_acme:", "acme_email:", "acme_domains:", "cache_dir:"} {
		if !strings.Contains(text, key) {
			t.Errorf("saved config missing snake_case key %q:\n%s", key, text)
		}
	}
	if !strings.Contains(text, "port: 8080") {
		t.Fatalf("unrelated server config was not preserved:\n%s", text)
	}
	if got := AppConfig.TLS.ACMEDomains; len(got) != 1 || got[0] != "example.com" {
		t.Fatalf("runtime TLS config was not normalized: %+v", AppConfig.TLS)
	}
}
