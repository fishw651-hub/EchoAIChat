package routes

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestPublicWebRoutesSupportGetAndHead(t *testing.T) {
	gin.SetMode(gin.TestMode)
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "landing", "assets"), 0o755); err != nil {
		t.Fatal(err)
	}

	files := map[string]string{
		filepath.Join(root, "landing", "index.html"):        "<h1>回响</h1>",
		filepath.Join(root, "landing", "assets", "app.css"): "body{}",
		filepath.Join(root, "robots.txt"):                   "User-agent: *\n",
		filepath.Join(root, "sitemap.xml"):                  "<urlset></urlset>",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	engine := gin.New()
	SetupPublicWebRoutes(engine, root)

	cases := []struct {
		method   string
		path     string
		status   int
		location string
		cache    string
	}{
		{http.MethodGet, "/", http.StatusMovedPermanently, "/landing/", ""},
		{http.MethodHead, "/", http.StatusMovedPermanently, "/landing/", ""},
		{http.MethodGet, "/landing", http.StatusMovedPermanently, "/landing/", ""},
		{http.MethodHead, "/landing", http.StatusMovedPermanently, "/landing/", ""},
		{http.MethodGet, "/landing/", http.StatusOK, "", "public, max-age=0, must-revalidate"},
		{http.MethodHead, "/landing/", http.StatusOK, "", "public, max-age=0, must-revalidate"},
		{http.MethodHead, "/landing/assets/app.css", http.StatusOK, "", "public, max-age=86400"},
		{http.MethodHead, "/robots.txt", http.StatusOK, "", ""},
		{http.MethodHead, "/sitemap.xml", http.StatusOK, "", ""},
	}

	for _, testCase := range cases {
		request := httptest.NewRequest(testCase.method, testCase.path, nil)
		response := httptest.NewRecorder()
		engine.ServeHTTP(response, request)

		if response.Code != testCase.status {
			t.Fatalf("%s %s: got %d, want %d", testCase.method, testCase.path, response.Code, testCase.status)
		}
		if testCase.location != "" && response.Header().Get("Location") != testCase.location {
			t.Fatalf("%s %s: got Location %q", testCase.method, testCase.path, response.Header().Get("Location"))
		}
		if testCase.cache != "" && response.Header().Get("Cache-Control") != testCase.cache {
			t.Fatalf("%s %s: got Cache-Control %q", testCase.method, testCase.path, response.Header().Get("Cache-Control"))
		}
		if testCase.method == http.MethodHead {
			body, err := io.ReadAll(response.Result().Body)
			if err != nil {
				t.Fatal(err)
			}
			if len(body) != 0 {
				t.Fatalf("HEAD %s returned %d body bytes", testCase.path, len(body))
			}
		}
	}
}
