package database

import (
	"fmt"
	"sync/atomic"
	"testing"
)

// 并发基准：对比 MaxOpenConns=1（改造前形态）与 maxOpenConns（写锁 + 读连接池）。
// 注意：MaxOpenConns=1 时 writeMu 基本无开销（单连接本就串行），
// 因此在同一份代码上只切换连接池上限即可公平对比新旧两种形态。

type benchRow struct {
	ID     uint
	UserID uint
	Name   string
	Value  float64
	Status string
}

// setupBenchTable 初始化临时库并写入 seed 行（UserID 均匀分布）。
func setupBenchTable(b *testing.B, maxConns, seed int) *Table {
	b.Helper()
	dir := b.TempDir()
	if err := Init(dir); err != nil {
		b.Fatalf("初始化数据库: %v", err)
	}
	db := Get()
	b.Cleanup(func() { _ = db.Close() })
	db.SQL().SetMaxOpenConns(maxConns)
	db.SQL().SetMaxIdleConns(maxConns)

	table := db.Register("BenchRow")
	rows := make([]map[string]interface{}, 0, seed)
	for i := 1; i <= seed; i++ {
		rows = append(rows, map[string]interface{}{
			"UserID": i%10 + 1,
			"Name":   fmt.Sprintf("row-%d", i),
			"Value":  float64(i),
			"Status": "active",
		})
	}
	if _, err := table.BatchInsertMaps(rows); err != nil {
		b.Fatalf("写入种子数据: %v", err)
	}
	return table
}

// BenchmarkConcurrentReads 纯读负载：直接衡量读吞吐随连接数的扩展。
func BenchmarkConcurrentReads(b *testing.B) {
	for _, maxConns := range []int{1, maxOpenConns} {
		b.Run(fmt.Sprintf("MaxOpenConns=%d", maxConns), func(b *testing.B) {
			const seed = 500
			table := setupBenchTable(b, maxConns, seed)

			var counter atomic.Uint64
			b.ResetTimer()
			b.RunParallel(func(pb *testing.PB) {
				var dest benchRow
				for pb.Next() {
					id := uint(counter.Add(1)%seed) + 1
					if !table.FindByID(id, &dest) {
						b.Errorf("行 %d 未找到", id)
						return
					}
				}
			})
			b.StopTimer()
			b.ReportMetric(float64(b.N)/b.Elapsed().Seconds(), "reads/s")
		})
	}
}

// BenchmarkMixedReadWrite 混合负载：约 80% 读 + 20% 读-改-写（IncrementField 走事务）。
func BenchmarkMixedReadWrite(b *testing.B) {
	for _, maxConns := range []int{1, maxOpenConns} {
		b.Run(fmt.Sprintf("MaxOpenConns=%d", maxConns), func(b *testing.B) {
			const seed = 500
			table := setupBenchTable(b, maxConns, seed)

			var counter, reads, writes atomic.Uint64
			b.ResetTimer()
			b.RunParallel(func(pb *testing.PB) {
				var dest benchRow
				for pb.Next() {
					n := counter.Add(1)
					id := uint(n%seed) + 1
					if n%5 == 0 {
						if err := table.IncrementField(FilterEq("ID", id), "Value", 1); err != nil {
							b.Errorf("IncrementField: %v", err)
							return
						}
						writes.Add(1)
					} else {
						if !table.FindByID(id, &dest) {
							b.Errorf("行 %d 未找到", id)
							return
						}
						reads.Add(1)
					}
				}
			})
			b.StopTimer()
			b.ReportMetric(float64(reads.Load())/b.Elapsed().Seconds(), "reads/s")
			b.ReportMetric(float64(writes.Load())/b.Elapsed().Seconds(), "writes/s")
		})
	}
}
