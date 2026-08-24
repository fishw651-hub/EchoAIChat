package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

func TestBackgroundPressureRejectsBulkTrafficWithoutBlockingChat(t *testing.T) {
	gin.SetMode(gin.TestMode)
	limiter := services.NewAdaptiveLimiter(services.AdaptiveLimiterConfig{
		MinConcurrency: 1,
		MaxConcurrency: 1,
	})
	if !limiter.TryAcquire() {
		t.Fatal("failed to occupy limiter slot")
	}

	router := gin.New()
	router.GET("/sync", BackgroundPressure(limiter), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	router.GET("/chat", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	syncResponse := httptest.NewRecorder()
	router.ServeHTTP(syncResponse, httptest.NewRequest(http.MethodGet, "/sync", nil))
	if syncResponse.Code != http.StatusTooManyRequests {
		t.Fatalf("sync status = %d, want 429", syncResponse.Code)
	}
	if syncResponse.Header().Get("Retry-After") != "1" {
		t.Fatalf("Retry-After = %q, want 1", syncResponse.Header().Get("Retry-After"))
	}

	chatResponse := httptest.NewRecorder()
	router.ServeHTTP(chatResponse, httptest.NewRequest(http.MethodGet, "/chat", nil))
	if chatResponse.Code != http.StatusOK {
		t.Fatalf("chat status = %d, want 200", chatResponse.Code)
	}
}

func TestBackgroundPressureReleasesSlotAfterHandlerPanic(t *testing.T) {
	gin.SetMode(gin.TestMode)
	limiter := services.NewAdaptiveLimiter(services.AdaptiveLimiterConfig{
		MinConcurrency:     1,
		MaxConcurrency:     4,
		InitialConcurrency: 4,
	})
	router := gin.New()
	router.Use(gin.Recovery())
	router.GET("/panic", BackgroundPressure(limiter), func(c *gin.Context) {
		panic("boom")
	})
	router.GET("/healthy", BackgroundPressure(limiter), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	panicResponse := httptest.NewRecorder()
	router.ServeHTTP(panicResponse, httptest.NewRequest(http.MethodGet, "/panic", nil))

	healthyResponse := httptest.NewRecorder()
	router.ServeHTTP(healthyResponse, httptest.NewRequest(http.MethodGet, "/healthy", nil))
	if healthyResponse.Code != http.StatusOK {
		t.Fatalf("healthy status after panic = %d, want 200", healthyResponse.Code)
	}
	if limiter.Limit() != 2 {
		t.Fatalf("limit after panic = %d, want 2", limiter.Limit())
	}
}
