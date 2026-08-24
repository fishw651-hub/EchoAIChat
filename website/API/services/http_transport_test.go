package services

import (
	"testing"
	"time"

	"aichat-api/config"
)

func TestNormalizeNetworkConfigUsesSafeBounds(t *testing.T) {
	normalized := config.NormalizeNetworkConfig(config.NetworkConfig{
		BackgroundMinConcurrency: 0,
		BackgroundMaxConcurrency: 1,
		HealthyLatencyMS:         -1,
		OverloadLatencyMS:        20,
		UpstreamIdleConns:        80,
		UpstreamMaxConnsPerHost:  20,
	})

	if normalized.BackgroundMinConcurrency < 1 {
		t.Fatalf("minimum concurrency = %d", normalized.BackgroundMinConcurrency)
	}
	if normalized.BackgroundMaxConcurrency < normalized.BackgroundMinConcurrency {
		t.Fatalf("concurrency bounds = %d..%d", normalized.BackgroundMinConcurrency, normalized.BackgroundMaxConcurrency)
	}
	if normalized.OverloadLatencyMS <= normalized.HealthyLatencyMS {
		t.Fatalf("latency bounds = %d..%d", normalized.HealthyLatencyMS, normalized.OverloadLatencyMS)
	}
	if normalized.UpstreamMaxConnsPerHost < normalized.UpstreamIdleConns {
		t.Fatalf("connection bounds = idle %d max %d", normalized.UpstreamIdleConns, normalized.UpstreamMaxConnsPerHost)
	}
}

func TestNormalizeNetworkConfigKeepsExtremeValuesInternallyConsistent(t *testing.T) {
	normalized := config.NormalizeNetworkConfig(config.NetworkConfig{
		BackgroundMinConcurrency: 80,
		BackgroundMaxConcurrency: 1,
		HealthyLatencyMS:         10000,
		OverloadLatencyMS:        100,
	})

	if normalized.BackgroundMaxConcurrency < normalized.BackgroundMinConcurrency {
		t.Fatalf("concurrency bounds = %d..%d", normalized.BackgroundMinConcurrency, normalized.BackgroundMaxConcurrency)
	}
	if normalized.OverloadLatencyMS <= normalized.HealthyLatencyMS {
		t.Fatalf("latency bounds = %d..%d", normalized.HealthyLatencyMS, normalized.OverloadLatencyMS)
	}
}

func TestNormalizeNetworkConfigCapsUnsafeValues(t *testing.T) {
	normalized := config.NormalizeNetworkConfig(config.NetworkConfig{
		BackgroundMinConcurrency: 100000,
		BackgroundMaxConcurrency: 100000,
		HealthyLatencyMS:         10000000,
		OverloadLatencyMS:        20000000,
		UpstreamIdleConns:        100000,
		UpstreamMaxConnsPerHost:  100000,
	})

	if normalized.BackgroundMaxConcurrency > 1024 {
		t.Fatalf("background max = %d, want <= 1024", normalized.BackgroundMaxConcurrency)
	}
	if normalized.UpstreamMaxConnsPerHost > 2048 {
		t.Fatalf("upstream max = %d, want <= 2048", normalized.UpstreamMaxConnsPerHost)
	}
	if normalized.OverloadLatencyMS > 300000 {
		t.Fatalf("overload latency = %d, want <= 300000", normalized.OverloadLatencyMS)
	}
}

func TestNewUpstreamTransportUsesNormalizedPoolLimits(t *testing.T) {
	cfg := config.NormalizeNetworkConfig(config.NetworkConfig{
		UpstreamIdleConns:       32,
		UpstreamMaxConnsPerHost: 64,
	})
	transport := NewUpstreamTransport(cfg)

	if transport.MaxIdleConnsPerHost != 32 || transport.MaxConnsPerHost != 64 {
		t.Fatalf("pool = %d/%d, want 32/64", transport.MaxIdleConnsPerHost, transport.MaxConnsPerHost)
	}
	if !transport.ForceAttemptHTTP2 {
		t.Fatal("HTTP/2 should be enabled for upstream connection reuse")
	}
	if transport.ResponseHeaderTimeout != 60*time.Second {
		t.Fatalf("response header timeout = %v, want 60s", transport.ResponseHeaderTimeout)
	}
}
