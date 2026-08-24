package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

func setupMaintenanceTestDB(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}

func setMaintenanceConfig(t *testing.T, enabled, bypassKey string) {
	t.Helper()
	tbl := database.Get().Register("SystemConfig")
	save := func(key, value string) {
		var sc models.SystemConfig
		if tbl.FindOne(database.FilterEq("Key", key), &sc) {
			if err := tbl.UpdateWhere(database.FilterEq("Key", key), map[string]interface{}{"Value": value}); err != nil {
				t.Fatal(err)
			}
		} else if err := tbl.Insert(&models.SystemConfig{Key: key, Value: value}); err != nil {
			t.Fatal(err)
		}
	}
	save("maintenance_enabled", enabled)
	save("maintenance_bypass_key", bypassKey)
}

func newMaintenanceRouter() *gin.Engine {
	r := gin.New()
	ok := func(c *gin.Context) { c.String(http.StatusOK, "ok") }
	landingGuard := MaintenanceGuard(MaintenancePageLanding)
	r.GET("/", landingGuard, ok)
	r.GET("/landing/*filepath", landingGuard, ok)
	r.GET("/admin/*filepath", MaintenanceGuard(MaintenancePageAdmin), ok)
	return r
}

func doMaintenanceRequest(r *gin.Engine, target, cookieValue string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, target, nil)
	if cookieValue != "" {
		req.Header.Set("Cookie", "maint_key="+cookieValue)
	}
	recorder := httptest.NewRecorder()
	r.ServeHTTP(recorder, req)
	return recorder
}

func TestMaintenanceGuardDisabledPassesThrough(t *testing.T) {
	setupMaintenanceTestDB(t)
	setMaintenanceConfig(t, "false", "somekey")
	router := newMaintenanceRouter()

	for _, target := range []string{"/", "/landing/", "/landing/index.html", "/admin/index.html", "/admin/login.html"} {
		if rec := doMaintenanceRequest(router, target, ""); rec.Code != http.StatusOK {
			t.Fatalf("GET %s status = %d, want 200 (maintenance disabled)", target, rec.Code)
		}
	}
}

func TestMaintenanceGuardBlocksLandingPagesButNotAssets(t *testing.T) {
	setupMaintenanceTestDB(t)
	setMaintenanceConfig(t, "true", "somekey")
	router := newMaintenanceRouter()

	blocked := []string{"/", "/landing/", "/landing/index.html", "/landing/download.html", "/landing/about"}
	for _, target := range blocked {
		rec := doMaintenanceRequest(router, target, "")
		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("GET %s status = %d, want 503", target, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "站点更新维护中") {
			t.Fatalf("GET %s body missing maintenance notice: %q", target, rec.Body.String())
		}
		if rec.Header().Get("Retry-After") != "300" {
			t.Fatalf("GET %s Retry-After = %q, want 300", target, rec.Header().Get("Retry-After"))
		}
	}

	allowed := []string{"/landing/css/landing.css", "/landing/js/landing.js", "/landing/assets/hero-main.jpg", "/landing/favicon.png"}
	for _, target := range allowed {
		if rec := doMaintenanceRequest(router, target, ""); rec.Code != http.StatusOK {
			t.Fatalf("GET %s status = %d, want 200 (static asset)", target, rec.Code)
		}
	}
}

func TestMaintenanceGuardAdminBypassByQueryKeyAndCookie(t *testing.T) {
	setupMaintenanceTestDB(t)
	setMaintenanceConfig(t, "true", "secret123")
	router := newMaintenanceRouter()

	// 入口页被拦截
	for _, target := range []string{"/admin/", "/admin/index.html", "/admin/login.html"} {
		if rec := doMaintenanceRequest(router, target, ""); rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("GET %s status = %d, want 503", target, rec.Code)
		}
	}

	// 后台静态资源放行（带 maint_key 进入后台后需正常加载 js/css）
	for _, target := range []string{"/admin/js/app.js", "/admin/css/admin.css"} {
		if rec := doMaintenanceRequest(router, target, ""); rec.Code != http.StatusOK {
			t.Fatalf("GET %s status = %d, want 200 (admin asset)", target, rec.Code)
		}
	}

	// 正确 maint_key 旁路成功并写 cookie
	rec := doMaintenanceRequest(router, "/admin/login.html?maint_key=secret123", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /admin/login.html?maint_key=secret123 status = %d, want 200", rec.Code)
	}
	if setCookie := rec.Header().Get("Set-Cookie"); !strings.Contains(setCookie, "maint_key=secret123") {
		t.Fatalf("bypass response missing maint_key cookie: %q", setCookie)
	}

	// 错误 key 仍然拦截
	if rec := doMaintenanceRequest(router, "/admin/login.html?maint_key=wrong", ""); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("wrong maint_key status = %d, want 503", rec.Code)
	}

	// cookie 旁路（login.html 登录后跳转 index.html 不再带查询参数）
	if rec := doMaintenanceRequest(router, "/admin/index.html", "secret123"); rec.Code != http.StatusOK {
		t.Fatalf("cookie bypass status = %d, want 200", rec.Code)
	}
	if rec := doMaintenanceRequest(router, "/admin/index.html", "wrong"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("wrong cookie status = %d, want 503", rec.Code)
	}
}

func TestMaintenanceGuardNoBypassWhenKeyEmpty(t *testing.T) {
	setupMaintenanceTestDB(t)
	setMaintenanceConfig(t, "true", "")
	router := newMaintenanceRouter()

	// key 未配置时任何 maint_key 都不能旁路
	if rec := doMaintenanceRequest(router, "/admin/index.html?maint_key=anything", ""); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 when bypass key not configured", rec.Code)
	}
	if rec := doMaintenanceRequest(router, "/admin/index.html?maint_key=", ""); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 for empty maint_key", rec.Code)
	}
}
