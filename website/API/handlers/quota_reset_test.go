package handlers

import (
	"testing"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

func TestQuotaResetIfNewDayResetsFreeUserCounters(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	user := models.User{
		Username:           "quota-reset-user",
		PasswordHash:       "x",
		Status:             1,
		OcrUsedToday:       3,
		RealReplyUsedToday: 30,
		QuotaResetDate:     "2020-01-01", // 过期日期，应被重置为今日
	}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}

	h := &QuotaHandler{}
	h.resetIfNewDay(&user)

	if user.OcrUsedToday != 0 || user.RealReplyUsedToday != 0 {
		t.Fatalf("counters not zeroed: ocr=%d real=%d",
			user.OcrUsedToday, user.RealReplyUsedToday)
	}
	if user.QuotaResetDate != utils.TodayCN() {
		t.Fatalf("QuotaResetDate = %q, want %q", user.QuotaResetDate, utils.TodayCN())
	}

	// 持久化验证：重新读取应为已重置值
	var after models.User
	if !database.Get().Register("User").FindByID(user.ID, &after) {
		t.Fatal("user not found after reset")
	}
	if after.OcrUsedToday != 0 || after.RealReplyUsedToday != 0 {
		t.Fatalf("persisted counters not zeroed: ocr=%d real=%d",
			after.OcrUsedToday, after.RealReplyUsedToday)
	}
	if after.QuotaResetDate != utils.TodayCN() {
		t.Fatalf("persisted QuotaResetDate = %q, want %q",
			after.QuotaResetDate, utils.TodayCN())
	}
}
