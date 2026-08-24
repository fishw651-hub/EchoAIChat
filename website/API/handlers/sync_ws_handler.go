package handlers

import (
	"net/http"
	"net/url"
	"strings"
	"time"

	"aichat-api/config"
	"aichat-api/hub"
	"aichat-api/middleware"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// SyncWSHandler 多端同步 WebSocket 端点
type SyncWSHandler struct {
	upgrader websocket.Upgrader
}

// NewSyncWSHandler 创建实例
func NewSyncWSHandler() *SyncWSHandler {
	return &SyncWSHandler{
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			// Origin 校验：Flutter 原生端不带 Origin（放行）；
			// 浏览器端必须落在 CORS 白名单域内，防止任意站点跨站建连
			CheckOrigin: func(r *http.Request) bool {
				origin := r.Header.Get("Origin")
				if origin == "" {
					return true
				}
				if config.AppConfig == nil {
					return false
				}
				originURL, err := url.Parse(origin)
				if err != nil {
					return false
				}
				for _, allowed := range config.AppConfig.CORS.AllowedOrigins {
					if allowedURL, err := url.Parse(allowed); err == nil &&
						strings.EqualFold(allowedURL.Host, originURL.Host) {
						return true
					}
				}
				return false
			},
		},
	}
}

// IssueTicket issues a short-lived, one-use browser WebSocket ticket.
func (h *SyncWSHandler) IssueTicket(c *gin.Context) {
	ticket, err := services.IssueWSTicket(c.GetUint("user_id"))
	if err != nil {
		utils.Internal(c, "无法创建 WebSocket ticket")
		return
	}
	utils.Success(c, gin.H{"ticket": ticket, "expires_in": 60})
}

// HandleWS GET /api/v1/sync/ws?ticket=<one-use-ticket>&device_id=<device_id>&device_name=<name>
// WebSocket 连接入口。所有已登录用户可接收 app_event；同步和聊天锁仍需订阅。
func (h *SyncWSHandler) HandleWS(c *gin.Context) {
	ticket := c.Query("ticket")
	userID, ticketOK := services.ConsumeWSTicket(ticket)
	tokenVersion := -1
	if !ticketOK {
		auth := strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
		claims, err := utils.ParseToken(auth)
		if err != nil {
			utils.Unauthorized(c, "WebSocket ticket 无效或已过期")
			return
		}
		userID = claims.UserID
		tokenVersion = claims.TokenVersion
		if ticket != "" {
			utils.Unauthorized(c, "WebSocket ticket 无效或已过期")
			return
		}
		if auth == "" {
			utils.Unauthorized(c, "缺少 Authorization")
			return
		}
	}

	// 令牌版本校验：改密/重置密码后旧 token 不得再建立同步连接
	wsUser, err := services.FindUserByID(userID)
	if err != nil || wsUser == nil || wsUser.Status != 1 {
		utils.Unauthorized(c, "登录状态已变更，请重新登录")
		return
	}
	if tokenVersion >= 0 && wsUser.TokenVersion != tokenVersion {
		utils.Unauthorized(c, "登录状态已变更，请重新登录")
		return
	}

	deviceID := c.Query("device_id")
	deviceName := c.Query("device_name")
	if deviceID == "" {
		utils.BadRequest(c, "缺少 device_id")
		return
	}

	// 订阅和设备注册只决定同步权限，不能阻断免费用户的应用事件连接。
	syncEnabled := false
	if middleware.HasSyncSubscription(userID) {
		if existing, err := services.FindDevice(userID, deviceID); err == nil && existing != nil {
			syncEnabled = true
			deviceName = existing.DeviceName
			_ = services.UpdateDeviceByID(existing.ID, map[string]interface{}{
				"LastActiveAt": time.Now(),
			})
		}
	}

	// 升级为 WebSocket
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return // Upgrade 已写入 HTTP 错误响应
	}

	// 创建客户端并注册到 Hub
	client := &hub.SyncClient{
		UserID:      userID,
		DeviceID:    deviceID,
		DeviceName:  deviceName,
		SyncEnabled: syncEnabled,
		Conn:        conn,
		Send:        make(chan []byte, 64),
		Hub:         hub.Hub,
	}

	hub.Hub.RegisterClient(client)
	hub.Hub.NotifyReady(client)

	go client.WritePump()
	go client.ReadPump()
}
