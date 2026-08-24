package services

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	maxUpstreamAttempts        = 2
	maxRetryAfterDelay         = 30 * time.Second
	defaultRateLimitRetryDelay = 30 * time.Second
	defaultTransientRetryDelay = 5 * time.Second
)

type upstreamTransportError struct {
	Provider string
	Err      error
}

func (e *upstreamTransportError) Error() string {
	return fmt.Sprintf("请求%s上游失败: %v", e.Provider, e.Err)
}

func (e *upstreamTransportError) Unwrap() error { return e.Err }

func upstreamRetryDelay(err error, now time.Time) (time.Duration, bool) {
	var httpErr *UpstreamHTTPError
	if errors.As(err, &httpErr) {
		switch httpErr.StatusCode {
		case http.StatusTooManyRequests:
			if delay, ok := parseRetryAfter(httpErr.RetryAfter, now); ok {
				return delay, true
			}
			return defaultRateLimitRetryDelay, true
		case http.StatusInternalServerError, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
			return defaultTransientRetryDelay, true
		default:
			return 0, false
		}
	}

	var transportErr *upstreamTransportError
	if errors.As(err, &transportErr) {
		return defaultTransientRetryDelay, true
	}

	return 0, false
}

func parseRetryAfter(retryAfter string, now time.Time) (time.Duration, bool) {
	retryAfter = strings.TrimSpace(retryAfter)
	if retryAfter == "" {
		return 0, false
	}

	if seconds, err := strconv.ParseInt(retryAfter, 10, 64); err == nil {
		if seconds < 0 {
			return 0, false
		}
		if seconds >= int64(maxRetryAfterDelay/time.Second) {
			return maxRetryAfterDelay, true
		}
		return time.Duration(seconds) * time.Second, true
	}

	date, err := http.ParseTime(retryAfter)
	if err != nil {
		return 0, false
	}

	delay := date.Sub(now)
	if delay <= 0 {
		return 0, true
	}
	if delay > maxRetryAfterDelay {
		return maxRetryAfterDelay, true
	}
	return delay, true
}

func waitForUpstreamRetry(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()

	if err := ctx.Err(); err != nil {
		return err
	}

	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
