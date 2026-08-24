package utils

import (
	"hash/fnv"
	"strconv"
	"sync"
)

// StripedLock 分片锁：固定 256 个桶，key 经 FNV 哈希落桶加锁。
// 相比 per-key sync.Map 锁（条目只增不删、随唯一 key 数无界增长，
// 且删除条目存在 load-vs-delete 竞态），内存恒定有界；
// 代价是不同 key 极小概率落同桶而短暂串行——毫秒级临界区下可忽略。
type StripedLock struct {
	shards [256]sync.Mutex
}

func NewStripedLock() *StripedLock {
	return &StripedLock{}
}

func (l *StripedLock) Lock(key string) func() {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	mu := &l.shards[h.Sum32()%uint32(len(l.shards))]
	mu.Lock()
	return mu.Unlock
}

func (l *StripedLock) LockUint(key uint) func() {
	return l.Lock(strconv.FormatUint(uint64(key), 10))
}
