package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

func TestDashboardDAURejectsUnsupportedRange(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	router := gin.New()
	router.GET("/dashboard", (&AdminHandler{}).Dashboard)
	request := httptest.NewRequest(http.MethodGet, "/dashboard?days=14", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var body struct {
		Code int `json:"code"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Code != 40000 {
		t.Fatalf("code = %d, want 40000", body.Code)
	}
}

func TestDashboardDAUReturnsTrendData(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	tracker := services.NewDailyActiveService()
	if err := tracker.Track(7, "user", time.Now()); err != nil {
		t.Fatalf("track daily active: %v", err)
	}

	router := gin.New()
	router.GET("/dashboard", (&AdminHandler{}).Dashboard)
	request := httptest.NewRequest(http.MethodGet, "/dashboard?days=7", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	var body struct {
		Code int `json:"code"`
		Data struct {
			ActiveUsersToday     int                         `json:"active_users_today"`
			ActiveUsersYesterday int                         `json:"active_users_yesterday"`
			ActiveChangePercent  float64                     `json:"active_change_percent"`
			DAUPeak              int                         `json:"dau_peak"`
			DAUAverage           float64                     `json:"dau_average"`
			DAUTrend             []services.DailyActivePoint `json:"dau_trend"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Code != 0 {
		t.Fatalf("code = %d, want 0", body.Code)
	}
	if body.Data.ActiveUsersToday != 1 {
		t.Fatalf("active users today = %d, want 1", body.Data.ActiveUsersToday)
	}
	if len(body.Data.DAUTrend) != 7 {
		t.Fatalf("trend length = %d, want 7", len(body.Data.DAUTrend))
	}
	if body.Data.DAUTrend[6].Count != 1 {
		t.Fatalf("latest trend count = %d, want 1", body.Data.DAUTrend[6].Count)
	}
}
