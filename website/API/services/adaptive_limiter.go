package services

import (
	"net/http"
	"sync"
	"time"

	"aichat-api/config"
)

type AdaptiveLimiterConfig struct {
	MinConcurrency     int
	MaxConcurrency     int
	InitialConcurrency int
	HealthyLatency     time.Duration
	OverloadLatency    time.Duration
}

type AdaptiveLimiter struct {
	mu              sync.Mutex
	min             int
	max             int
	limit           int
	inFlight        int
	healthyStreak   int
	healthyLatency  time.Duration
	overloadLatency time.Duration
}

func NewAdaptiveLimiter(value AdaptiveLimiterConfig) *AdaptiveLimiter {
	if value.MinConcurrency < 1 {
		value.MinConcurrency = 1
	}
	if value.MaxConcurrency < value.MinConcurrency {
		value.MaxConcurrency = value.MinConcurrency
	}
	if value.InitialConcurrency < value.MinConcurrency || value.InitialConcurrency > value.MaxConcurrency {
		value.InitialConcurrency = value.MinConcurrency
	}
	if value.HealthyLatency <= 0 {
		value.HealthyLatency = 800 * time.Millisecond
	}
	if value.OverloadLatency <= value.HealthyLatency {
		value.OverloadLatency = 3 * time.Second
	}
	return &AdaptiveLimiter{
		min:             value.MinConcurrency,
		max:             value.MaxConcurrency,
		limit:           value.InitialConcurrency,
		healthyLatency:  value.HealthyLatency,
		overloadLatency: value.OverloadLatency,
	}
}

func (l *AdaptiveLimiter) TryAcquire() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.inFlight >= l.limit {
		return false
	}
	l.inFlight++
	return true
}

func (l *AdaptiveLimiter) Release(status int, elapsed time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.inFlight > 0 {
		l.inFlight--
	}
	if status == http.StatusTooManyRequests || status >= http.StatusInternalServerError || elapsed >= l.overloadLatency {
		l.limit = max(l.min, l.limit/2)
		l.healthyStreak = 0
		return
	}
	if status >= http.StatusOK && status < http.StatusBadRequest && elapsed <= l.healthyLatency {
		l.healthyStreak++
		if l.healthyStreak >= l.limit && l.limit < l.max {
			l.limit++
			l.healthyStreak = 0
		}
		return
	}
	l.healthyStreak = 0
}

func (l *AdaptiveLimiter) Limit() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.limit
}

var (
	defaultBackgroundLimiterOnce sync.Once
	defaultBackgroundLimiter     *AdaptiveLimiter
)

func DefaultBackgroundLimiter() *AdaptiveLimiter {
	defaultBackgroundLimiterOnce.Do(func() {
		value := config.NormalizeNetworkConfig(runtimeNetwork())
		defaultBackgroundLimiter = NewAdaptiveLimiter(AdaptiveLimiterConfig{
			MinConcurrency:     value.BackgroundMinConcurrency,
			MaxConcurrency:     value.BackgroundMaxConcurrency,
			InitialConcurrency: value.BackgroundMinConcurrency,
			HealthyLatency:     time.Duration(value.HealthyLatencyMS) * time.Millisecond,
			OverloadLatency:    time.Duration(value.OverloadLatencyMS) * time.Millisecond,
		})
	})
	return defaultBackgroundLimiter
}
