package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

func TestRefreshDailyAllowanceHandlerReturnsQuotaSnapshot(t *testing.T) {
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

	user := models.User{Username: "handler-user", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if err := database.Get().Register("SystemConfig").Insert(&models.SystemConfig{
		Key: "default_daily_quota", Value: "0.8",
	}); err != nil {
		t.Fatalf("insert config: %v", err)
	}

	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Request = httptest.NewRequest(http.MethodPost, "/api/v1/user/daily-allowance/refresh", nil)
	context.Set("user_id", user.ID)

	(&UserHandler{}).RefreshDailyAllowance(context)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
}
