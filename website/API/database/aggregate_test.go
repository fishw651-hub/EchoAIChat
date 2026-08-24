package database

import (
	"strings"
	"testing"
)

// FindByIDE/FindOneE 必须区分"记录不存在"与"DB 错误"，旧接口行为保持兼容。
func TestFindErrorSemantics(t *testing.T) {
	if err := Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := Get().Register("ErrSemUser")
	if err := tbl.InsertMap(map[string]interface{}{"Username": "alice"}); err != nil {
		t.Fatalf("insert: %v", err)
	}

	type user struct {
		ID       uint
		Username string
	}

	var existing user
	found, err := tbl.FindByIDE(1, &existing)
	if err != nil || !found {
		t.Fatalf("FindByIDE(1) = (%v, %v), want (true, nil)", found, err)
	}
	if existing.Username != "alice" {
		t.Fatalf("username = %q, want alice", existing.Username)
	}

	var missing user
	found, err = tbl.FindByIDE(999, &missing)
	if err != nil || found {
		t.Fatalf("FindByIDE(999) = (%v, %v), want (false, nil)", found, err)
	}

	found, err = tbl.FindOneE(FilterEq("Username", "alice"), &missing)
	if err != nil || !found {
		t.Fatalf("FindOneE(alice) = (%v, %v), want (true, nil)", found, err)
	}
	found, err = tbl.FindOneE(FilterEq("Username", "nobody"), &missing)
	if err != nil || found {
		t.Fatalf("FindOneE(nobody) = (%v, %v), want (false, nil)", found, err)
	}

	// 关闭底层连接模拟 DB 故障：新接口必须报错，旧接口保持吞错兼容
	// （直接关 *sql.DB 而不是 db.Close()——后者会把 db.sql 置 nil）
	db := Get()
	if err := db.SQL().Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	found, err = tbl.FindByIDE(1, &existing)
	if err == nil || found {
		t.Fatalf("FindByIDE on closed db = (%v, %v), want (false, error)", found, err)
	}
	if !strings.Contains(err.Error(), "closed") {
		t.Fatalf("FindByIDE error = %v, want closed-db error", err)
	}
	if _, err = tbl.FindOneE(FilterEq("Username", "alice"), &existing); err == nil {
		t.Fatal("FindOneE on closed db must return error")
	}
	if tbl.FindByID(1, &existing) {
		t.Fatal("FindByID on closed db must keep returning false (compat)")
	}
	if tbl.FindOne(FilterEq("Username", "alice"), &existing) {
		t.Fatal("FindOne on closed db must keep returning false (compat)")
	}
}

// CountWhere/SumWhere 的下推 SQL 结果必须与内存回退路径一致。
func TestAggregatePushdownParity(t *testing.T) {
	if err := Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := Get().Register("AggUsage")
	seed := []map[string]interface{}{
		{"Cost": float64(1.5), "Status": "pending", "CreatedAt": "2026-08-16T01:00:00Z"},
		{"Cost": float64(2.25), "Status": "paid", "CreatedAt": "2026-08-16T02:00:00Z"},
		{"Cost": float64(0.5), "Status": "pending", "CreatedAt": "2026-08-15T23:00:00Z"},
	}
	for _, row := range seed {
		if err := tbl.InsertMap(row); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}

	countCases := []struct {
		name  string
		where Filter
		want  int64
	}{
		{"全量", nil, 3},
		{"实体列等值下推", FilterEq("Status", "pending"), 2},
		{"日期前缀下推", FilterDate("CreatedAt", "2026-08-16"), 2},
		{"无匹配", FilterEq("Status", "refunded"), 0},
		{"不可下推回退（Like）", FilterLike("Status", "pend"), 2},
	}
	for _, tc := range countCases {
		got, err := tbl.CountWhere(tc.where)
		if err != nil {
			t.Errorf("%s: CountWhere err = %v", tc.name, err)
			continue
		}
		if got != tc.want {
			t.Errorf("%s: CountWhere = %d, want %d", tc.name, got, tc.want)
		}
		// 与旧 Count 的结果保持一致
		if legacy := tbl.Count(tc.where); legacy != got {
			t.Errorf("%s: CountWhere = %d != Count = %d", tc.name, got, legacy)
		}
	}

	sumCases := []struct {
		name  string
		where Filter
		want  float64
	}{
		{"全量求和", nil, 4.25},
		{"条件下推求和", FilterEq("Status", "pending"), 2.0},
		{"日期前缀求和", FilterDate("CreatedAt", "2026-08-16"), 3.75},
		{"空集求和为 0", FilterEq("Status", "refunded"), 0},
		{"不可下推回退求和", FilterLike("Status", "pend"), 2.0},
	}
	for _, tc := range sumCases {
		got, err := tbl.SumWhere("Cost", tc.where)
		if err != nil {
			t.Errorf("%s: SumWhere err = %v", tc.name, err)
			continue
		}
		if got != tc.want {
			t.Errorf("%s: SumWhere = %v, want %v", tc.name, got, tc.want)
		}
	}

	// DB 故障必须显式报错
	db := Get()
	if err := db.SQL().Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if _, err := tbl.CountWhere(nil); err == nil {
		t.Fatal("CountWhere on closed db must return error")
	}
	if _, err := tbl.SumWhere("Cost", nil); err == nil {
		t.Fatal("SumWhere on closed db must return error")
	}
}
