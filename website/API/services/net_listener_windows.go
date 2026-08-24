//go:build windows

package services

import (
	"context"
	"fmt"
	"net"
	"syscall"
)

// ListenTCPWithBuffer 创建一个 TCP listener，并设置：
//   - SO_SNDBUF = 4MB（默认 16KB，对高 RTT 链路严重不足）
//   - SO_RCVBUF = 4MB
//   - TCP_NODELAY = 1（禁用 Nagle 算法，避免小包延迟）
//
// 这些选项可显著提升跨境/高延迟链路的吞吐量。
func ListenTCPWithBuffer(addr string) (net.Listener, error) {
	lc := net.ListenConfig{
		Control: setSocketOptions,
	}
	return lc.Listen(context.Background(), "tcp", addr)
}

// setSocketOptions 在 Windows 平台设置 socket buffer 和 TCP_NODELAY
// Windows 上 syscall.Handle 是 uintptr，需要类型转换
func setSocketOptions(network, address string, c syscall.RawConn) error {
	var serr error
	err := c.Control(func(fd uintptr) {
		const bufSize = 4 * 1024 * 1024 // 4MB
		handle := syscall.Handle(fd)
		if err := syscall.SetsockoptInt(handle, syscall.SOL_SOCKET, syscall.SO_SNDBUF, bufSize); err != nil {
			serr = fmt.Errorf("设置 SO_SNDBUF 失败: %w", err)
			return
		}
		if err := syscall.SetsockoptInt(handle, syscall.SOL_SOCKET, syscall.SO_RCVBUF, bufSize); err != nil {
			serr = fmt.Errorf("设置 SO_RCVBUF 失败: %w", err)
			return
		}
		if err := syscall.SetsockoptInt(handle, syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1); err != nil {
			serr = fmt.Errorf("设置 TCP_NODELAY 失败: %w", err)
			return
		}
	})
	if err != nil {
		return err
	}
	return serr
}
