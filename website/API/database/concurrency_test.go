package database

import (
	"fmt"
	"sync"
	"testing"
)

// 并发正确性：验证写锁纪律下并发写/RMW 不丢数据、nextID 序列无重复。
// 需配合 -race 运行。

type counterRow struct {
	ID     uint
	UserID uint
	Value  float64
	Status string
}

func setupConcurrencyTable(t *testing.T) *Table {
	t.Helper()
	dir := t.TempDir()
	if err := Init(dir); err != nil {
		t.Fatalf("初始化数据库: %v", err)
	}
	db := Get()
	t.Cleanup(func() { _ = db.Close() })
	return db.Register("CounterRow")
}

// TestConcurrentInsertUniqueIDs 并发 Insert：所有行落库且 ID 全局唯一（无重复序列）。
func TestConcurrentInsertUniqueIDs(t *testing.T) {
	table := setupConcurrencyTable(t)

	const goroutines = 8
	const perGoroutine = 50
	ids := make(chan uint, goroutines*perGoroutine)
	var wg sync.WaitGroup
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			for i := 0; i < perGoroutine; i++ {
				row := &counterRow{UserID: uint(g + 1), Value: float64(i), Status: "active"}
				if err := table.Insert(row); err != nil {
					t.Errorf("Insert: %v", err)
					return
				}
				ids <- row.ID
			}
		}(g)
	}
	wg.Wait()
	close(ids)

	seen := make(map[uint]struct{})
	count := 0
	for id := range ids {
		if id == 0 {
			t.Fatal("Insert 未回写 ID")
		}
		if _, dup := seen[id]; dup {
			t.Fatalf("nextID 产生重复 ID: %d", id)
		}
		seen[id] = struct{}{}
		count++
	}
	if count != goroutines*perGoroutine {
		t.Fatalf("插入行数 = %d, 期望 %d（存在丢失）", count, goroutines*perGoroutine)
	}
	if got := table.Count(nil); got != int64(goroutines*perGoroutine) {
		t.Fatalf("库内行数 = %d, 期望 %d", got, goroutines*perGoroutine)
	}
}

// TestConcurrentIncrementNoLostUpdate 并发 RMW（IncrementField 走 updateRows 事务）：
// 最终值必须等于全部增量之和，否则说明读-改-写丢更新。
func TestConcurrentIncrementNoLostUpdate(t *testing.T) {
	table := setupConcurrencyTable(t)

	row := &counterRow{UserID: 1, Status: "active"}
	if err := table.Insert(row); err != nil {
		t.Fatalf("Insert: %v", err)
	}

	const goroutines = 16
	const perGoroutine = 25
	var wg sync.WaitGroup
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perGoroutine; i++ {
				if err := table.IncrementField(FilterEq("ID", row.ID), "Value", 1); err != nil {
					t.Errorf("IncrementField: %v", err)
					return
				}
			}
		}()
	}
	wg.Wait()

	var final counterRow
	if !table.FindByID(row.ID, &final) {
		t.Fatal("计数行未找到")
	}
	if want := float64(goroutines * perGoroutine); final.Value != want {
		t.Fatalf("最终值 = %v, 期望 %v（丢更新）", final.Value, want)
	}
}

// TestConcurrentConditionalUpdateSingleWinner 并发条件更新（Status=pending 才翻转到 done）：
// 恰好一个赢家，模拟支付回调/并发激活的原子状态转换语义。
func TestConcurrentConditionalUpdateSingleWinner(t *testing.T) {
	table := setupConcurrencyTable(t)

	row := &counterRow{UserID: 1, Status: "pending"}
	if err := table.Insert(row); err != nil {
		t.Fatalf("Insert: %v", err)
	}

	const goroutines = 16
	var winners int64
	var mu sync.Mutex
	var wg sync.WaitGroup
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			affected, err := table.UpdateWhereCount(
				FilterAll(FilterEq("ID", row.ID), FilterEq("Status", "pending")),
				map[string]interface{}{"Status": "done"},
			)
			if err != nil {
				t.Errorf("UpdateWhereCount: %v", err)
				return
			}
			if affected > 0 {
				mu.Lock()
				winners += int64(affected)
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	if winners != 1 {
		t.Fatalf("条件更新赢家数 = %d, 期望恰好 1", winners)
	}
	var final counterRow
	if !table.FindByID(row.ID, &final) || final.Status != "done" {
		t.Fatalf("最终状态 = %q, 期望 done", final.Status)
	}
}

// TestConcurrentInsertMapAndBatch 并发 InsertMap / BatchInsertMaps 混合写入不丢行。
func TestConcurrentInsertMapAndBatch(t *testing.T) {
	table := setupConcurrencyTable(t)

	const goroutines = 8
	const perGoroutine = 20
	var wg sync.WaitGroup
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			for i := 0; i < perGoroutine; i++ {
				if i%2 == 0 {
					if err := table.InsertMap(map[string]interface{}{
						"UserID": g + 1, "Value": float64(i), "Status": "active",
					}); err != nil {
						t.Errorf("InsertMap: %v", err)
						return
					}
					continue
				}
				if _, err := table.BatchInsertMaps([]map[string]interface{}{{
					"UserID": g + 1, "Value": float64(i), "Status": fmt.Sprintf("batch-%d", i),
				}}); err != nil {
					t.Errorf("BatchInsertMaps: %v", err)
					return
				}
			}
		}(g)
	}
	wg.Wait()

	if want := int64(goroutines * perGoroutine); table.Count(nil) != want {
		t.Fatalf("库内行数 = %d, 期望 %d（存在丢失）", table.Count(nil), want)
	}
}
