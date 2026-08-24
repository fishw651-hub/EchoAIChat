package services

import (
	"sync"

	"aichat-api/config"
)

// RuntimeConfig 是 services 层对全局配置的运行期依赖子集。
// 全部字段为 getter 函数而非值拷贝：加密密钥、支付参数、上游站点等原本就是
// "每次使用时读全局配置" 的热读语义（后台改配置/测试替换立即生效），
// 注入 getter 可原样保留这一时机。
//
// 装配：main.go 在 config.LoadConfig 之后调用一次 ConfigureRuntime；
// 测试可用 ConfigureRuntime 替换（并用 t.Cleanup 恢复）。
type RuntimeConfig struct {
	// EncryptionKey 主加密密钥（DecryptWithConfiguredKeys 的第一把钥匙）。
	EncryptionKey func() string
	// EncryptionFallbackKeys 历史密文兼容密钥。
	EncryptionFallbackKeys func() []string
	// DeepSeekBaseURL deepseek 上游默认站点（APIKey 未配 BaseURL 时的回退）。
	DeepSeekBaseURL func() string
	// ServerURL 站点外网地址（支付回调 URL 拼接的兜底）。
	ServerURL func() string
	// EasyPay 易支付商户参数（DB SystemConfig 缺失时的兜底）。
	EasyPay func() config.EasyPayConfig
	// Network 上游连接池/后台限流参数（仅启动期消费一次）。
	Network func() config.NetworkConfig
}

var (
	runtimeCfgMu sync.RWMutex
	runtimeCfg   RuntimeConfig
)

// ConfigureRuntime 注入 services 层的运行期配置。允许重复调用（后者覆盖前者）。
func ConfigureRuntime(rc RuntimeConfig) {
	runtimeCfgMu.Lock()
	runtimeCfg = rc
	runtimeCfgMu.Unlock()
}

// runtimeEncryptionKey 返回 (key, configured)；未配置等价于原 AppConfig == nil 的语义。
func runtimeEncryptionKey() (string, bool) {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.EncryptionKey
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return "", false
	}
	return fn(), true
}

func runtimeEncryptionFallbackKeys() []string {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.EncryptionFallbackKeys
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return nil
	}
	return fn()
}

func runtimeDeepSeekBaseURL() string {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.DeepSeekBaseURL
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return ""
	}
	return fn()
}

func runtimeServerURL() string {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.ServerURL
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return ""
	}
	return fn()
}

func runtimeEasyPay() config.EasyPayConfig {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.EasyPay
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return config.EasyPayConfig{}
	}
	return fn()
}

func runtimeNetwork() config.NetworkConfig {
	runtimeCfgMu.RLock()
	fn := runtimeCfg.Network
	runtimeCfgMu.RUnlock()
	if fn == nil {
		return config.NetworkConfig{}
	}
	return fn()
}
