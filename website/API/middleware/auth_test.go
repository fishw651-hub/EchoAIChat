package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func TestAuthRequiredRejectsDisabledUserWithValidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	config.AppConfig = &config.Config{}
	config.AppConfig.JWT.Secret = "test-secret-with-sufficient-length"
	config.AppConfig.JWT.ExpireHours = 24
	user := models.User{Username: "disabled", Role: "user", Status: 0}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	token, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	router := gin.New()
	router.GET("/private", AuthRequired(), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	request := httptest.NewRequest(http.MethodGet, "/private", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusUnauthorized)
	}
}

func TestAuthRequiredTracksActiveUser(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	config.AppConfig = &config.Config{}
	config.AppConfig.JWT.Secret = "test-secret-with-sufficient-length"
	config.AppConfig.JWT.ExpireHours = 24
	user := models.User{Username: "active", Role: "user", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	token, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	router := gin.New()
	router.GET("/private", AuthRequired(), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	request := httptest.NewRequest(http.MethodGet, "/private", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
	}
	if count := database.Get().Register("DailyActiveUser").Count(nil); count != 1 {
		t.Fatalf("daily active records = %d, want 1", count)
	}
}

// 改密/重置密码会递增 User.TokenVersion：已签发的旧 token 必须立即失效（401），
// 与 claims 版本一致的新 token 仍可正常访问。
func TestAuthRequiredRejectsStaleTokenVersion(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	config.AppConfig = &config.Config{}
	config.AppConfig.JWT.Secret = "test-secret-with-sufficient-length"
	config.AppConfig.JWT.ExpireHours = 24
	user := models.User{Username: "versioned", Role: "user", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	staleToken, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	// 模拟改密：TokenVersion 递增
	database.Get().Register("User").UpdateWhere(
		database.FilterEq("ID", user.ID),
		map[string]interface{}{"TokenVersion": user.TokenVersion + 1},
	)

	router := gin.New()
	router.GET("/private", AuthRequired(), func(c *gin.Context) { c.Status(http.StatusNoContent) })

	request := httptest.NewRequest(http.MethodGet, "/private", nil)
	request.Header.Set("Authorization", "Bearer "+staleToken)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("旧版本 token status = %d, want %d", response.Code, http.StatusUnauthorized)
	}

	freshToken, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion+1)
	if err != nil {
		t.Fatalf("generate fresh token: %v", err)
	}
	request2 := httptest.NewRequest(http.MethodGet, "/private", nil)
	request2.Header.Set("Authorization", "Bearer "+freshToken)
	response2 := httptest.NewRecorder()
	router.ServeHTTP(response2, request2)
	if response2.Code != http.StatusNoContent {
		t.Fatalf("新版本 token status = %d, want %d", response2.Code, http.StatusNoContent)
	}
}
