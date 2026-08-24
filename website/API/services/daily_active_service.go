package services

import (
	"context"
	"fmt"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

type DailyActivePoint struct {
	Date  string `json:"date"`
	Count int    `json:"count"`
}

type DailyActiveStats struct {
	Today         int                `json:"today"`
	Yesterday     int                `json:"yesterday"`
	ChangePercent float64            `json:"change_percent"`
	Peak          int                `json:"peak"`
	Average       float64            `json:"average"`
	Trend         []DailyActivePoint `json:"trend"`
}

type DailyActiveService struct {
	mu   sync.Mutex
	day  string
	db   *database.DB // DB 重建（测试场景）时 seen 一并重置
	seen map[uint]struct{}
}

func NewDailyActiveService() *DailyActiveService {
	return &DailyActiveService{seen: make(map[uint]struct{})}
}

// Track 记录用户当日活跃。seen 按天整体轮换：跨天时丢弃旧日集合，
// 避免 key 携带日期导致 map 随天数×用户数无界增长。
func (s *DailyActiveService) Track(userID uint, role string, now time.Time) error {
	if role != "user" {
		return nil
	}

	currentDB := database.Get()
	activeDate := now.Format("2006-01-02")
	s.mu.Lock()
	if s.day != activeDate || s.db != currentDB {
		s.day = activeDate
		s.db = currentDB
		s.seen = make(map[uint]struct{})
	}
	if _, ok := s.seen[userID]; ok {
		s.mu.Unlock()
		return nil
	}
	s.mu.Unlock()

	err := currentDB.WithTx(context.Background(), func(tx *database.Tx) error {
		return tx.UpsertByUserIDClientID("DailyActiveUser", userID, map[string]interface{}{
			"ClientID":      activeDate,
			"ActiveDate":    activeDate,
			"FirstActiveAt": now,
			"CreatedAt":     now,
		})
	})
	if err != nil {
		return fmt.Errorf("tracking daily active user: %w", err)
	}
	s.mu.Lock()
	if s.day == activeDate && s.db == currentDB {
		s.seen[userID] = struct{}{}
	}
	s.mu.Unlock()
	return nil
}

func GetDailyActiveStats(days int, now time.Time) (DailyActiveStats, error) {
	if days != 7 && days != 30 && days != 90 {
		return DailyActiveStats{}, fmt.Errorf("unsupported daily active range: %d", days)
	}

	start := now.AddDate(0, 0, -(days - 1)).Format("2006-01-02")
	var records []models.DailyActiveUser
	database.Get().Register("DailyActiveUser").FindAll(
		&records,
		database.FilterGte("ActiveDate", start),
		"",
		0,
		0,
	)

	usersByDate := make(map[string]map[uint]struct{}, days)
	for _, record := range records {
		if usersByDate[record.ActiveDate] == nil {
			usersByDate[record.ActiveDate] = make(map[uint]struct{})
		}
		usersByDate[record.ActiveDate][record.UserID] = struct{}{}
	}

	trend := make([]DailyActivePoint, 0, days)
	total := 0
	peak := 0
	for offset := days - 1; offset >= 0; offset-- {
		date := now.AddDate(0, 0, -offset).Format("2006-01-02")
		count := len(usersByDate[date])
		trend = append(trend, DailyActivePoint{Date: date, Count: count})
		total += count
		if count > peak {
			peak = count
		}
	}

	today := trend[len(trend)-1].Count
	yesterday := trend[len(trend)-2].Count
	changePercent := 0.0
	if yesterday > 0 {
		changePercent = float64(today-yesterday) / float64(yesterday) * 100
	} else if today > 0 {
		changePercent = 100
	}

	return DailyActiveStats{
		Today:         today,
		Yesterday:     yesterday,
		ChangePercent: changePercent,
		Peak:          peak,
		Average:       float64(total) / float64(days),
		Trend:         trend,
	}, nil
}
