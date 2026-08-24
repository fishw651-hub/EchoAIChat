package database

import "testing"

// 数值字段必须按数值排序：纯字符串比较会让 "10" < "9"，
// version_code 到达三位数时更新检查会把旧版错当最新版下发。
func TestSortRowsNumericOrdering(t *testing.T) {
	rows := []map[string]interface{}{
		{"VersionCode": float64(9)},
		{"VersionCode": float64(100)},
		{"VersionCode": float64(65)},
	}
	sortRows(rows, "VersionCode desc")
	got := []float64{rows[0]["VersionCode"].(float64), rows[1]["VersionCode"].(float64), rows[2]["VersionCode"].(float64)}
	want := []float64{100, 65, 9}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("desc 数值排序错误: got %v want %v", got, want)
		}
	}

	sortRows(rows, "VersionCode asc")
	if rows[0]["VersionCode"].(float64) != 9 || rows[2]["VersionCode"].(float64) != 100 {
		t.Fatalf("asc 数值排序错误: %v", rows)
	}
}

// 字符串字段保持字典序行为不变；混合类型（一侧非数值）回退字符串比较。
func TestSortRowsStringFallback(t *testing.T) {
	rows := []map[string]interface{}{
		{"Name": "banana"},
		{"Name": "apple"},
		{"Name": "cherry"},
	}
	sortRows(rows, "Name asc")
	if rows[0]["Name"] != "apple" || rows[2]["Name"] != "cherry" {
		t.Fatalf("字符串排序行为改变: %v", rows)
	}

	mixed := []map[string]interface{}{
		{"Val": "abc"},
		{"Val": float64(10)},
	}
	// 不 panic 即可，一侧非数值回退字符串比较
	sortRows(mixed, "Val desc")
}
