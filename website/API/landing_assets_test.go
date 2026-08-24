package main

import (
	"os"
	"strings"
	"testing"
)

func TestLandingReferencesServedAssets(t *testing.T) {
	content, err := os.ReadFile("landing/index.html")
	if err != nil {
		t.Fatalf("read landing/index.html: %v", err)
	}

	html := string(content)

	requiredRefs := []string{
		`src="assets/favicon.png"`,
		`src="assets/hero-main.jpg"`,
	}

	for _, ref := range requiredRefs {
		if !strings.Contains(html, ref) {
			t.Fatalf("landing page should reference served asset path %q", ref)
		}
	}

	for _, badRef := range []string{
		`src="..favicon.png"`,
		`src="../assets/hero-main.jpg"`,
	} {
		if strings.Contains(html, badRef) {
			t.Fatalf("landing page still contains broken asset path %q", badRef)
		}
	}
}

func TestLandingContainsCurrentSEOAndDownloadSignals(t *testing.T) {
	content, err := os.ReadFile("landing/index.html")
	if err != nil {
		t.Fatalf("read landing/index.html: %v", err)
	}
	html := string(content)

	required := []string{
		`>回响AI · 会记忆的 AI 智能聊天伙伴</h1>`,
		`"softwareVersion": "5.3.3"`,
		`"operatingSystem": "Android"`,
		`"downloadUrl": "https://example.com/api/v1/update/download/8"`,
		`"sameAs": "https://github.com/fishw651-hub/EchoAIChat"`,
		`href="/api/v1/update/download/8"`,
		`href="/web/"`,
		`data-download-link`,
		`data-app-version`,
	}
	for _, signal := range required {
		if !strings.Contains(html, signal) {
			t.Fatalf("landing page is missing %q", signal)
		}
	}

	forbidden := []string{`v3.2`, `支持 Android 与 iOS`, `href="javascript:void(0)"`}
	for _, signal := range forbidden {
		if strings.Contains(html, signal) {
			t.Fatalf("landing page still contains stale signal %q", signal)
		}
	}
}
