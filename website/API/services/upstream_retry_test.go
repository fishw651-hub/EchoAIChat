package services

import (
	"context"
	"errors"
	"io"
	"net/http"
	"testing"
	"time"
)

func TestUpstreamRetryDelay(t *testing.T) {
	now := time.Date(2026, 8, 18, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name  string
		err   error
		want  time.Duration
		retry bool
	}{
		{"429 seconds", &UpstreamHTTPError{StatusCode: 429, RetryAfter: "7"}, 7 * time.Second, true},
		{"429 date", &UpstreamHTTPError{StatusCode: 429, RetryAfter: now.Add(12 * time.Second).Format(http.TimeFormat)}, 12 * time.Second, true},
		{"429 capped", &UpstreamHTTPError{StatusCode: 429, RetryAfter: "90"}, 30 * time.Second, true},
		{"429 missing", &UpstreamHTTPError{StatusCode: 429}, 30 * time.Second, true},
		{"429 invalid", &UpstreamHTTPError{StatusCode: 429, RetryAfter: "later"}, 30 * time.Second, true},
		{"429 negative", &UpstreamHTTPError{StatusCode: 429, RetryAfter: "-1"}, 30 * time.Second, true},
		{"429 past date", &UpstreamHTTPError{StatusCode: 429, RetryAfter: now.Add(-time.Minute).Format(http.TimeFormat)}, 0, true},
		{"500", &UpstreamHTTPError{StatusCode: 500}, 5 * time.Second, true},
		{"502", &UpstreamHTTPError{StatusCode: 502}, 5 * time.Second, true},
		{"503", &UpstreamHTTPError{StatusCode: 503}, 5 * time.Second, true},
		{"504", &UpstreamHTTPError{StatusCode: 504}, 5 * time.Second, true},
		{"400", &UpstreamHTTPError{StatusCode: 400}, 0, false},
		{"transport", &upstreamTransportError{Provider: "grok", Err: io.EOF}, 5 * time.Second, true},
		{"unknown", io.EOF, 0, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, retry := upstreamRetryDelay(tt.err, now)
			if got != tt.want || retry != tt.retry {
				t.Fatalf("upstreamRetryDelay() = (%v, %v), want (%v, %v)", got, retry, tt.want, tt.retry)
			}
		})
	}
}

func TestWaitForUpstreamRetry(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err := waitForUpstreamRetry(ctx, time.Minute)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("waitForUpstreamRetry() error = %v, want context.Canceled", err)
	}
}

func TestWaitForUpstreamRetryCanceledContextWinsOverZeroDelay(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	for i := 0; i < 1000; i++ {
		err := waitForUpstreamRetry(ctx, 0)
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("waitForUpstreamRetry() iteration %d error = %v, want context.Canceled", i, err)
		}
	}
}

func TestUpstreamTransportError(t *testing.T) {
	err := &upstreamTransportError{Provider: "grok", Err: io.EOF}
	if !errors.Is(err, io.EOF) {
		t.Fatal("errors.Is() = false, want true for io.EOF")
	}
	if got := err.Error(); got != "请求grok上游失败: EOF" {
		t.Fatalf("Error() = %q, want provider name", got)
	}
}
