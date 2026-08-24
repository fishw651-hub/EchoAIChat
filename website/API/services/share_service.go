package services

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

// 分享智能体规则：
//   - 分享码为 6 位数字（100000-999999），有效期 ShareCodeTTL
//   - 有效期内可多人重复兑换，不删除记录
//   - 兑换失败防爆破：同一用户 RedeemRateWindow 内失败 RedeemMaxFailures 次后拒绝再试（仅计失败）
const (
	ShareCodeTTL       = 20 * time.Minute
	ShareMaxSnapshotKB = 512
	RedeemRateWindow   = 10 * time.Minute
	RedeemMaxFailures  = 10
)

const shareMaxSnapshotBytes = ShareMaxSnapshotKB * 1024

var (
	ErrShareSnapshotTooLarge = errors.New("快照过大，超过 512KB 限制")
	ErrShareSnapshotEmpty    = errors.New("快照不能为空")
	ErrShareCodeNotFound     = errors.New("分享码不存在")
	ErrShareCodeExpired      = errors.New("分享码已过期")
	ErrRedeemRateLimited     = errors.New("兑换失败次数过多，请稍后再试")
)

func shareCodeTable() *database.Table {
	return database.Get().Register("ShareCode")
}

// CreateShareCode 为用户生成智能体分享码，返回码与过期时间。
// 顺带清理全表已过期记录（创建路径驱动，无需后台 goroutine）。
func CreateShareCode(userID uint, snapshot []byte) (string, time.Time, error) {
	if len(snapshot) == 0 {
		return "", time.Time{}, ErrShareSnapshotEmpty
	}
	if len(snapshot) > shareMaxSnapshotBytes {
		return "", time.Time{}, ErrShareSnapshotTooLarge
	}

	tbl := shareCodeTable()
	now := time.Now()

	// 清理已过期记录
	var all []models.ShareCode
	tbl.FindAll(&all, nil, "", 0, 0)
	for _, record := range all {
		if !record.ExpiresAt.After(now) {
			tbl.Delete(record.ID)
		}
	}

	// 生成不冲突的 6 位数字码，碰撞时重试
	var code string
	for attempt := 0; attempt < 10; attempt++ {
		candidate, err := generateShareCode()
		if err != nil {
			return "", time.Time{}, fmt.Errorf("生成分享码失败: %w", err)
		}
		var existing models.ShareCode
		if tbl.FindOne(database.FilterEq("Code", candidate), &existing) {
			continue
		}
		code = candidate
		break
	}
	if code == "" {
		return "", time.Time{}, errors.New("生成分享码失败：碰撞次数过多")
	}

	expiresAt := now.Add(ShareCodeTTL)
	if err := tbl.Insert(&models.ShareCode{
		Code:        code,
		OwnerUserID: userID,
		Snapshot:    string(snapshot),
		ExpiresAt:   expiresAt,
	}); err != nil {
		return "", time.Time{}, fmt.Errorf("保存分享码失败: %w", err)
	}
	return code, expiresAt, nil
}

// RedeemShareCode 凭码兑换智能体快照。有效期内可多人重复兑换（不删除记录）。
// 码不存在返回 ErrShareCodeNotFound，已过期返回 ErrShareCodeExpired，可区分。
func RedeemShareCode(code string) ([]byte, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return nil, ErrShareCodeNotFound
	}
	var record models.ShareCode
	if !shareCodeTable().FindOne(database.FilterEq("Code", code), &record) {
		return nil, ErrShareCodeNotFound
	}
	if !record.ExpiresAt.After(time.Now()) {
		return nil, ErrShareCodeExpired
	}
	return []byte(record.Snapshot), nil
}

// generateShareCode 生成 100000-999999 的 6 位数字码
func generateShareCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()+100000), nil
}

// 兑换失败防爆破限流：内存固定窗口计数（仅计失败，成功不计）
var redeemRateLimit = struct {
	sync.Mutex
	entries map[uint]*redeemRateEntry
}{entries: make(map[uint]*redeemRateEntry)}

type redeemRateEntry struct {
	windowStart time.Time
	failures    int
}

// CheckRedeemRateLimit 用户当前是否被限流；被限流时返回 ErrRedeemRateLimited
func CheckRedeemRateLimit(userID uint) error {
	redeemRateLimit.Lock()
	defer redeemRateLimit.Unlock()
	entry, ok := redeemRateLimit.entries[userID]
	if !ok || time.Since(entry.windowStart) >= RedeemRateWindow {
		return nil
	}
	if entry.failures >= RedeemMaxFailures {
		return ErrRedeemRateLimited
	}
	return nil
}

// ═══ per-IP 兑换防爆破（批量注册小号绕过 per-user 限流的兜底） ═══

// 兑换失败防爆破限流（per-IP）：注册邮箱选填、账号可批量注册，
// 仅按 userID 计数会被线性放大；同一 IP 的失败次数也设上限
var redeemIPRateLimit = struct {
	sync.Mutex
	entries map[string]*redeemRateEntry
}{entries: make(map[string]*redeemRateEntry)}

// 同窗口下 per-IP 上限放宽到 per-user 的 5 倍（NAT/校园网共享 IP 误伤兜底）
const redeemIPMaxFailures = RedeemMaxFailures * 5

// CheckRedeemIPRateLimit IP 当前是否被限流
func CheckRedeemIPRateLimit(ip string) error {
	redeemIPRateLimit.Lock()
	defer redeemIPRateLimit.Unlock()
	entry, ok := redeemIPRateLimit.entries[ip]
	if !ok || time.Since(entry.windowStart) >= RedeemRateWindow {
		return nil
	}
	if entry.failures >= redeemIPMaxFailures {
		return ErrRedeemRateLimited
	}
	return nil
}

// RecordRedeemIPFailure 记录一次 per-IP 兑换失败（含懒清扫，防 map 无界增长）
func RecordRedeemIPFailure(ip string) {
	redeemIPRateLimit.Lock()
	defer redeemIPRateLimit.Unlock()
	if len(redeemIPRateLimit.entries) > 4096 {
		for k, entry := range redeemIPRateLimit.entries {
			if time.Since(entry.windowStart) >= RedeemRateWindow {
				delete(redeemIPRateLimit.entries, k)
			}
		}
	}
	entry, ok := redeemIPRateLimit.entries[ip]
	if !ok || time.Since(entry.windowStart) >= RedeemRateWindow {
		redeemIPRateLimit.entries[ip] = &redeemRateEntry{windowStart: time.Now(), failures: 1}
		return
	}
	entry.failures++
}

// RecordRedeemFailure 记录一次兑换失败（码不存在/已过期）。窗口过期后重新计数。
func RecordRedeemFailure(userID uint) {
	redeemRateLimit.Lock()
	defer redeemRateLimit.Unlock()
	// 懒清扫：条目随失败用户数无界增长，超过阈值时清掉窗口已过期的条目
	if len(redeemRateLimit.entries) > 4096 {
		for id, entry := range redeemRateLimit.entries {
			if time.Since(entry.windowStart) >= RedeemRateWindow {
				delete(redeemRateLimit.entries, id)
			}
		}
	}
	entry, ok := redeemRateLimit.entries[userID]
	if !ok || time.Since(entry.windowStart) >= RedeemRateWindow {
		redeemRateLimit.entries[userID] = &redeemRateEntry{windowStart: time.Now(), failures: 1}
		return
	}
	entry.failures++
}
