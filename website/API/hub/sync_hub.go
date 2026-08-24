package hub

import (
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"

	"aichat-api/models"

	"github.com/gorilla/websocket"
)

// SyncMessage WebSocket 消息协议
type SyncMessage struct {
	Type          string `json:"type"`      // ready / app_event / chat_lock / chat_unlock / lock_status / sync_notify / ping / pong / error
	AgentID       string `json:"agent_id"`  // 智能体 ID（私聊锁）
	GroupID       string `json:"group_id"`  // 群聊 ID（群聊锁）
	Status        string `json:"status"`    // typing（输入中） / waiting（等待AI回复）
	DeviceID      string `json:"device_id"` // 发起锁的设备 ID
	DeviceName    string `json:"device_name"`
	Timestamp     int64  `json:"timestamp"`
	Message       string `json:"message"` // 错误或提示信息
	PolicyVersion uint64 `json:"policy_version,omitempty"`
	SyncEnabled   bool   `json:"sync_enabled,omitempty"`
	Scope         string `json:"scope,omitempty"`
	ResourceType  string `json:"resource_type,omitempty"`
	ResourceID    uint   `json:"resource_id,omitempty"`
	Reason        string `json:"reason,omitempty"`
	Version       int    `json:"version,omitempty"`
	EventID       string `json:"event_id,omitempty"`
}

const (
	AppEventScopeNetworkAgents = "network_agents"
	AppEventScopeNetworkGroups = "network_groups"
	AppEventScopeMyUploads     = "my_uploads"
	AppEventScopeQuota         = "quota"
	AppEventScopeSubscription  = "subscription"
)

// AppEvent 只通知客户端对应资源已失效，权威内容仍通过 HTTP 拉取。
type AppEvent struct {
	Scope        string
	ResourceType string
	ResourceID   uint
	Status       string
	Reason       string
	Version      int
	EventID      string
	Timestamp    int64
}

// SyncClient 一个 WebSocket 连接
type SyncClient struct {
	UserID     uint
	DeviceID   string
	DeviceName string
	// SyncEnabled 仅控制同步通知和聊天锁；false 的登录用户仍可接收 app_event。
	SyncEnabled bool
	Conn        *websocket.Conn
	Send        chan []byte
	Hub         *SyncHub

	// appEventMu protects the bounded, per-scope app-event mailbox. App events
	// are kept separate from Send so a burst of ordinary sync messages cannot
	// discard the refresh signal needed by the client.
	appEventMu          sync.Mutex
	pendingAppEvents    map[string][]byte
	pendingAppEventKeys []string
	appEventWake        chan struct{}
}

// queueAppEvent stores the newest event for a scope and wakes WritePump.
// A client without a websocket is an in-memory test sink; preserve its
// historical direct-channel behavior when there is room in Send.
func (c *SyncClient) queueAppEvent(scope string, data []byte) {
	if c.Conn == nil {
		select {
		case c.Send <- data:
			return
		default:
		}
	}

	c.appEventMu.Lock()
	if c.pendingAppEvents == nil {
		c.pendingAppEvents = make(map[string][]byte)
	}
	if c.appEventWake == nil {
		c.appEventWake = make(chan struct{}, 1)
	}
	if _, exists := c.pendingAppEvents[scope]; !exists {
		c.pendingAppEventKeys = append(c.pendingAppEventKeys, scope)
	}
	c.pendingAppEvents[scope] = data
	wake := c.appEventWake
	c.appEventMu.Unlock()

	select {
	case wake <- struct{}{}:
	default:
	}
}

func (c *SyncClient) popAppEvent() ([]byte, bool) {
	c.appEventMu.Lock()
	defer c.appEventMu.Unlock()
	if len(c.pendingAppEventKeys) == 0 {
		return nil, false
	}
	scope := c.pendingAppEventKeys[0]
	c.pendingAppEventKeys = c.pendingAppEventKeys[1:]
	data, ok := c.pendingAppEvents[scope]
	if ok {
		delete(c.pendingAppEvents, scope)
	}
	return data, ok
}

func (c *SyncClient) appEventWakeChannel() <-chan struct{} {
	c.appEventMu.Lock()
	defer c.appEventMu.Unlock()
	if c.appEventWake == nil {
		c.appEventWake = make(chan struct{}, 1)
	}
	return c.appEventWake
}

// chatLockKey 聊天锁的 key（用户级 + 会话级）
func chatLockKey(userID uint, agentID, groupID string) string {
	if groupID != "" {
		return formatLockKey(userID, "", groupID)
	}
	return formatLockKey(userID, agentID, "")
}

func formatLockKey(userID uint, agentID, groupID string) string {
	if groupID != "" {
		return formatUint(userID) + ":g:" + groupID
	}
	return formatUint(userID) + ":a:" + agentID
}

func formatUint(n uint) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

// chatLockEntry 聊天锁条目
type chatLockEntry struct {
	DeviceID   string
	DeviceName string
	Status     string // typing / waiting
	UpdatedAt  time.Time
}

// SyncHub 管理所有在线设备的 WebSocket 连接和聊天锁
type SyncHub struct {
	mu      sync.RWMutex
	clients map[*SyncClient]bool          // 所有在线客户端
	users   map[uint]map[*SyncClient]bool // 按用户分组的客户端
	locks   map[string]*chatLockEntry     // 聊天锁：key = "userID:a:agentID" 或 "userID:g:groupID"
}

// NewSyncHub 创建 Hub 实例
func NewSyncHub() *SyncHub {
	return &SyncHub{
		clients: make(map[*SyncClient]bool),
		users:   make(map[uint]map[*SyncClient]bool),
		locks:   make(map[string]*chatLockEntry),
	}
}

// Run 启动后台清理（过期锁清理）
func (h *SyncHub) Run() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		h.cleanupExpiredLocks()
	}
}

// cleanupExpiredLocks 清理超过 60 秒无心跳的锁
func (h *SyncHub) cleanupExpiredLocks() {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := time.Now()
	for key, entry := range h.locks {
		if now.Sub(entry.UpdatedAt) > 60*time.Second {
			delete(h.locks, key)
		}
	}
}

// RegisterClient 注册客户端
func (h *SyncHub) RegisterClient(c *SyncClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[c] = true
	if h.users[c.UserID] == nil {
		h.users[c.UserID] = make(map[*SyncClient]bool)
	}
	h.users[c.UserID][c] = true
}

// UnregisterClient 注销客户端
func (h *SyncHub) UnregisterClient(c *SyncClient) {
	h.mu.Lock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
	}
	if clients, ok := h.users[c.UserID]; ok {
		delete(clients, c)
		if len(clients) == 0 {
			delete(h.users, c.UserID)
		}
	}
	// 释放该设备持有的所有锁，并收集需要通知的客户端
	notifyClients := h.releaseDeviceLocksLocked(c.UserID, c.DeviceID)
	h.mu.Unlock()
	// 锁外发送通知，减少锁持有时间
	if len(notifyClients) > 0 {
		h.sendToClients(notifyClients, SyncMessage{
			Type:    "lock_status",
			Message: "released",
		})
	}
}

// releaseDeviceLocksLocked 释放指定设备的所有锁（调用方需持锁）
// 返回需要通知的客户端列表
func (h *SyncHub) releaseDeviceLocksLocked(userID uint, deviceID string) []*SyncClient {
	toRelease := []string{}
	userLockPrefix := formatUint(userID) + ":"
	for key, entry := range h.locks {
		if strings.HasPrefix(key, userLockPrefix) && entry.DeviceID == deviceID {
			toRelease = append(toRelease, key)
		}
	}
	for _, key := range toRelease {
		delete(h.locks, key)
	}
	if len(toRelease) > 0 {
		return h.collectClientsLocked(userID, "")
	}
	return nil
}

// HandleChatLock 处理聊天锁请求
// 返回错误消息（如果锁冲突），nil 表示成功
func (h *SyncHub) HandleChatLock(client *SyncClient, msg SyncMessage) *SyncMessage {
	if !client.SyncEnabled {
		return &SyncMessage{
			Type:    "error",
			Message: "当前连接未启用多端同步",
			AgentID: msg.AgentID,
			GroupID: msg.GroupID,
		}
	}
	h.mu.Lock()

	key := chatLockKey(client.UserID, msg.AgentID, msg.GroupID)
	existing := h.locks[key]

	// 已有锁且不是自己的设备
	if existing != nil && existing.DeviceID != client.DeviceID {
		// 检查锁是否过期（60秒）
		if time.Since(existing.UpdatedAt) > 60*time.Second {
			// 锁已过期，直接抢占
			h.locks[key] = &chatLockEntry{
				DeviceID:   client.DeviceID,
				DeviceName: client.DeviceName,
				Status:     msg.Status,
				UpdatedAt:  time.Now(),
			}
			broadcastMsg := SyncMessage{
				Type:       "lock_status",
				AgentID:    msg.AgentID,
				GroupID:    msg.GroupID,
				Status:     msg.Status,
				DeviceID:   client.DeviceID,
				DeviceName: client.DeviceName,
				Timestamp:  time.Now().Unix(),
			}
			clients := h.collectClientsLocked(client.UserID, "")
			h.mu.Unlock()
			h.sendToClients(clients, broadcastMsg)
			return nil
		}
		// 锁冲突
		conflictMsg := &SyncMessage{
			Type:       "error",
			Message:    "你在同步状态，不要在同一聊天同时发起聊天信息",
			AgentID:    msg.AgentID,
			GroupID:    msg.GroupID,
			DeviceID:   existing.DeviceID,
			DeviceName: existing.DeviceName,
		}
		h.mu.Unlock()
		return conflictMsg
	}

	// 没有锁或者是自己的锁 → 更新/创建
	h.locks[key] = &chatLockEntry{
		DeviceID:   client.DeviceID,
		DeviceName: client.DeviceName,
		Status:     msg.Status,
		UpdatedAt:  time.Now(),
	}

	// 收集需要通知的客户端，锁外发送以减少锁持有时间
	broadcastMsg := SyncMessage{
		Type:       "lock_status",
		AgentID:    msg.AgentID,
		GroupID:    msg.GroupID,
		Status:     msg.Status,
		DeviceID:   client.DeviceID,
		DeviceName: client.DeviceName,
		Timestamp:  time.Now().Unix(),
	}
	clients := h.collectClientsLocked(client.UserID, "")
	h.mu.Unlock()
	h.sendToClients(clients, broadcastMsg)

	return nil
}

// HandleChatUnlock 处理释放锁请求
func (h *SyncHub) HandleChatUnlock(client *SyncClient, msg SyncMessage) {
	if !client.SyncEnabled {
		return
	}
	h.mu.Lock()

	key := chatLockKey(client.UserID, msg.AgentID, msg.GroupID)
	var clients []*SyncClient
	broadcastMsg := SyncMessage{}
	if entry, ok := h.locks[key]; ok && entry.DeviceID == client.DeviceID {
		delete(h.locks, key)
		broadcastMsg = SyncMessage{
			Type:      "lock_status",
			Message:   "released",
			AgentID:   msg.AgentID,
			GroupID:   msg.GroupID,
			Timestamp: time.Now().Unix(),
		}
		clients = h.collectClientsLocked(client.UserID, client.DeviceID)
	}
	h.mu.Unlock()
	// 锁外发送通知，减少锁持有时间
	if clients != nil {
		h.sendToClients(clients, broadcastMsg)
	}
}

// NotifySyncChange 通知某用户的所有在线设备有数据变更（100%同步用）
func (h *SyncHub) NotifySyncChange(userID uint, tableName string) {
	h.mu.RLock()
	clients := h.collectClientsLocked(userID, "")
	h.mu.RUnlock()
	h.sendToClients(clients, SyncMessage{
		Type:      "sync_notify",
		Message:   tableName,
		Timestamp: time.Now().Unix(),
	})
}

func (h *SyncHub) NotifyDataChange(
	userID uint,
	sourceDeviceID string,
	tableName string,
	agentID string,
	policy models.SyncPolicy,
) {
	if !policy.RealtimeEnabled {
		return
	}
	if policy.ScopeMode == "selected" {
		selected := false
		for _, selectedAgentID := range policy.SelectedAgentIDs {
			if selectedAgentID == agentID {
				selected = true
				break
			}
		}
		if !selected {
			return
		}
	}

	h.mu.RLock()
	clients := h.collectClientsLocked(userID, sourceDeviceID)
	h.mu.RUnlock()
	h.sendToClients(clients, SyncMessage{
		Type:          "sync_notify",
		Message:       tableName,
		AgentID:       agentID,
		DeviceID:      sourceDeviceID,
		PolicyVersion: policy.Version,
		Timestamp:     time.Now().Unix(),
	})
}

// NotifyGlobalAppEvent 向所有在线登录用户广播公共资源失效事件。
// 拒绝理由属于上传者隐私，即使调用方误传也必须在这里剥离。
func (h *SyncHub) NotifyGlobalAppEvent(event AppEvent) {
	event.Reason = ""
	h.mu.RLock()
	clients := h.collectAllClientsLocked()
	h.mu.RUnlock()
	h.sendToClients(clients, appEventMessage(event))
}

// NotifyUserAppEvent 向指定用户的全部在线设备发送定向事件。
func (h *SyncHub) NotifyUserAppEvent(userID uint, event AppEvent) {
	h.mu.RLock()
	clients := h.collectClientsLocked(userID, "")
	h.mu.RUnlock()
	h.sendToClients(clients, appEventMessage(event))
}

// NotifyReady 明确确认 WebSocket 已完成鉴权和 Hub 注册。
func (h *SyncHub) NotifyReady(client *SyncClient) {
	h.sendToClients([]*SyncClient{client}, SyncMessage{
		Type:        "ready",
		SyncEnabled: client.SyncEnabled,
		Timestamp:   time.Now().Unix(),
	})
}

func appEventMessage(event AppEvent) SyncMessage {
	timestamp := event.Timestamp
	if timestamp == 0 {
		timestamp = time.Now().Unix()
	}
	return SyncMessage{
		Type:         "app_event",
		Scope:        event.Scope,
		ResourceType: event.ResourceType,
		ResourceID:   event.ResourceID,
		Status:       event.Status,
		Reason:       event.Reason,
		Version:      event.Version,
		EventID:      event.EventID,
		Timestamp:    timestamp,
	}
}

// collectClientsLocked 收集指定用户的所有在线客户端（调用方需持锁）
// excludeDeviceID 为空时不排除任何设备
func (h *SyncHub) collectClientsLocked(userID uint, excludeDeviceID string) []*SyncClient {
	src := h.users[userID]
	clients := make([]*SyncClient, 0, len(src))
	for c := range src {
		if excludeDeviceID != "" && c.DeviceID == excludeDeviceID {
			continue
		}
		clients = append(clients, c)
	}
	return clients
}

func (h *SyncHub) collectAllClientsLocked() []*SyncClient {
	clients := make([]*SyncClient, 0, len(h.clients))
	for client := range h.clients {
		clients = append(clients, client)
	}
	return clients
}

// sendToClients 向客户端列表发送消息（无需持锁，减少锁持有时间）
func (h *SyncHub) sendToClients(clients []*SyncClient, msg SyncMessage) {
	if len(clients) == 0 {
		return
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	if msg.Type == "app_event" {
		for _, c := range clients {
			c.queueAppEvent(msg.Scope, data)
		}
		return
	}
	for _, c := range clients {
		select {
		case c.Send <- data:
		default:
			// 发送缓冲区满，跳过
		}
	}
}

// Hub 全局 Hub 实例
var Hub *SyncHub

// InitSyncHub 初始化全局 Hub
func InitSyncHub() {
	Hub = NewSyncHub()
	go Hub.Run()
}

// ReadPump 客户端读取循环（每个连接一个 goroutine）
func (c *SyncClient) ReadPump() {
	defer func() {
		c.Hub.UnregisterClient(c)
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(4096)
	c.Conn.SetReadDeadline(time.Now().Add(70 * time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(70 * time.Second))
		return nil
	})

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		var msg SyncMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			continue
		}
		switch msg.Type {
		case "chat_lock":
			if errMsg := c.Hub.HandleChatLock(c, msg); errMsg != nil {
				data, _ := json.Marshal(errMsg)
				select {
				case c.Send <- data:
				default:
				}
			}
		case "chat_unlock":
			c.Hub.HandleChatUnlock(c, msg)
		case "ping":
			pong := SyncMessage{Type: "pong", Timestamp: time.Now().Unix()}
			data, _ := json.Marshal(pong)
			select {
			case c.Send <- data:
			default:
			}
		}
	}
}

// WritePump 客户端写入循环（每个连接一个 goroutine）
func (c *SyncClient) WritePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()
	wake := c.appEventWakeChannel()
	var deferredMessage []byte
	var hasDeferredMessage bool

	for {
		// App events have priority over ordinary sync messages. If several
		// updates arrived for one scope while the socket was busy, popAppEvent
		// returns only the newest one.
		if message, ok := c.popAppEvent(); ok {
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			continue
		}
		if hasDeferredMessage {
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.TextMessage, deferredMessage); err != nil {
				return
			}
			deferredMessage = nil
			hasDeferredMessage = false
			continue
		}

		select {
		case <-wake:
			continue
		case message, ok := <-c.Send:
			if !ok {
				c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			// Hold the ordinary message for one loop turn so an app event
			// queued concurrently can take precedence.
			deferredMessage = message
			hasDeferredMessage = true
		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func init() {
	// 兜底日志，防止 Hub 未初始化时 panic
	log.SetFlags(log.LstdFlags)
}
