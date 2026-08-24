package services

import (
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

func TestDeviceBanDaysForCountEscalates(t *testing.T) {
	cases := []struct {
		count int
		want  int
	}{
		{0, 0}, {1, 1}, {2, 2}, {3, 4}, {4, 8}, {10, 365}, {100, 365},
	}
	for _, c := range cases {
		if got := DeviceBanDaysForCount(c.count); got != c.want {
			t.Fatalf("DeviceBanDaysForCount(%d) = %d, want %d", c.count, got, c.want)
		}
	}
}

func TestRecordDeviceLoginBansAfterThreeAccounts(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	// 两个不同账号：不封禁
	for _, uid := range []uint{1, 2} {
		banned, _, _ := RecordDeviceLogin("dev-1", uid)
		if banned {
			t.Fatalf("uid %d: unexpected ban", uid)
		}
	}
	// 第三个不同账号：触发封禁，首次 1 天
	banned, until, days := RecordDeviceLogin("dev-1", 3)
	if !banned {
		t.Fatal("expected ban on 3rd distinct account")
	}
	if days != 1 {
		t.Fatalf("first ban days = %d, want 1", days)
	}
	if !until.After(time.Now()) {
		t.Fatal("ban_until should be in the future")
	}

	// 封禁状态可查询
	banned, _, days = CheckDeviceBan("dev-1")
	if !banned || days != 1 {
		t.Fatalf("CheckDeviceBan = (%v, %d), want (true, 1)", banned, days)
	}

	// 封禁后记录已清空：同窗口内再次切换 3 个账号 → 第二次封禁 2 天
	RecordDeviceLogin("dev-1", 4)
	RecordDeviceLogin("dev-1", 5)
	banned, _, days = RecordDeviceLogin("dev-1", 6)
	if !banned || days != 2 {
		t.Fatalf("second ban = (%v, %d), want (true, 2)", banned, days)
	}
}

func TestRecordDeviceLoginSkipsSubscribedUsers(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	// 用户 9 有激活订阅
	tomorrow := time.Now().AddDate(0, 0, 1).Format("2006-01-02")
	if err := database.Get().Register("UserSubscription").Insert(&models.UserSubscription{
		UserID:    9,
		Status:    1,
		ExpiresAt: tomorrow,
	}); err != nil {
		t.Fatalf("insert subscription: %v", err)
	}

	// 订阅账号登录不计入
	banned, _, _ := RecordDeviceLogin("dev-2", 9)
	if banned {
		t.Fatal("subscribed user should be exempt")
	}
	// 窗口内只有两个非订阅账号 + 订阅账号 → 不封禁
	RecordDeviceLogin("dev-2", 10)
	banned, _, _ = RecordDeviceLogin("dev-2", 11)
	if banned {
		t.Fatal("expected no ban: subscribed account must not count")
	}
}

func TestCheckDeviceBanExpires(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	// 手动写入一个已过期的封禁记录
	if err := database.Get().Register("DeviceBan").Insert(&models.DeviceBan{
		DeviceID: "dev-3",
		BanUntil: time.Now().Add(-time.Hour),
		BanCount: 2,
	}); err != nil {
		t.Fatalf("insert ban: %v", err)
	}

	banned, _, _ := CheckDeviceBan("dev-3")
	if banned {
		t.Fatal("expired ban should auto-clear")
	}
}
