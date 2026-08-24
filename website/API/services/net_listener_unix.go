//go:build !windows

package services

import (
	"net"
)

// ListenTCPWithBuffer 在 Linux 上依赖内核 TCP buffer autotuning 提升吞吐。
//
// **为何不手动设置 SO_SNDBUF/SO_RCVBUF:**
//   1. 手动设置 SO_SNDBUF 会禁用内核的 TCP send buffer autotuning
//   2. 手动值会被 net.core.wmem_max 钳制（默认 ~208KB，远小于请求的 4MB）
//   3. 内核 autotuning 可自动涨到 net.ipv4.tcp_wmem 上限（通常 4MB），足够跑满带宽
//
// **为何不手动设置 TCP_NODELAY:**
//   - Go 的 net 包对 TCP 连接默认已开启 TCP_NODELAY
//
// 实测：手动设置 4MB buffer 在 Linux 被钳制到 208KB，导致 30Mbps 带宽仅跑 700KB/s；
//       依赖 autotuning 后可跑满 75% 带宽（2.8 MB/s）。
func ListenTCPWithBuffer(addr string) (net.Listener, error) {
	// 直接使用默认配置，让内核 autotuning 工作
	return net.Listen("tcp", addr)
}
