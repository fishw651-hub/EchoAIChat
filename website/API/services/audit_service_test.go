package services

import (
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

// 回归测试：List 曾把 FindAll(dest, where, order, offset, limit) 的
// offset/limit 传反，第 1 页 limit=0 会返回整表剩余数据。
func TestAuditListPagination(t *testing.T) {
	initReservationTestDatabase(t)

	tbl := database.Get().Register("AuditLog")
	for i := 0; i < 25; i++ {
		if err := tbl.Insert(&models.AuditLog{
			AdminID:    1,
			AdminName:  "admin",
			Action:     string(AuditActionLogin),
			TargetType: string(AuditTargetSystem),
		}); err != nil {
			t.Fatalf("insert audit log: %v", err)
		}
	}

	svc := &AuditService{}

	page1, total, err := svc.List(1, 10, nil, nil, nil, nil)
	if err != nil {
		t.Fatalf("list page 1: %v", err)
	}
	if total != 25 {
		t.Fatalf("total = %d, want 25", total)
	}
	if len(page1) != 10 {
		t.Fatalf("page 1 size = %d, want 10", len(page1))
	}

	page2, _, err := svc.List(2, 10, nil, nil, nil, nil)
	if err != nil {
		t.Fatalf("list page 2: %v", err)
	}
	if len(page2) != 10 {
		t.Fatalf("page 2 size = %d, want 10", len(page2))
	}

	page3, _, err := svc.List(3, 10, nil, nil, nil, nil)
	if err != nil {
		t.Fatalf("list page 3: %v", err)
	}
	if len(page3) != 5 {
		t.Fatalf("page 3 size = %d, want 5", len(page3))
	}

	// 三页之间不允许出现重复记录。
	seen := make(map[uint]bool)
	for _, page := range [][]models.AuditLog{page1, page2, page3} {
		for _, log := range page {
			if seen[log.ID] {
				t.Fatalf("audit log %d appears on multiple pages", log.ID)
			}
			seen[log.ID] = true
		}
	}
	if len(seen) != 25 {
		t.Fatalf("distinct logs across pages = %d, want 25", len(seen))
	}

	// 按 ID desc 排序：第 1 页首条应是最大 ID。
	if page1[0].ID <= page1[len(page1)-1].ID {
		t.Fatalf("page 1 not ordered by ID desc: first=%d last=%d", page1[0].ID, page1[len(page1)-1].ID)
	}
}
