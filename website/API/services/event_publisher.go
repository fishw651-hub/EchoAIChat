package services

import (
	"sync"

	"aichat-api/hub"
)

// EventPublisher 是 services 包对事件中枢（hub.SyncHub）的窄接口抽象。
// 业务代码一律经此接口发布事件，不直接引用 hub 包的全局单例。
type EventPublisher interface {
	// NotifyUserAppEvent 向指定用户的全部在线设备发送定向事件。
	NotifyUserAppEvent(userID uint, event hub.AppEvent)
	// NotifyGlobalAppEvent 向所有在线登录用户广播公共资源失效事件。
	NotifyGlobalAppEvent(event hub.AppEvent)
	// NotifySyncChange 通知某用户的所有在线设备有数据变更（100%同步用）。
	NotifySyncChange(userID uint, tableName string)
}

var (
	eventPublisherMu sync.RWMutex
	eventPublisher   EventPublisher
)

// SetEventPublisher 注入事件发布器（main.go 装配时调用；传 nil 恢复为无操作）。
func SetEventPublisher(p EventPublisher) {
	eventPublisherMu.Lock()
	eventPublisher = p
	eventPublisherMu.Unlock()
}

// getEventPublisher 返回当前事件发布器；未注入时返回 nil，调用方需判空（nil 安全）。
func getEventPublisher() EventPublisher {
	eventPublisherMu.RLock()
	defer eventPublisherMu.RUnlock()
	return eventPublisher
}
