package routes

import (
	"compress/gzip"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"aichat-api/config"
	"aichat-api/handlers"
	"aichat-api/middleware"
	"aichat-api/services"

	"github.com/gin-gonic/gin"
)

const minimumSecureClientVersionCode = 67

// contentTypeFixer 修复 Windows 服务器上 FileServer 对 .js/.mjs/.wasm 等返回 text/plain 的问题
// 浏览器因 X-Content-Type-Options: nosniff 拒绝执行 text/plain 的脚本
func contentTypeFixer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ext := strings.ToLower(filepath.Ext(r.URL.Path))
		switch ext {
		case ".js", ".mjs":
			w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
		case ".wasm":
			w.Header().Set("Content-Type", "application/wasm")
		case ".json":
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
		case ".css":
			w.Header().Set("Content-Type", "text/css; charset=utf-8")
		case ".html", ".htm":
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
		}
		next.ServeHTTP(w, r)
	})
}

// gzipResponseWriter 包装 ResponseWriter，将写入的数据通过 gzip 压缩
type gzipResponseWriter struct {
	http.ResponseWriter
	gz *gzip.Writer
}

func (g *gzipResponseWriter) Write(b []byte) (int, error) {
	return g.gz.Write(b)
}

func (g *gzipResponseWriter) WriteHeader(code int) {
	// 压缩后 Content-Length 不再准确，必须删除
	g.Header().Del("Content-Length")
	g.ResponseWriter.WriteHeader(code)
}

// gzipHandler 对文本类静态资源进行 gzip 压缩
// 只压缩 .js/.mjs/.css/.html/.json/.svg/.xml，跳过已压缩的二进制文件（.wasm/.png/.jpg 等）
// main.dart.js 5.8MB → gzip 后 ~1.5MB，大幅减少传输时间
func gzipHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 客户端不支持 gzip → 直接透传
		if !strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
			next.ServeHTTP(w, r)
			return
		}

		ext := strings.ToLower(filepath.Ext(r.URL.Path))

		// 只对文本类文件压缩
		var shouldCompress bool
		switch ext {
		case ".js", ".mjs", ".css", ".html", ".htm", ".json", ".svg", ".xml":
			shouldCompress = true
		}
		if !shouldCompress {
			next.ServeHTTP(w, r)
			return
		}

		// 设置 gzip 响应头
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Add("Vary", "Accept-Encoding")
		w.Header().Del("Content-Length")

		gz := gzip.NewWriter(w)
		defer gz.Close()

		next.ServeHTTP(&gzipResponseWriter{ResponseWriter: w, gz: gz}, r)
	})
}

func publicCacheHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ext := strings.ToLower(filepath.Ext(r.URL.Path))
		switch ext {
		case "", ".html", ".htm":
			w.Header().Set("Cache-Control", "public, max-age=0, must-revalidate")
		case ".png", ".jpg", ".jpeg", ".webp", ".svg":
			w.Header().Set("Cache-Control", "public, max-age=604800")
		default:
			w.Header().Set("Cache-Control", "public, max-age=86400")
		}
		next.ServeHTTP(w, r)
	})
}

func SetupPublicWebRoutes(r *gin.Engine, root string) {
	landingFS := http.FileServer(http.Dir(filepath.Join(root, "landing")))
	landingHandler := gin.WrapH(publicCacheHandler(gzipHandler(contentTypeFixer(http.StripPrefix("/landing", landingFS)))))
	landingGuard := middleware.MaintenanceGuard(middleware.MaintenancePageLanding)
	r.Match([]string{http.MethodGet, http.MethodHead}, "/landing/*filepath", landingGuard, landingHandler)

	permanentLandingRedirect := func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/landing/")
	}
	r.Match([]string{http.MethodGet, http.MethodHead}, "/landing", landingGuard, permanentLandingRedirect)
	r.Match([]string{http.MethodGet, http.MethodHead}, "/", landingGuard, permanentLandingRedirect)

	r.StaticFile("/robots.txt", filepath.Join(root, "robots.txt"))
	r.StaticFile("/sitemap.xml", filepath.Join(root, "sitemap.xml"))

	baiduVerification := filepath.Join(root, "baidu_verify_codeva-5ndb2lJTnZ.html")
	if _, err := os.Stat(baiduVerification); err == nil {
		r.StaticFile("/baidu_verify_codeva-5ndb2lJTnZ.html", baiduVerification)
	}
	bingVerification := filepath.Join(root, "BingSiteAuth.xml")
	if _, err := os.Stat(bingVerification); err == nil {
		r.StaticFile("/BingSiteAuth.xml", bingVerification)
	}
}

func SetupRoutes(r *gin.Engine) {
	adminFS := http.FileServer(http.Dir("./admin"))
	r.GET("/admin/*filepath", middleware.MaintenanceGuard(middleware.MaintenancePageAdmin), gin.WrapH(gzipHandler(contentTypeFixer(http.StripPrefix("/admin", adminFS)))))
	r.GET("/admin", func(c *gin.Context) {
		c.Redirect(302, "/admin/")
	})

	// Flutter Web 静态文件服务
	webFS := http.FileServer(http.Dir("./web"))
	r.GET("/web/*filepath", gin.WrapH(gzipHandler(contentTypeFixer(http.StripPrefix("/web", webFS)))))
	r.GET("/web", func(c *gin.Context) {
		c.Redirect(302, "/web/")
	})

	r.Static("/uploads", "./uploads")

	SetupPublicWebRoutes(r, ".")

	api := r.Group("/api/v1")
	api.Use(middleware.DomainBinding(func() []string {
		if config.AppConfig == nil {
			return nil
		}
		return config.AppConfig.Server.DomainWhitelist
	}))
	{
		authHandler := handlers.NewAuthHandler()
		chatHandler := handlers.NewChatHandler()
		paymentHandler := handlers.NewPaymentHandler()
		updateHandler := &handlers.UpdateHandler{}
		activityHandler := &handlers.ActivityHandler{}
		ifdianHandler := handlers.NewIfdianHandler()
		userAgentHandler := &handlers.UserAgentHandler{}

		auth := api.Group("/auth")
		{
			auth.POST("/register", middleware.LoginRateLimit(), authHandler.Register)
			auth.POST("/login", middleware.LoginRateLimit(), authHandler.Login)
			auth.POST("/refresh", authHandler.Refresh)
			auth.GET("/device-status", authHandler.DeviceStatus)

			// 邮箱验证码 / 忘记密码
			emailHandler := &handlers.EmailHandler{}
			auth.POST("/send-code", middleware.LoginRateLimit(), emailHandler.SendCode)
			auth.POST("/register-with-code", middleware.LoginRateLimit(), emailHandler.RegisterWithCode)
			auth.POST("/reset-password", middleware.LoginRateLimit(), emailHandler.ResetPassword)
		}

		api.GET("/models", chatHandler.GetModels)

		update := api.Group("/update")
		{
			update.GET("/check", updateHandler.CheckUpdate)
			update.GET("/download/:id", updateHandler.Download)
			update.GET("/versions", updateHandler.ListVersions)
		}

		api.GET("/activities", activityHandler.ListActive)

		ifdian := api.Group("/payment/ifdian")
		{
			ifdian.GET("/plans", ifdianHandler.PublicPlans)
			ifdian.POST("/webhook", ifdianHandler.Webhook)
		}

		payment := api.Group("/payment")
		{
			payment.POST("/notify", paymentHandler.Notify)
			payment.GET("/notify", paymentHandler.Notify)
			payment.GET("/return", paymentHandler.Return)
		}

		userGroup := api.Group("")
		userGroup.Use(middleware.AuthRequired())
		{
			userHandler := &handlers.UserHandler{}
			networkAgentHandler := &handlers.NetworkAgentHandler{}
			networkGroupHandler := &handlers.NetworkGroupHandler{}
			quotaHandler := &handlers.QuotaHandler{}

			userGroup.GET("/user/profile", authHandler.GetProfile)
			userGroup.PUT("/user/profile", authHandler.UpdateProfile)
			userGroup.PUT("/user/password", authHandler.ChangePassword)
			userGroup.POST("/user/avatar", authHandler.UploadAvatar)
			userGroup.GET("/user/balance", userHandler.GetBalance)
			userGroup.POST("/user/daily-allowance/refresh", userHandler.RefreshDailyAllowance)
			userGroup.GET("/user/subscriptions", userHandler.GetSubscriptions)
			userGroup.GET("/user/usage", userHandler.GetUsageHistory)

			// 功能配额（OCR 识别、真实回复）
			secureClient := middleware.RequireClientVersion(minimumSecureClientVersionCode)
			userGroup.GET("/quota/usage", secureClient, quotaHandler.GetUsage)
			userGroup.POST("/quota/consume", secureClient, quotaHandler.Consume)
			userGroup.POST("/quota/proactive/claim", secureClient, quotaHandler.ClaimProactiveCare)
			userGroup.POST("/quota/proactive/commit", secureClient, quotaHandler.CommitProactiveCare)
			userGroup.POST("/quota/proactive/release", secureClient, quotaHandler.ReleaseProactiveCare)

			// 网络市场 - 智能体
			userGroup.GET("/network/tags", networkAgentHandler.GetPublicTags)
			userGroup.GET("/network/agents", networkAgentHandler.ListAgents)
			userGroup.GET("/network/agents/:id", networkAgentHandler.GetDetail)
			userGroup.POST("/network/agents/:id/download", networkAgentHandler.Download)
			userGroup.GET("/network/my/agents", networkAgentHandler.ListMyUploads)
			userGroup.GET("/network/my/review-statuses", networkAgentHandler.ListMyReviewStatuses)
			userGroup.POST("/network/agents", networkAgentHandler.Upload)
			userGroup.PUT("/network/agents/:id", networkAgentHandler.Edit)
			userGroup.DELETE("/network/agents/:id", networkAgentHandler.TakeDown)

			// 网络市场 - 群聊
			userGroup.GET("/network/groups", networkGroupHandler.ListGroups)
			userGroup.GET("/network/groups/:id", networkGroupHandler.GetGroupDetail)
			userGroup.POST("/network/groups/:id/download", networkGroupHandler.DownloadGroup)
			userGroup.GET("/network/my/groups", networkGroupHandler.ListMyGroups)
			userGroup.POST("/network/groups", networkGroupHandler.UploadGroup)
			userGroup.PUT("/network/groups/:id", networkGroupHandler.EditGroup)
			userGroup.DELETE("/network/groups/:id", networkGroupHandler.TakeDownGroup)

			userGroup.GET("/user/agents", userAgentHandler.ListMyAgents)
			userGroup.POST("/user/agents", userAgentHandler.SaveAgent)
			userGroup.DELETE("/user/agents/:id", userAgentHandler.DeleteAgent)

			// 分享智能体（6 位数字码，20 分钟有效）
			shareHandler := &handlers.ShareHandler{}
			userGroup.POST("/user/share/agent", shareHandler.CreateShare)
			userGroup.POST("/user/share/redeem", shareHandler.RedeemShare)

			userGroup.POST("/chat/completions", secureClient, chatHandler.ChatCompletions)
			userGroup.POST("/chat/completions/stream", secureClient, chatHandler.ChatCompletionsStream)

			userGroup.GET("/plans", paymentHandler.GetPlans)
			userGroup.GET("/payment/order/:orderNo", paymentHandler.GetOrderStatus)
			userGroup.POST("/payment/subscribe", paymentHandler.Subscribe)
			userGroup.POST("/payment/zero-drop", paymentHandler.ZeroDrop)
			userGroup.POST("/payment/ifdian/verify", ifdianHandler.Verify)

			userGroup.GET("/user/subscription", paymentHandler.GetUserSubscription)

			// 用户反馈
			feedbackHandler := &handlers.FeedbackHandler{}
			userGroup.POST("/feedback", feedbackHandler.Create)
			userGroup.GET("/feedback", feedbackHandler.ListMine)

			// 弹窗公告（用户端拉取当前生效公告）
			announcementHandler := &handlers.AnnouncementHandler{}
			userGroup.GET("/announcements/active", announcementHandler.ListActive)

			// 多端同步（仅订阅用户可用）
			syncHandler := &handlers.SyncHandler{}
			syncGroup := userGroup.Group("/sync")
			syncGroup.Use(secureClient, middleware.RequireSyncSubscription())
			{
				backgroundPressure := middleware.BackgroundPressure(services.DefaultBackgroundLimiter())
				policyHandler := &handlers.SyncPolicyHandler{}
				syncGroup.GET("/policy", policyHandler.Get)
				syncGroup.PUT("/policy", policyHandler.Update)
				syncV2Handler := &handlers.SyncV2Handler{}
				syncGroup.POST("/v2/preview", backgroundPressure, syncV2Handler.Preview)
				syncGroup.POST("/v2/run", backgroundPressure, syncV2Handler.Run)
				syncGroup.GET("/status", syncHandler.GetStatus)
				syncGroup.GET("/all", backgroundPressure, syncHandler.DownloadAll)
				syncGroup.POST("/all", backgroundPressure, syncHandler.UploadAll)
				syncGroup.DELETE("/cloud", backgroundPressure, syncHandler.DeleteCloudCopy)
				// 注意：/tombstones 的 GET/POST 由 /:table 通配符处理（table="tombstones"）
				// 只保留 DELETE 静态路由（因为没有 DELETE /:table）
				syncGroup.DELETE("/tombstones", syncHandler.ClearTombstones)

				// 设备管理
				deviceHandler := &handlers.DeviceHandler{}
				syncGroup.POST("/devices/register", deviceHandler.RegisterDevice)
				syncGroup.GET("/devices", deviceHandler.ListDevices)
				syncGroup.PUT("/devices/:device_id/role", deviceHandler.SetDeviceRole)
				syncGroup.PUT("/devices/:device_id/name", deviceHandler.UpdateDeviceName)
				syncGroup.DELETE("/devices/:device_id", deviceHandler.DeleteDevice)
				syncGroup.PUT("/devices/full_sync", deviceHandler.SetFullSync)

				syncGroup.GET("/:table", backgroundPressure, syncHandler.DownloadTable)
				syncGroup.POST("/:table", backgroundPressure, syncHandler.UploadTable)
			}

			// WebSocket 端点（独立注册，不走常规中间件，handler 内部自行验证 token + 订阅）
			wsHandler := handlers.NewSyncWSHandler()
			wsVersion := middleware.RequireClientVersion(minimumSecureClientVersionCode)
			api.GET("/sync/ws/ticket", middleware.AuthRequired(), wsVersion, wsHandler.IssueTicket)
			api.GET("/sync/ws", wsVersion, wsHandler.HandleWS)
		}

		adminGroup := api.Group("/admin")
		adminGroup.Use(middleware.AuthRequired(), middleware.AdminRequired())
		{
			adminHandler := &handlers.AdminHandler{}
			configHandler := &handlers.ConfigHandler{}
			planHandler := &handlers.PlanHandler{}

			adminGroup.GET("/dashboard", adminHandler.Dashboard)

			adminGroup.PUT("/password", adminHandler.ChangePassword)

			adminGroup.GET("/domain-config", adminHandler.GetDomainConfig)
			adminGroup.PUT("/domain-config", adminHandler.UpdateDomainConfig)

			adminGroup.GET("/maintenance-config", adminHandler.GetMaintenanceConfig)
			adminGroup.PUT("/maintenance-config", adminHandler.UpdateMaintenanceConfig)

			adminGroup.GET("/chat-stream-config", adminHandler.GetChatStreamConfig)
			adminGroup.PUT("/chat-stream-config", adminHandler.UpdateChatStreamConfig)

			adminGroup.GET("/users", adminHandler.ListUsers)
			adminGroup.POST("/users", adminHandler.CreateUser)
			adminGroup.GET("/users/:id", adminHandler.GetUser)
			adminGroup.PUT("/users/:id", adminHandler.UpdateUser)
			adminGroup.DELETE("/users/:id", adminHandler.DeleteUser)
			adminGroup.POST("/users/:id/reset-test", adminHandler.ResetUserQuotaTest)
			adminGroup.GET("/users/:id/subscriptions", adminHandler.GetUserSubscriptions)
			adminGroup.POST("/users/:id/subscription", adminHandler.AssignSubscription)

			// 网络市场管理端
			networkAdminHandler := &handlers.NetworkAdminHandler{}
			adminGroup.GET("/network/agents", networkAdminHandler.ListAgents)
			adminGroup.GET("/network/agents/:id", networkAdminHandler.AdminGetAgent)
			adminGroup.POST("/network/agents/:id/approve", networkAdminHandler.ApproveAgent)
			adminGroup.POST("/network/agents/:id/reject", networkAdminHandler.RejectAgent)
			adminGroup.PUT("/network/agents/:id", networkAdminHandler.AdminEditAgent)
			adminGroup.DELETE("/network/agents/:id", networkAdminHandler.AdminDeleteAgent)
			adminGroup.GET("/network/groups", networkAdminHandler.ListGroups)
			adminGroup.GET("/network/groups/:id", networkAdminHandler.AdminGetGroup)
			adminGroup.POST("/network/groups/:id/approve", networkAdminHandler.ApproveGroup)
			adminGroup.POST("/network/groups/:id/reject", networkAdminHandler.RejectGroup)
			adminGroup.PUT("/network/groups/:id", networkAdminHandler.AdminEditGroup)
			adminGroup.DELETE("/network/groups/:id", networkAdminHandler.AdminDeleteGroup)
			adminGroup.GET("/network/preset-tags", networkAdminHandler.GetPresetTags)
			adminGroup.PUT("/network/preset-tags", networkAdminHandler.UpdatePresetTags)

			// AI 内容审核（网络市场）
			networkAiReviewHandler := &handlers.NetworkAiReviewHandler{}
			adminGroup.GET("/ai-review-config", networkAiReviewHandler.GetConfig)
			adminGroup.PUT("/ai-review-config", networkAiReviewHandler.UpdateConfig)
			adminGroup.POST("/network/agents/:id/ai-review", networkAiReviewHandler.ReviewAgent)
			adminGroup.POST("/network/groups/:id/ai-review", networkAiReviewHandler.ReviewGroup)

			adminGroup.GET("/api-keys", configHandler.ListAPIKeys)
			adminGroup.POST("/api-keys", configHandler.CreateAPIKey)
			adminGroup.PUT("/api-keys/:id", configHandler.UpdateAPIKey)
			adminGroup.DELETE("/api-keys/:id", configHandler.DeleteAPIKey)

			adminGroup.GET("/model-prices", configHandler.ListModelPrices)
			adminGroup.POST("/model-prices", configHandler.CreateModelPrice)
			adminGroup.PUT("/model-prices/:id", configHandler.UpdateModelPrice)
			adminGroup.PUT("/model-prices/:id/status", configHandler.UpdateModelPriceStatus)
			adminGroup.DELETE("/model-prices/:id", configHandler.DeleteModelPrice)
			adminGroup.POST("/model-prices/sync", configHandler.SyncModels)
			adminGroup.POST("/models/fetch-remote", configHandler.FetchRemoteModels)
			adminGroup.GET("/time-of-use-pricing", configHandler.GetTimeOfUsePricing)
			adminGroup.PUT("/time-of-use-pricing", configHandler.UpdateTimeOfUsePricing)

			adminGroup.GET("/plans", planHandler.ListPlans)
			adminGroup.POST("/plans", planHandler.CreatePlan)
			adminGroup.PUT("/plans/:id", planHandler.UpdatePlan)
			adminGroup.DELETE("/plans/:id", planHandler.DeletePlan)

			adminGroup.GET("/config", planHandler.GetSystemConfig)
			adminGroup.PUT("/config", planHandler.UpdateSystemConfig)
			adminGroup.GET("/tls-config", configHandler.GetTLSConfig)
			adminGroup.PUT("/tls-config", configHandler.UpdateTLSConfig)

			adminGroup.GET("/payment-config", planHandler.GetPaymentConfig)
			adminGroup.PUT("/payment-config", planHandler.UpdatePaymentConfig)

			adminGroup.GET("/orders", planHandler.ListOrders)

			adminGroup.GET("/versions", updateHandler.AdminListVersions)
			adminGroup.POST("/versions", updateHandler.UploadVersion)
			adminGroup.PUT("/versions/:id", updateHandler.UpdateVersion)
			adminGroup.DELETE("/versions/:id", updateHandler.DeleteVersion)

			adminGroup.GET("/activities", activityHandler.AdminList)
			adminGroup.POST("/activities", activityHandler.Create)
			adminGroup.PUT("/activities/:id", activityHandler.Update)
			adminGroup.DELETE("/activities/:id", activityHandler.Delete)
			adminGroup.GET("/activities/:id/rules", activityHandler.GetRules)
			adminGroup.PUT("/activities/:id/rules", activityHandler.UpdateRules)

			// 弹窗公告管理
			announcementAdminHandler := &handlers.AnnouncementHandler{}
			adminGroup.GET("/announcements", announcementAdminHandler.AdminList)
			adminGroup.POST("/announcements", announcementAdminHandler.Create)
			adminGroup.PUT("/announcements/:id", announcementAdminHandler.Update)
			adminGroup.DELETE("/announcements/:id", announcementAdminHandler.Delete)

			adminGroup.GET("/ifdian/config", ifdianHandler.GetConfig)
			adminGroup.PUT("/ifdian/config", ifdianHandler.SaveConfig)
			adminGroup.POST("/ifdian/sync-plans", ifdianHandler.SyncPlans)
			adminGroup.GET("/ifdian/plans", ifdianHandler.ListPlans)
			adminGroup.PUT("/ifdian/plans/:id/mapping", ifdianHandler.UpdateMapping)
			adminGroup.GET("/ifdian/records", ifdianHandler.ListRecords)

			// SMTP 邮件配置
			emailAdminHandler := &handlers.EmailHandler{}
			adminGroup.GET("/smtp-config", emailAdminHandler.GetSMTPConfig)
			adminGroup.PUT("/smtp-config", emailAdminHandler.UpdateSMTPConfig)
			adminGroup.POST("/smtp-config/test", emailAdminHandler.TestSMTP)
			adminGroup.GET("/email-templates", emailAdminHandler.GetEmailTemplates)
			adminGroup.PUT("/email-templates", emailAdminHandler.UpdateEmailTemplates)
			adminGroup.POST("/email/notify", emailAdminHandler.SendNotificationEmail)

			// 用户反馈管理
			feedbackHandler := &handlers.FeedbackHandler{}
			adminGroup.GET("/feedback", feedbackHandler.AdminList)
			adminGroup.PUT("/feedback/:id", feedbackHandler.AdminReply)
			adminGroup.DELETE("/feedback/:id", feedbackHandler.AdminDelete)

			adminGroup.GET("/audit-logs", adminHandler.ListAuditLogs)
			adminGroup.GET("/audit-logs/stats", adminHandler.AuditLogStats)
		}
	}

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
}
