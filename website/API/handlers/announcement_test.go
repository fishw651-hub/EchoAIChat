package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func setupAnnouncementRouter(t *testing.T) *gin.Engine {
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

	router := gin.New()
	h := &AnnouncementHandler{}
	router.GET("/ann", h.AdminList)
	router.POST("/ann", h.Create)
	router.PUT("/ann/:id", h.Update)
	router.DELETE("/ann/:id", h.Delete)
	router.GET("/ann-active", h.ListActive)
	return router
}

func doAnnouncementRequest(t *testing.T, router *gin.Engine, method, path, body string) utils.Response {
	t.Helper()
	var req *http.Request
	if body != "" {
		req = httptest.NewRequest(method, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
	} else {
		req = httptest.NewRequest(method, path, nil)
	}
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)
	var resp utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response: %v (body=%s)", err, recorder.Body.String())
	}
	return resp
}

func announcementTimeRange() (string, string) {
	now := time.Now()
	return now.Add(-time.Hour).UTC().Format(time.RFC3339),
		now.Add(time.Hour).UTC().Format(time.RFC3339)
}

func TestAnnouncementCreateValidation(t *testing.T) {
	router := setupAnnouncementRouter(t)
	start, end := announcementTimeRange()
	valid := func() string {
		return fmt.Sprintf(`{"title":"标题","content":"内容","frequency":"once","audience":"all","start_at":%q,"end_at":%q}`, start, end)
	}

	cases := []struct {
		name string
		body string
	}{
		{"缺标题", fmt.Sprintf(`{"content":"c","frequency":"once","audience":"all","start_at":%q,"end_at":%q}`, start, end)},
		{"非法频率", fmt.Sprintf(`{"title":"t","content":"c","frequency":"hourly","audience":"all","start_at":%q,"end_at":%q}`, start, end)},
		{"非法目标", fmt.Sprintf(`{"title":"t","content":"c","frequency":"once","audience":"admins","start_at":%q,"end_at":%q}`, start, end)},
		{"截止早于生效", fmt.Sprintf(`{"title":"t","content":"c","frequency":"once","audience":"all","start_at":%q,"end_at":%q}`, end, start)},
		{"空生效时间", fmt.Sprintf(`{"title":"t","content":"c","frequency":"once","audience":"all","start_at":"","end_at":%q}`, end)},
		{"超长内容", fmt.Sprintf(`{"title":"t","content":%q,"frequency":"once","audience":"all","start_at":%q,"end_at":%q}`, strings.Repeat("a", services.AnnouncementMaxContentBytes+1), start, end)},
		{"非法JSON", `{"title":`},
	}
	for _, tc := range cases {
		resp := doAnnouncementRequest(t, router, http.MethodPost, "/ann", tc.body)
		if resp.Code != utils.CodeBadRequest {
			t.Fatalf("%s: code = %d, want %d", tc.name, resp.Code, utils.CodeBadRequest)
		}
	}

	// 合法创建成功，默认启用
	resp := doAnnouncementRequest(t, router, http.MethodPost, "/ann", valid())
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("valid create: code = %d msg = %s", resp.Code, resp.Message)
	}
	var created struct {
		ID      uint `json:"id"`
		Enabled bool `json:"enabled"`
	}
	raw, _ := json.Marshal(resp.Data)
	if err := json.Unmarshal(raw, &created); err != nil {
		t.Fatal(err)
	}
	if created.ID == 0 || !created.Enabled {
		t.Fatalf("created = %+v, want ID assigned and enabled by default", created)
	}

	// 管理端列表返回 1 条
	resp = doAnnouncementRequest(t, router, http.MethodGet, "/ann", "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("admin list: code = %d", resp.Code)
	}
	var list []models.Announcement
	raw, _ = json.Marshal(resp.Data)
	if err := json.Unmarshal(raw, &list); err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].Title != "标题" {
		t.Fatalf("admin list = %+v", list)
	}
}

func TestAnnouncementUpdateAndDelete(t *testing.T) {
	router := setupAnnouncementRouter(t)
	start, end := announcementTimeRange()

	// 更新不存在的公告 → 404
	resp := doAnnouncementRequest(t, router, http.MethodPut, "/ann/999",
		fmt.Sprintf(`{"title":"t","content":"c","frequency":"once","audience":"all","start_at":%q,"end_at":%q}`, start, end))
	if resp.Code != utils.CodeNotFound {
		t.Fatalf("update missing: code = %d, want %d", resp.Code, utils.CodeNotFound)
	}

	// 创建后更新（停用 + 校验仍生效）
	a := &models.Announcement{
		Title: "旧", Content: "c", Frequency: "once", Audience: "all",
		StartAt: start, EndAt: end, Enabled: true,
	}
	if err := services.CreateAnnouncement(a); err != nil {
		t.Fatal(err)
	}
	resp = doAnnouncementRequest(t, router, http.MethodPut, fmt.Sprintf("/ann/%d", a.ID),
		fmt.Sprintf(`{"title":"新","content":"cc","frequency":"daily","audience":"subscriber","start_at":%q,"end_at":%q,"enabled":false}`, start, end))
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("update: code = %d msg = %s", resp.Code, resp.Message)
	}
	got, _ := services.GetAnnouncement(a.ID)
	if got.Title != "新" || got.Enabled || got.Frequency != "daily" || got.Audience != "subscriber" {
		t.Fatalf("after update = %+v", got)
	}

	// 更新时校验仍生效（时间先后）
	resp = doAnnouncementRequest(t, router, http.MethodPut, fmt.Sprintf("/ann/%d", a.ID),
		fmt.Sprintf(`{"title":"新","content":"cc","frequency":"daily","audience":"subscriber","start_at":%q,"end_at":%q}`, end, start))
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("update invalid time: code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// 删除
	resp = doAnnouncementRequest(t, router, http.MethodDelete, fmt.Sprintf("/ann/%d", a.ID), "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("delete: code = %d", resp.Code)
	}
	if _, ok := services.GetAnnouncement(a.ID); ok {
		t.Fatal("announcement should be deleted")
	}
}

func TestAnnouncementListActiveOnlyReturnsActive(t *testing.T) {
	router := setupAnnouncementRouter(t)

	now := time.Now()
	mk := func(title string, enabled bool, start, end time.Time) {
		if err := services.CreateAnnouncement(&models.Announcement{
			Title: title, Content: "内容", Frequency: "once", Audience: "all",
			StartAt: start.UTC().Format(time.RFC3339), EndAt: end.UTC().Format(time.RFC3339), Enabled: enabled,
		}); err != nil {
			t.Fatal(err)
		}
	}
	mk("生效中", true, now.Add(-time.Hour), now.Add(time.Hour))
	mk("已停用", false, now.Add(-time.Hour), now.Add(time.Hour))
	mk("未到生效期", true, now.Add(time.Hour), now.Add(2*time.Hour))
	mk("已过期", true, now.Add(-2*time.Hour), now.Add(-time.Hour))

	resp := doAnnouncementRequest(t, router, http.MethodGet, "/ann-active", "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("active: code = %d", resp.Code)
	}
	var list []struct {
		ID        uint   `json:"id"`
		Title     string `json:"title"`
		Content   string `json:"content"`
		Frequency string `json:"frequency"`
		Audience  string `json:"audience"`
		StartAt   string `json:"start_at"`
		EndAt     string `json:"end_at"`
		UpdatedAt string `json:"updated_at"`
	}
	raw, _ := json.Marshal(resp.Data)
	if err := json.Unmarshal(raw, &list); err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].Title != "生效中" {
		t.Fatalf("active list = %+v, want only 生效中", list)
	}
	// 契约字段齐全
	item := list[0]
	if item.ID == 0 || item.Content == "" || item.Frequency != "once" || item.Audience != "all" ||
		item.StartAt == "" || item.EndAt == "" || item.UpdatedAt == "" {
		t.Fatalf("active item missing contract fields: %+v", item)
	}
}
