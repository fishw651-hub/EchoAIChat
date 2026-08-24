package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRequireClientVersion(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name        string
		versionCode string
		wantStatus  int
	}{
		{name: "missing", wantStatus: http.StatusUpgradeRequired},
		{name: "invalid", versionCode: "not-a-number", wantStatus: http.StatusUpgradeRequired},
		{name: "below minimum", versionCode: "66", wantStatus: http.StatusUpgradeRequired},
		{name: "minimum", versionCode: "67", wantStatus: http.StatusNoContent},
		{name: "newer", versionCode: "68", wantStatus: http.StatusNoContent},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.GET("/protected", RequireClientVersion(67), func(c *gin.Context) {
				c.Status(http.StatusNoContent)
			})

			request := httptest.NewRequest(http.MethodGet, "/protected", nil)
			if tt.versionCode != "" {
				request.Header.Set("X-Client-Version-Code", tt.versionCode)
			}
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)

			if response.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", response.Code, tt.wantStatus)
			}
		})
	}
}
