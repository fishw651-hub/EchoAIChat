package services

import (
	"strings"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

func setupAnnouncementTestDB(t *testing.T) {
	t.Helper()
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}

func rfc3339(t time.Time) string {
	return t.UTC().Format(time.RFC3339)
}

func TestValidateAnnouncement(t *testing.T) {
	now := time.Now()
	start := rfc3339(now)
	end := rfc3339(now.Add(time.Hour))

	// 合法输入通过
	if _, _, err := ValidateAnnouncement("标题", "内容", "once", "all", start, end); err != nil {
		t.Fatalf("valid input rejected: %v", err)
	}
	// 频率/目标全部白名单取值通过
	for _, f := range []string{"once", "daily", "always"} {
		for _, a := range []string{"all", "subscriber", "free"} {
			if _, _, err := ValidateAnnouncement("t", "c", f, a, start, end); err != nil {
				t.Fatalf("whitelist %s/%s rejected: %v", f, a, err)
			}
		}
	}

	cases := []struct {
		name                                      string
		title, content, frequency, audience, s, e string
	}{
		{"空标题", "", "c", "once", "all", start, end},
		{"空白标题", "   ", "c", "once", "all", start, end},
		{"空内容", "t", "", "once", "all", start, end},
		{"超长内容", "t", strings.Repeat("a", AnnouncementMaxContentBytes+1), "once", "all", start, end},
		{"非法频率", "t", "c", "hourly", "all", start, end},
		{"非法目标", "t", "c", "once", "admins", start, end},
		{"空生效时间", "t", "c", "once", "all", "", end},
		{"空截止时间", "t", "c", "once", "all", start, ""},
		{"生效时间格式错", "t", "c", "once", "all", "2026-08-09 05:00", end},
		{"截止时间格式错", "t", "c", "once", "all", start, "not-a-time"},
		{"截止早于生效", "t", "c", "once", "all", end, start},
		{"截止等于生效", "t", "c", "once", "all", start, start},
	}
	for _, tc := range cases {
		if _, _, err := ValidateAnnouncement(tc.title, tc.content, tc.frequency, tc.audience, tc.s, tc.e); err == nil {
			t.Fatalf("%s: expected error, got nil", tc.name)
		}
	}

	// 恰好 50KB 的内容允许通过
	if _, _, err := ValidateAnnouncement("t", strings.Repeat("a", AnnouncementMaxContentBytes), "once", "all", start, end); err != nil {
		t.Fatalf("exactly 50KB content rejected: %v", err)
	}
}

func TestAnnouncementCRUD(t *testing.T) {
	setupAnnouncementTestDB(t)

	now := time.Now()
	a1 := &models.Announcement{
		Title: "第一条", Content: "# hello", Frequency: "once", Audience: "all",
		StartAt: rfc3339(now.Add(-time.Hour)), EndAt: rfc3339(now.Add(time.Hour)), Enabled: true,
	}
	a2 := &models.Announcement{
		Title: "第二条", Content: "world", Frequency: "daily", Audience: "subscriber",
		StartAt: rfc3339(now.Add(-time.Hour)), EndAt: rfc3339(now.Add(time.Hour)), Enabled: false,
	}
	if err := CreateAnnouncement(a1); err != nil {
		t.Fatalf("create a1: %v", err)
	}
	if err := CreateAnnouncement(a2); err != nil {
		t.Fatalf("create a2: %v", err)
	}
	if a1.ID == 0 || a2.ID == 0 || a1.ID == a2.ID {
		t.Fatalf("IDs not assigned: a1=%d a2=%d", a1.ID, a2.ID)
	}

	// 列表按 ID 倒序（新公告在前）
	list := ListAnnouncements()
	if len(list) != 2 || list[0].ID != a2.ID || list[1].ID != a1.ID {
		t.Fatalf("ListAnnouncements order wrong: %+v", list)
	}

	// 按 ID 查询
	got, ok := GetAnnouncement(a1.ID)
	if !ok || got.Title != "第一条" || got.Frequency != "once" || !got.Enabled {
		t.Fatalf("GetAnnouncement = %+v, ok=%v", got, ok)
	}

	// 全量更新（含停用）
	a1.Title = "第一条（改）"
	a1.Enabled = false
	a1.Audience = "free"
	if err := UpdateAnnouncement(a1); err != nil {
		t.Fatalf("update: %v", err)
	}
	got, ok = GetAnnouncement(a1.ID)
	if !ok || got.Title != "第一条（改）" || got.Enabled || got.Audience != "free" {
		t.Fatalf("after update = %+v, ok=%v", got, ok)
	}

	// 删除
	if !DeleteAnnouncement(a2.ID) {
		t.Fatal("DeleteAnnouncement returned false")
	}
	if _, ok := GetAnnouncement(a2.ID); ok {
		t.Fatal("a2 should be deleted")
	}
	if list := ListAnnouncements(); len(list) != 1 {
		t.Fatalf("list after delete len = %d, want 1", len(list))
	}
}

func TestListActiveAnnouncementsFilters(t *testing.T) {
	setupAnnouncementTestDB(t)

	now := time.Now()
	mk := func(title string, enabled bool, start, end time.Time) *models.Announcement {
		a := &models.Announcement{
			Title: title, Content: "c", Frequency: "always", Audience: "all",
			StartAt: rfc3339(start), EndAt: rfc3339(end), Enabled: enabled,
		}
		if err := CreateAnnouncement(a); err != nil {
			t.Fatalf("create %s: %v", title, err)
		}
		return a
	}

	active := mk("生效中", true, now.Add(-time.Hour), now.Add(time.Hour))
	mk("已停用", false, now.Add(-time.Hour), now.Add(time.Hour))
	mk("未到生效期", true, now.Add(time.Hour), now.Add(2*time.Hour))
	mk("已过期", true, now.Add(-2*time.Hour), now.Add(-time.Hour))

	// 时间字段无法解析的记录直接写入 DB（绕过校验），应被跳过
	if err := CreateAnnouncement(&models.Announcement{
		Title: "坏时间", Content: "c", Frequency: "always", Audience: "all",
		StartAt: "bad", EndAt: "bad", Enabled: true,
	}); err != nil {
		t.Fatalf("create 坏时间: %v", err)
	}

	got := ListActiveAnnouncements(now)
	if len(got) != 1 || got[0].ID != active.ID {
		t.Fatalf("ListActive = %+v, want only 生效中(ID=%d)", got, active.ID)
	}

	// 边界：now == StartAt / now == EndAt 都算生效（存储时间按 RFC3339 整秒截断，用解析后的时间判定）
	start, _ := time.Parse(time.RFC3339, active.StartAt)
	end, _ := time.Parse(time.RFC3339, active.EndAt)
	contains := func(list []models.Announcement, id uint) bool {
		for _, a := range list {
			if a.ID == id {
				return true
			}
		}
		return false
	}
	if got := ListActiveAnnouncements(start); !contains(got, active.ID) {
		t.Fatal("at StartAt boundary, 生效中 should be active")
	}
	if got := ListActiveAnnouncements(end); !contains(got, active.ID) {
		t.Fatal("at EndAt boundary, 生效中 should be active")
	}
	if got := ListActiveAnnouncements(start.Add(-time.Second)); contains(got, active.ID) {
		t.Fatal("before StartAt, 生效中 should be inactive")
	}
	if got := ListActiveAnnouncements(end.Add(time.Second)); contains(got, active.ID) {
		t.Fatal("after EndAt, 生效中 should be inactive")
	}
	// 远超所有记录窗口的时间点：无生效公告
	if got := ListActiveAnnouncements(now.Add(24 * time.Hour)); len(got) != 0 {
		t.Fatalf("far after all windows, ListActive len = %d, want 0", len(got))
	}
}
