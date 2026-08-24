package services

import (
	"net"
	"net/http"
	"sync"
	"time"

	"aichat-api/config"
)

func NewUpstreamTransport(value config.NetworkConfig) *http.Transport {
	value = config.NormalizeNetworkConfig(value)
	return &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          value.UpstreamIdleConns * 2,
		MaxIdleConnsPerHost:   value.UpstreamIdleConns,
		MaxConnsPerHost:       value.UpstreamMaxConnsPerHost,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
		ExpectContinueTimeout: time.Second,
	}
}

type upstreamClients struct {
	completion *http.Client
	stream     *http.Client
	metadata   *http.Client
}

var (
	sharedUpstreamClients upstreamClients
	upstreamClientsOnce   sync.Once
)

func getUpstreamClients() upstreamClients {
	upstreamClientsOnce.Do(func() {
		transport := NewUpstreamTransport(runtimeNetwork())
		sharedUpstreamClients = upstreamClients{
			completion: &http.Client{Transport: transport, Timeout: 120 * time.Second},
			stream:     &http.Client{Transport: transport, Timeout: 300 * time.Second},
			metadata:   &http.Client{Transport: transport, Timeout: 30 * time.Second},
		}
	})
	return sharedUpstreamClients
}
