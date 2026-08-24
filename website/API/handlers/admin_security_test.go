package handlers

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

func TestAdminCannotPromoteUserToSuperAdmin(t *testing.T) {
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
	user := models.User{Username: "target", Role: "user", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	router := gin.New()
	router.PUT("/users/:id", func(c *gin.Context) {
		c.Set("role", "admin")
		(&AdminHandler{}).UpdateUser(c)
	})
	request := httptest.NewRequest(http.MethodPut, "/users/1", bytes.NewBufferString(`{"role":"super_admin"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusForbidden)
	}
	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("target user not found")
	}
	if after.Role != "user" {
		t.Fatalf("role = %q, want user", after.Role)
	}
}

// 普通管理员调用 CreateUser 指定 role=super_admin 必须被拒绝，且用户不得落库
func TestAdminCreateUserCannotElevateRole(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	router := gin.New()
	router.POST("/users", func(c *gin.Context) {
		c.Set("role", "admin")
		(&AdminHandler{}).CreateUser(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/users",
		bytes.NewBufferString(`{"username":"evil","password":"password123","role":"super_admin"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusForbidden)
	}
	var created models.User
	if database.Get().Register("User").FindOne(database.FilterEq("Username", "evil"), &created) {
		t.Fatal("user must not be created when role elevation is rejected")
	}
}

// CreateUser / ListUsers / GetUser 的响应均不得包含 PasswordHash
func TestAdminUserResponsesOmitPasswordHash(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	const hashMarker = "$2a$12$secrethashmarkermustnotleak"
	seed := models.User{Username: "seed", PasswordHash: hashMarker, Role: "user", Status: 1}
	if err := database.Get().Register("User").Insert(&seed); err != nil {
		t.Fatalf("insert seed user: %v", err)
	}

	handler := &AdminHandler{}
	router := gin.New()
	router.POST("/users", func(c *gin.Context) {
		c.Set("role", "super_admin")
		handler.CreateUser(c)
	})
	router.GET("/users", handler.ListUsers)
	router.GET("/users/:id", handler.GetUser)

	assertNoHash := func(name string, response *httptest.ResponseRecorder) {
		t.Helper()
		if response.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want %d", name, response.Code, http.StatusOK)
		}
		body := response.Body.String()
		if strings.Contains(body, "PasswordHash") || strings.Contains(body, hashMarker) || strings.Contains(body, "$2a$") {
			t.Fatalf("%s response leaks password hash: %s", name, body)
		}
	}

	createReq := httptest.NewRequest(http.MethodPost, "/users",
		bytes.NewBufferString(`{"username":"newuser","password":"password123","role":"admin"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createResp := httptest.NewRecorder()
	router.ServeHTTP(createResp, createReq)
	assertNoHash("CreateUser", createResp)

	listReq := httptest.NewRequest(http.MethodGet, "/users", nil)
	listResp := httptest.NewRecorder()
	router.ServeHTTP(listResp, listReq)
	assertNoHash("ListUsers", listResp)

	getReq := httptest.NewRequest(http.MethodGet, "/users/1", nil)
	getResp := httptest.NewRecorder()
	router.ServeHTTP(getResp, getReq)
	assertNoHash("GetUser", getResp)

	// 顺带确认 json:"-" 不影响落库：哈希仍能从 DB 读回（登录依赖该字段）
	var stored models.User
	if !database.Get().Register("User").FindByID(seed.ID, &stored) {
		t.Fatal("seed user not found")
	}
	if stored.PasswordHash != hashMarker {
		t.Fatalf("stored PasswordHash = %q, want %q (persistence broken by json tag?)", stored.PasswordHash, hashMarker)
	}
}
