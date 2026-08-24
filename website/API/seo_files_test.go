package main

import (
	"os"
	"strings"
	"testing"
)

func TestSEOFilesUseCanonicalLandingURL(t *testing.T) {
	robots, err := os.ReadFile("robots.txt")
	if err != nil {
		t.Fatal(err)
	}
	sitemap, err := os.ReadFile("sitemap.xml")
	if err != nil {
		t.Fatal(err)
	}

	robotsText := string(robots)
	sitemapText := string(sitemap)
	if !strings.Contains(robotsText, "Sitemap: https://example.com/sitemap.xml") {
		t.Fatal("robots.txt sitemap URL is missing")
	}
	for _, path := range []string{"/api/v1/admin/", "/api/v1/auth/", "/api/v1/chat/", "/api/v1/user/", "/api/v1/sync"} {
		if !strings.Contains(robotsText, "Disallow: "+path) {
			t.Fatalf("robots.txt should disallow %s", path)
		}
	}
	if !strings.Contains(sitemapText, "<loc>https://example.com/landing/</loc>") {
		t.Fatal("sitemap canonical landing URL is missing")
	}
	if !strings.Contains(sitemapText, "<lastmod>2026-07-28</lastmod>") {
		t.Fatal("sitemap lastmod is stale")
	}
}
