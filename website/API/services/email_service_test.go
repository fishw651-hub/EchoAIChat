package services

import (
	"regexp"
	"strings"
	"testing"
	"time"
)

func TestNormalizeTLSMode(t *testing.T) {
	tests := []struct {
		name      string
		mode      string
		legacyTLS string
		port      int
		want      string
	}{
		{name: "explicit starttls", mode: "starttls", legacyTLS: "1", port: 587, want: SMTPTLSStartTLS},
		{name: "explicit ssl", mode: "ssl", legacyTLS: "1", port: 465, want: SMTPTLSSSL},
		{name: "legacy off", mode: "", legacyTLS: "0", port: 587, want: SMTPTLSNone},
		{name: "465 defaults to ssl", mode: "", legacyTLS: "1", port: 465, want: SMTPTLSSSL},
		{name: "587 defaults to starttls", mode: "", legacyTLS: "1", port: 587, want: SMTPTLSStartTLS},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := normalizeTLSMode(tt.mode, tt.legacyTLS, tt.port)
			if got != tt.want {
				t.Fatalf("normalizeTLSMode() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestNormalizeAuthMode(t *testing.T) {
	tests := []struct {
		name     string
		mode     string
		username string
		password string
		want     string
	}{
		{name: "explicit none", mode: "none", want: SMTPAuthNone},
		{name: "explicit plain", mode: "plain", want: SMTPAuthPlain},
		{name: "username implies plain", username: "noreply@example.com", want: SMTPAuthPlain},
		{name: "password implies plain", password: "secret", want: SMTPAuthPlain},
		{name: "empty implies none", want: SMTPAuthNone},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := normalizeAuthMode(tt.mode, tt.username, tt.password)
			if got != tt.want {
				t.Fatalf("normalizeAuthMode() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestLocalSMTPConfigFromEnv(t *testing.T) {
	t.Run("disabled when no local smtp env is present", func(t *testing.T) {
		cfg := localSMTPConfigFromEnv(func(string) string { return "" })
		if cfg != nil {
			t.Fatalf("expected nil config, got %+v", cfg)
		}
	})

	t.Run("builds config from local smtp env", func(t *testing.T) {
		env := map[string]string{
			"AICHAT_LOCAL_SMTP_ENABLED":   "true",
			"AICHAT_LOCAL_SMTP_HOST":      "127.0.0.1",
			"AICHAT_LOCAL_SMTP_PORT":      "587",
			"AICHAT_LOCAL_SMTP_USERNAME":  "mailer",
			"AICHAT_LOCAL_SMTP_PASSWORD":  "secret",
			"AICHAT_LOCAL_SMTP_FROM":      "noreply@example.com",
			"AICHAT_LOCAL_SMTP_TLS_MODE":  "starttls",
			"AICHAT_LOCAL_SMTP_AUTH_MODE": "plain",
		}
		cfg := localSMTPConfigFromEnv(func(key string) string { return env[key] })
		if cfg == nil {
			t.Fatal("expected local smtp config, got nil")
		}
		if cfg.Host != "127.0.0.1" || cfg.Port != 587 {
			t.Fatalf("unexpected host/port: %+v", cfg)
		}
		if cfg.TLSMode != SMTPTLSStartTLS || cfg.AuthMode != SMTPAuthPlain {
			t.Fatalf("unexpected modes: %+v", cfg)
		}
		if cfg.From != "noreply@example.com" {
			t.Fatalf("unexpected from: %+v", cfg)
		}
	})
}

func TestRenderVerificationEmail(t *testing.T) {
	t.Run("uses defaults when templates are empty", func(t *testing.T) {
		subject, body := renderVerificationEmail("register", "123456", func(string) string { return "" })
		if subject == "" {
			t.Fatal("expected default subject")
		}
		if !strings.Contains(body, "123456") {
			t.Fatalf("expected default body to contain code, got %q", body)
		}
	})

	t.Run("renders custom register template variables", func(t *testing.T) {
		values := map[string]string{
			emailCodeRegisterSubjectKey: "Code {{code}} for {{app_name}}",
			emailCodeRegisterBodyKey:    "Use {{code}} within {{ttl_minutes}} minutes for {{purpose}} on {{app_name}}.",
			emailAppNameKey:             "Echo",
		}
		subject, body := renderVerificationEmail("register", "654321", func(key string) string {
			return values[key]
		})
		if subject != "Code 654321 for Echo" {
			t.Fatalf("subject = %q", subject)
		}
		wantBody := "Use 654321 within 10 minutes for register on Echo."
		if body != wantBody {
			t.Fatalf("body = %q, want %q", body, wantBody)
		}
	})

	t.Run("renders reset template variables", func(t *testing.T) {
		values := map[string]string{
			emailCodeResetSubjectKey: "Reset {{code}}",
			emailCodeResetBodyKey:    "Reset code {{code}} expires in {{ttl_minutes}}.",
		}
		subject, body := renderVerificationEmail("reset", "111222", func(key string) string {
			return values[key]
		})
		if subject != "Reset 111222" {
			t.Fatalf("subject = %q", subject)
		}
		if body != "Reset code 111222 expires in 10." {
			t.Fatalf("body = %q", body)
		}
	})
}

func TestGenerateVerificationCode(t *testing.T) {
	code, err := generateVerificationCode()
	if err != nil {
		t.Fatalf("generateVerificationCode returned error: %v", err)
	}
	if !regexp.MustCompile(`^\d{12}$`).MatchString(code) {
		t.Fatalf("code = %q, want 12 digits", code)
	}
}

func TestVerifyCodeRejectsExpiredCode(t *testing.T) {
	codeStore = map[string]*emailCode{}
	codeStore["expired@example.com"] = &emailCode{
		code:      "123456789012",
		expiresAt: time.Now().Add(-time.Second),
		purpose:   "register",
	}

	if VerifyCode("expired@example.com", "123456789012", "register") {
		t.Fatal("expected expired code to be rejected")
	}
	if _, ok := codeStore["expired@example.com"]; ok {
		t.Fatal("expected expired code to be deleted")
	}
}
