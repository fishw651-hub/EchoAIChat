package database

import (
	"testing"
)

// 下推 SQL 与内存过滤必须返回一致的结果集（覆盖 string/int/float64/uint/bool/实体列）。
func TestFilterPushdownParity(t *testing.T) {
	if err := Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := Get().Register("ParityUser")
	seed := []map[string]interface{}{
		{"Username": "alice", "Age": float64(30), "Score": float64(9.5), "Active": true, "UserID": float64(1)},
		{"Username": "bob", "Age": float64(25), "Score": float64(7.0), "Active": false, "UserID": float64(1)},
		{"Username": "carol", "Age": float64(100), "Score": float64(9.5), "Active": true, "UserID": float64(2)},
		{"Username": "10", "Age": float64(10), "Score": float64(0), "Active": false, "UserID": float64(2)},
	}
	for _, row := range seed {
		if err := tbl.InsertMap(row); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}

	cases := []struct {
		name  string
		where Filter
		want  int
	}{
		{"字符串等值", FilterEq("Username", "alice"), 1},
		{"数字等值 float64", FilterEq("Age", float64(25)), 1},
		{"数字等值 int", FilterEq("Age", 100), 1},
		{"数字等值 uint", FilterEq("Age", uint(10)), 1},
		{"字符串匹配数字文本", FilterEq("Username", "10"), 1},
		{"bool true", FilterEq("Active", true), 2},
		{"bool false", FilterEq("Active", false), 2},
		{"实体列 UserID", FilterEq("UserID", uint(1)), 2},
		{"实体列 UserID int64", FilterEq("UserID", int64(2)), 2},
		{"无匹配", FilterEq("Username", "nobody"), 0},
		{"And 组合", FilterAnd(FilterEq("Active", true), FilterEq("Score", 9.5)), 2},
		{"Or 组合", FilterOr(FilterEq("Username", "alice"), FilterEq("Username", "bob")), 2},
		{"And 嵌套 Or", FilterAnd(FilterEq("UserID", 1), FilterOr(FilterEq("Username", "alice"), FilterEq("Username", "bob"))), 2},
		{"FilterAll", FilterAll(FilterEq("Active", true), FilterEq("UserID", 2)), 1},
		{"不可下推回退（Like）", FilterLike("Username", "ali"), 1},
		{"混合 And（可下推+不可下推）回退", FilterAnd(FilterEq("Active", true), FilterLike("Username", "caro")), 1},
	}

	for _, tc := range cases {
		// 下推路径（rows 内部自动选择）
		var pushed []map[string]interface{}
		tbl.FindAll(&pushed, tc.where, "", 0, 0)
		if len(pushed) != tc.want {
			t.Errorf("%s: 下推/实际路径命中 %d 行, want %d", tc.name, len(pushed), tc.want)
			continue
		}
		// 强制内存过滤路径（funcFilter 不下推），与 Match 语义对照
		mem := FilterFunc(func(row map[string]interface{}) bool { return tc.where.Match(row) })
		var inMemory []map[string]interface{}
		tbl.FindAll(&inMemory, mem, "", 0, 0)
		if len(inMemory) != len(pushed) {
			t.Errorf("%s: 内存过滤 %d 行 != 下推 %d 行", tc.name, len(inMemory), len(pushed))
		}
	}
}

// 下推路径的 UpdateWhere 只更新匹配行。
func TestUpdateWherePushdownOnlyTouchesMatches(t *testing.T) {
	if err := Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := Get(); db != nil {
			_ = db.Close()
		}
	})

	tbl := Get().Register("ParityUpdate")
	if err := tbl.InsertMap(map[string]interface{}{"Name": "a", "Flag": float64(1)}); err != nil {
		t.Fatal(err)
	}
	if err := tbl.InsertMap(map[string]interface{}{"Name": "b", "Flag": float64(1)}); err != nil {
		t.Fatal(err)
	}

	if err := tbl.UpdateWhere(FilterEq("Name", "a"), map[string]interface{}{"Flag": float64(0)}); err != nil {
		t.Fatalf("update: %v", err)
	}

	var all []map[string]interface{}
	tbl.FindAll(&all, nil, "ID asc", 0, 0)
	if len(all) != 2 {
		t.Fatalf("rows = %d, want 2", len(all))
	}
	if got := all[0]["Flag"]; got != float64(0) {
		t.Errorf("匹配行 Flag = %v, want 0", got)
	}
	if got := all[1]["Flag"]; got != float64(1) {
		t.Errorf("未匹配行 Flag = %v, want 1（不应被更新）", got)
	}
}
