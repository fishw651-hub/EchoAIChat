package services

import (
	"net/http"
	"testing"
	"time"
)

func TestAdaptiveLimiterIncreasesAfterHealthyWindow(t *testing.T) {
	limiter := NewAdaptiveLimiter(AdaptiveLimiterConfig{
		MinConcurrency:  2,
		MaxConcurrency:  4,
		HealthyLatency:  500 * time.Millisecond,
		OverloadLatency: 2 * time.Second,
	})

	for range 2 {
		if !limiter.TryAcquire() {
			t.Fatal("healthy request was rejected")
		}
		limiter.Release(http.StatusOK, 100*time.Millisecond)
	}

	if limiter.Limit() != 3 {
		t.Fatalf("limit = %d, want 3", limiter.Limit())
	}
}

func TestAdaptiveLimiterHalvesOnOverloadWithinBounds(t *testing.T) {
	limiter := NewAdaptiveLimiter(AdaptiveLimiterConfig{
		MinConcurrency:     2,
		MaxConcurrency:     8,
		InitialConcurrency: 8,
		HealthyLatency:     500 * time.Millisecond,
		OverloadLatency:    2 * time.Second,
	})

	if !limiter.TryAcquire() {
		t.Fatal("request was rejected")
	}
	limiter.Release(http.StatusTooManyRequests, 100*time.Millisecond)
	if limiter.Limit() != 4 {
		t.Fatalf("limit = %d, want 4", limiter.Limit())
	}

	if !limiter.TryAcquire() {
		t.Fatal("request was rejected")
	}
	limiter.Release(http.StatusOK, 3*time.Second)
	if limiter.Limit() != 2 {
		t.Fatalf("limit = %d, want minimum 2", limiter.Limit())
	}
}

func TestAdaptiveLimiterRejectsWhenCurrentLimitIsFull(t *testing.T) {
	limiter := NewAdaptiveLimiter(AdaptiveLimiterConfig{
		MinConcurrency: 1,
		MaxConcurrency: 1,
	})

	if !limiter.TryAcquire() {
		t.Fatal("first request was rejected")
	}
	if limiter.TryAcquire() {
		t.Fatal("second request should be rejected while the slot is occupied")
	}
}

func BenchmarkAdaptiveLimiter(b *testing.B) {
	limiter := NewAdaptiveLimiter(AdaptiveLimiterConfig{
		MinConcurrency: 32,
		MaxConcurrency: 32,
	})
	b.ReportAllocs()
	for b.Loop() {
		if limiter.TryAcquire() {
			limiter.Release(http.StatusOK, 100*time.Millisecond)
		}
	}
}
