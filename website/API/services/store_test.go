package services

import (
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

// setupStoreTestDB 初始化独立临时库，覆盖 store 薄封装的读写往返。
func setupStoreTestDB(t *testing.T) {
	t.Helper()
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
}

func TestUserStoreFindAndUpdate(t *testing.T) {
	setupStoreTestDB(t)

	if u, err := FindUserByID(999); err != nil || u != nil {
		t.Fatalf("missing user = (%v, %v), want (nil, nil)", u, err)
	}
	if u, err := FindUserByUsername("nobody"); err != nil || u != nil {
		t.Fatalf("missing username = (%v, %v), want (nil, nil)", u, err)
	}
	if u, err := FindUserByEmail("nobody@example.com"); err != nil || u != nil {
		t.Fatalf("missing email = (%v, %v), want (nil, nil)", u, err)
	}

	user := &models.User{Username: "alice", Email: "alice@example.com", Role: "user", Status: 1}
	if err := InsertUser(user); err != nil {
		t.Fatalf("InsertUser: %v", err)
	}

	byID, err := FindUserByID(user.ID)
	if err != nil || byID == nil || byID.Username != "alice" {
		t.Fatalf("FindUserByID = (%v, %v)", byID, err)
	}
	byName, err := FindUserByUsername("alice")
	if err != nil || byName == nil || byName.ID != user.ID {
		t.Fatalf("FindUserByUsername = (%v, %v)", byName, err)
	}
	byEmail, err := FindUserByEmail("alice@example.com")
	if err != nil || byEmail == nil || byEmail.ID != user.ID {
		t.Fatalf("FindUserByEmail = (%v, %v)", byEmail, err)
	}

	if err := UpdateUserByID(user.ID, map[string]interface{}{"Nickname": "爱丽丝"}); err != nil {
		t.Fatalf("UpdateUserByID: %v", err)
	}
	if err := IncrementUserField(user.ID, "OcrUsedToday", 2); err != nil {
		t.Fatalf("IncrementUserField: %v", err)
	}
	updated, err := FindUserByID(user.ID)
	if err != nil || updated == nil {
		t.Fatalf("FindUserByID after update = (%v, %v)", updated, err)
	}
	if updated.Nickname != "爱丽丝" || updated.OcrUsedToday != 2 {
		t.Fatalf("updated = %+v", updated)
	}

	count, err := CountUsers()
	if err != nil || count != 1 {
		t.Fatalf("CountUsers = (%d, %v), want (1, nil)", count, err)
	}
	if users := ListUsers("ID desc"); len(users) != 1 {
		t.Fatalf("ListUsers len = %d, want 1", len(users))
	}

	if !DeleteUserByID(user.ID) {
		t.Fatal("DeleteUserByID = false, want true")
	}
	if u, err := FindUserByID(user.ID); err != nil || u != nil {
		t.Fatalf("deleted user = (%v, %v), want (nil, nil)", u, err)
	}
}

func TestSystemConfigStoreSaveUpsert(t *testing.T) {
	setupStoreTestDB(t)

	if sc, err := FindSystemConfig("k1"); err != nil || sc != nil {
		t.Fatalf("missing config = (%v, %v), want (nil, nil)", sc, err)
	}

	if err := SaveSystemConfig("k1", "v1", "d1"); err != nil {
		t.Fatalf("SaveSystemConfig insert: %v", err)
	}
	if err := SaveSystemConfig("k1", "v2", "d2"); err != nil {
		t.Fatalf("SaveSystemConfig update: %v", err)
	}

	sc, err := FindSystemConfig("k1")
	if err != nil || sc == nil {
		t.Fatalf("FindSystemConfig = (%v, %v)", sc, err)
	}
	if sc.Value != "v2" || sc.Description != "d1" {
		t.Fatalf("config = %+v, want Value=v2 Description=d1（upsert 只更新 Value）", sc)
	}
	if all := ListSystemConfigs(); len(all) != 1 {
		t.Fatalf("ListSystemConfigs len = %d, want 1", len(all))
	}
}

func TestModelPriceStoreRoundTrip(t *testing.T) {
	setupStoreTestDB(t)

	if p, err := FindModelPriceByModelID("m-x"); err != nil || p != nil {
		t.Fatalf("missing price = (%v, %v), want (nil, nil)", p, err)
	}

	price := &models.ModelPrice{ModelID: "m-x", ModelName: "M X", Status: 1}
	if err := InsertModelPrice(price); err != nil {
		t.Fatalf("InsertModelPrice: %v", err)
	}

	byModel, err := FindModelPriceByModelID("m-x")
	if err != nil || byModel == nil || byModel.ID != price.ID {
		t.Fatalf("FindModelPriceByModelID = (%v, %v)", byModel, err)
	}
	byID, err := FindModelPriceByID(price.ID)
	if err != nil || byID == nil || byID.ModelID != "m-x" {
		t.Fatalf("FindModelPriceByID = (%v, %v)", byID, err)
	}

	if err := UpdateModelPriceByID(price.ID, map[string]interface{}{"Status": 0}); err != nil {
		t.Fatalf("UpdateModelPriceByID: %v", err)
	}
	updated, _ := FindModelPriceByID(price.ID)
	if updated == nil || updated.Status != 0 {
		t.Fatalf("updated = %+v, want Status=0", updated)
	}
	if all := ListModelPrices(); len(all) != 1 {
		t.Fatalf("ListModelPrices len = %d, want 1", len(all))
	}
	if !DeleteModelPriceByID(price.ID) {
		t.Fatal("DeleteModelPriceByID = false, want true")
	}
}

func TestNetworkStoreSearchAndCounts(t *testing.T) {
	setupStoreTestDB(t)

	agents := []models.NetworkAgent{
		{UploaderID: 1, UploaderName: "alice", Name: "小助手", Description: "温柔陪伴", Status: "approved", Version: 1},
		{UploaderID: 1, UploaderName: "alice", Name: "反派", Description: "危险角色", Status: "pending", Version: 1},
		{UploaderID: 2, UploaderName: "bob", Name: "助手二号", Status: "approved", Version: 1},
	}
	for i := range agents {
		if err := InsertNetworkAgent(&agents[i]); err != nil {
			t.Fatalf("InsertNetworkAgent: %v", err)
		}
	}

	counts, err := NetworkAgentStatusCounts()
	if err != nil {
		t.Fatalf("NetworkAgentStatusCounts: %v", err)
	}
	if counts["approved"] != 2 || counts["pending"] != 1 || counts["rejected"] != 0 || counts["taken_down"] != 0 {
		t.Fatalf("counts = %v", counts)
	}

	// 公开搜索：仅 approved + 关键词命中 Name/Description/Tags 任一
	items, total, err := PublicSearchNetworkAgents("助手", nil, "CreatedAt desc", 0, 20)
	if err != nil {
		t.Fatalf("PublicSearchNetworkAgents: %v", err)
	}
	if total != 2 || len(items) != 2 {
		t.Fatalf("public search = (%d, %d), want (2, 2)", total, len(items))
	}

	// 管理端搜索：状态过滤 + 上传者名命中
	adminItems, adminTotal, err := AdminSearchNetworkAgents("pending", "alice", 0, 20)
	if err != nil {
		t.Fatalf("AdminSearchNetworkAgents: %v", err)
	}
	if adminTotal != 1 || len(adminItems) != 1 || adminItems[0].Name != "反派" {
		t.Fatalf("admin search = (%d, %v)", adminTotal, adminItems)
	}

	if err := IncrementNetworkAgentDownloads(agents[0].ID); err != nil {
		t.Fatalf("IncrementNetworkAgentDownloads: %v", err)
	}
	got, err := FindNetworkAgentByID(agents[0].ID)
	if err != nil || got == nil || got.DownloadCount != 1 {
		t.Fatalf("FindNetworkAgentByID = (%v, %v), want DownloadCount=1", got, err)
	}

	// 条件更新：仅 pending + 指定版本才生效
	if err := UpdatePendingNetworkAgentVersion(agents[0].ID, 1, map[string]interface{}{"Status": "rejected"}); err != nil {
		t.Fatalf("UpdatePendingNetworkAgentVersion: %v", err)
	}
	got, _ = FindNetworkAgentByID(agents[0].ID)
	if got == nil || got.Status != "approved" {
		t.Fatalf("approved 记录被条件更新误改: %+v", got)
	}
	if err := UpdatePendingNetworkAgentVersion(agents[1].ID, 1, map[string]interface{}{"Status": "rejected"}); err != nil {
		t.Fatalf("UpdatePendingNetworkAgentVersion pending: %v", err)
	}
	got, _ = FindNetworkAgentByID(agents[1].ID)
	if got == nil || got.Status != "rejected" {
		t.Fatalf("pending 记录条件更新未生效: %+v", got)
	}

	if mine := ListNetworkAgentsByUploader(1); len(mine) != 2 {
		t.Fatalf("ListNetworkAgentsByUploader len = %d, want 2", len(mine))
	}
	if !DeleteNetworkAgentByID(agents[2].ID) {
		t.Fatal("DeleteNetworkAgentByID = false, want true")
	}
}

func TestDeviceStoreLifecycle(t *testing.T) {
	setupStoreTestDB(t)

	if d, err := FindDevice(1, "dev-1"); err != nil || d != nil {
		t.Fatalf("missing device = (%v, %v), want (nil, nil)", d, err)
	}

	if err := InsertDevice(&models.Device{UserID: 1, DeviceID: "dev-1", Role: "master"}); err != nil {
		t.Fatalf("InsertDevice: %v", err)
	}
	if err := InsertDevice(&models.Device{UserID: 1, DeviceID: "dev-2", Role: "slave"}); err != nil {
		t.Fatalf("InsertDevice: %v", err)
	}

	d, err := FindDevice(1, "dev-1")
	if err != nil || d == nil || d.Role != "master" {
		t.Fatalf("FindDevice = (%v, %v)", d, err)
	}
	if n, err := CountDevicesByUser(1); err != nil || n != 2 {
		t.Fatalf("CountDevicesByUser = (%d, %v), want (2, nil)", n, err)
	}
	if n, err := CountDevicesByUserAndRole(1, "slave"); err != nil || n != 1 {
		t.Fatalf("CountDevicesByUserAndRole = (%d, %v), want (1, nil)", n, err)
	}
	if masters := ListDevicesByUserAndRole(1, "master"); len(masters) != 1 {
		t.Fatalf("ListDevicesByUserAndRole len = %d, want 1", len(masters))
	}

	if err := UpdateDeviceByID(d.ID, map[string]interface{}{"DeviceName": "主机"}); err != nil {
		t.Fatalf("UpdateDeviceByID: %v", err)
	}
	if err := UpdateDeviceByUserAndDeviceID(1, "dev-2", map[string]interface{}{"DeviceName": "副机"}); err != nil {
		t.Fatalf("UpdateDeviceByUserAndDeviceID: %v", err)
	}
	devices := ListDevicesByUser(1)
	if len(devices) != 2 {
		t.Fatalf("ListDevicesByUser len = %d, want 2", len(devices))
	}
	names := map[string]string{}
	for _, dev := range devices {
		names[dev.DeviceID] = dev.DeviceName
	}
	if names["dev-1"] != "主机" || names["dev-2"] != "副机" {
		t.Fatalf("device names = %v", names)
	}

	// SyncSetting
	if s, err := FindSyncSettingByUser(1); err != nil || s != nil {
		t.Fatalf("missing sync setting = (%v, %v), want (nil, nil)", s, err)
	}
	if err := InsertSyncSetting(&models.SyncSetting{UserID: 1, ScopeMode: "all", PolicyVersion: 1}); err != nil {
		t.Fatalf("InsertSyncSetting: %v", err)
	}
	s, err := FindSyncSettingByUser(1)
	if err != nil || s == nil || s.ScopeMode != "all" {
		t.Fatalf("FindSyncSettingByUser = (%v, %v)", s, err)
	}

	if !DeleteDeviceByID(d.ID) {
		t.Fatal("DeleteDeviceByID = false, want true")
	}
	if n, _ := CountDevicesByUser(1); n != 1 {
		t.Fatalf("CountDevicesByUser after delete = %d, want 1", n)
	}
}

func TestPlanStoreAndSubscriptions(t *testing.T) {
	setupStoreTestDB(t)

	plan := &models.SubscriptionPlan{Name: "月度", Price: 9.9, DailyQuota: 5, DurationDays: 30, Status: 1}
	if err := InsertSubscriptionPlan(plan); err != nil {
		t.Fatalf("InsertSubscriptionPlan: %v", err)
	}
	got, err := FindSubscriptionPlanByID(plan.ID)
	if err != nil || got == nil || got.Name != "月度" {
		t.Fatalf("FindSubscriptionPlanByID = (%v, %v)", got, err)
	}
	if n, err := CountSubscriptionPlans(); err != nil || n != 1 {
		t.Fatalf("CountSubscriptionPlans = (%d, %v), want (1, nil)", n, err)
	}

	sub := &models.UserSubscription{
		UserID: 7, PlanID: plan.ID, PlanName: "月度", DailyQuota: 5,
		StartedAt: "2026-01-01", ExpiresAt: "2099-01-01", Status: 1,
	}
	if err := InsertUserSubscription(sub); err != nil {
		t.Fatalf("InsertUserSubscription: %v", err)
	}

	active, err := FindActiveUserSubscription(7, plan.ID, "2026-08-17")
	if err != nil || active == nil || active.ID != sub.ID {
		t.Fatalf("FindActiveUserSubscription = (%v, %v)", active, err)
	}
	// 过期订阅查不到
	expired := &models.UserSubscription{
		UserID: 7, PlanID: plan.ID, PlanName: "月度", DailyQuota: 5,
		StartedAt: "2025-01-01", ExpiresAt: "2025-02-01", Status: 1,
	}
	if err := InsertUserSubscription(expired); err != nil {
		t.Fatalf("InsertUserSubscription expired: %v", err)
	}
	if all := ListUserSubscriptionsByUser(7); len(all) != 2 {
		t.Fatalf("ListUserSubscriptionsByUser len = %d, want 2", len(all))
	}

	if err := IncrementUserSubscriptionField(sub.ID, "OcrUsedToday", 1); err != nil {
		t.Fatalf("IncrementUserSubscriptionField: %v", err)
	}
	if err := UpdateUserSubscriptionByID(sub.ID, map[string]interface{}{"Status": 0}); err != nil {
		t.Fatalf("UpdateUserSubscriptionByID: %v", err)
	}
	active, err = FindActiveUserSubscription(7, plan.ID, "2026-08-17")
	if err != nil || active != nil {
		t.Fatalf("停用后 FindActiveUserSubscription = (%v, %v), want (nil, nil)", active, err)
	}

	if err := UpdateSubscriptionPlanByID(plan.ID, map[string]interface{}{"Price": 19.9}); err != nil {
		t.Fatalf("UpdateSubscriptionPlanByID: %v", err)
	}
	got, _ = FindSubscriptionPlanByID(plan.ID)
	if got == nil || got.Price != 19.9 {
		t.Fatalf("plan after update = %+v", got)
	}
	if plans := ListSubscriptionPlans(); len(plans) != 1 {
		t.Fatalf("ListSubscriptionPlans len = %d, want 1", len(plans))
	}
	if !DeleteSubscriptionPlanByID(plan.ID) {
		t.Fatal("DeleteSubscriptionPlanByID = false, want true")
	}
}

func TestOrderUsageActivityStores(t *testing.T) {
	setupStoreTestDB(t)

	order := &models.PaymentOrder{OrderNo: "NO1", UserID: 1, Status: "pending", Amount: 9.9}
	if err := database.Get().Register("PaymentOrder").Insert(order); err != nil {
		t.Fatalf("insert order: %v", err)
	}
	found, err := FindPaymentOrderByOrderNo("NO1")
	if err != nil || found == nil || found.UserID != 1 {
		t.Fatalf("FindPaymentOrderByOrderNo = (%v, %v)", found, err)
	}
	if missing, err := FindPaymentOrderByOrderNo("NO2"); err != nil || missing != nil {
		t.Fatalf("missing order = (%v, %v), want (nil, nil)", missing, err)
	}
	if n, err := CountPaymentOrdersByStatus("pending"); err != nil || n != 1 {
		t.Fatalf("CountPaymentOrdersByStatus = (%d, %v), want (1, nil)", n, err)
	}
	if all := ListPaymentOrders(); len(all) != 1 {
		t.Fatalf("ListPaymentOrders len = %d, want 1", len(all))
	}

	if err := database.Get().Register("UsageRecord").Insert(&models.UsageRecord{UserID: 3, Cost: 1.5, CreatedAt: time.Date(2026, 8, 17, 10, 0, 0, 0, time.UTC)}); err != nil {
		t.Fatalf("insert usage: %v", err)
	}
	if err := database.Get().Register("UsageRecord").Insert(&models.UsageRecord{UserID: 4, Cost: 2.5, CreatedAt: time.Date(2026, 8, 16, 10, 0, 0, 0, time.UTC)}); err != nil {
		t.Fatalf("insert usage: %v", err)
	}
	if records := ListUsageRecordsByUser(3); len(records) != 1 || records[0].Cost != 1.5 {
		t.Fatalf("ListUsageRecordsByUser = %v", records)
	}
	if sum, err := SumTotalUsageCost(); err != nil || sum != 4.0 {
		t.Fatalf("SumTotalUsageCost = (%v, %v), want (4.0, nil)", sum, err)
	}
	// Insert 会把 CreatedAt 覆盖为当前时间，两条记录都落在今天
	today := time.Now().Format("2006-01-02")
	if sum, err := SumUsageCostOn(today); err != nil || sum != 4.0 {
		t.Fatalf("SumUsageCostOn(today) = (%v, %v), want (4.0, nil)", sum, err)
	}
	if sum, err := SumUsageCostOn("1999-01-01"); err != nil || sum != 0 {
		t.Fatalf("SumUsageCostOn(1999-01-01) = (%v, %v), want (0, nil)", sum, err)
	}

	activity := &models.Activity{Name: "七夕", ApplyScope: "chat", Discount: 0.8, Status: 1}
	if err := InsertActivity(activity); err != nil {
		t.Fatalf("InsertActivity: %v", err)
	}
	other := &models.Activity{Name: "旧活动", ApplyScope: "chat", Discount: 0.9, Status: 1}
	if err := InsertActivity(other); err != nil {
		t.Fatalf("InsertActivity other: %v", err)
	}
	if err := DisableOtherActivitiesInScope("chat", activity.ID); err != nil {
		t.Fatalf("DisableOtherActivitiesInScope: %v", err)
	}
	all := ListActivities("")
	statusByName := map[string]int{}
	for _, a := range all {
		statusByName[a.Name] = a.Status
	}
	if statusByName["七夕"] != 1 || statusByName["旧活动"] != 0 {
		t.Fatalf("statusByName = %v", statusByName)
	}

	rule := &models.ActivityModelRule{ActivityID: activity.ID, ModelID: "m-1", InputDiscount: 0.5}
	if err := InsertActivityModelRule(rule); err != nil {
		t.Fatalf("InsertActivityModelRule: %v", err)
	}
	if rules := ListActivityModelRules(activity.ID); len(rules) != 1 {
		t.Fatalf("ListActivityModelRules len = %d, want 1", len(rules))
	}
	if !DeleteActivityModelRuleByID(rule.ID) {
		t.Fatal("DeleteActivityModelRuleByID = false, want true")
	}
	if !DeleteActivityByID(other.ID) {
		t.Fatal("DeleteActivityByID = false, want true")
	}
}

func TestFeedbackIfdianVersionAPIKeyUserAgentStores(t *testing.T) {
	setupStoreTestDB(t)

	// Feedback
	fb := &models.Feedback{UserID: 1, Username: "alice", Category: "bug", Content: "崩溃了", Contact: "x", Status: 0}
	if err := InsertFeedback(fb); err != nil {
		t.Fatalf("InsertFeedback: %v", err)
	}
	if err := UpdateFeedbackByID(fb.ID, map[string]interface{}{"Status": 2, "Reply": "已修复"}); err != nil {
		t.Fatalf("UpdateFeedbackByID: %v", err)
	}
	if all := ListFeedback(); len(all) != 1 || all[0].Status != 2 {
		t.Fatalf("ListFeedback = %v", all)
	}
	if deleted, err := DeleteFeedbackByID(fb.ID); err != nil || !deleted {
		t.Fatalf("DeleteFeedbackByID = (%v, %v), want (true, nil)", deleted, err)
	}
	if deleted, err := DeleteFeedbackByID(fb.ID); err != nil || deleted {
		t.Fatalf("DeleteFeedbackByID again = (%v, %v), want (false, nil)", deleted, err)
	}

	// Ifdian
	plan := &models.IfdianPlan{IfdianPlanID: "ifd-1", Name: "赞助", MappingType: "subscription", Status: 1}
	if err := database.Get().Register("IfdianPlan").Insert(plan); err != nil {
		t.Fatalf("insert ifdian plan: %v", err)
	}
	gotPlan, err := FindIfdianPlanByPlanID("ifd-1")
	if err != nil || gotPlan == nil || gotPlan.Name != "赞助" {
		t.Fatalf("FindIfdianPlanByPlanID = (%v, %v)", gotPlan, err)
	}
	if err := UpdateIfdianPlanByID(plan.ID, map[string]interface{}{"MappingType": "quota"}); err != nil {
		t.Fatalf("UpdateIfdianPlanByID: %v", err)
	}
	if plans := ListIfdianPlans(); len(plans) != 1 || plans[0].MappingType != "quota" {
		t.Fatalf("ListIfdianPlans = %v", plans)
	}
	record := &models.IfdianRecord{OutTradeNo: "T1", PlanID: "ifd-1"}
	if err := InsertIfdianRecord(record); err != nil {
		t.Fatalf("InsertIfdianRecord: %v", err)
	}
	if gotRecord, err := FindIfdianRecordByOutTradeNo("T1"); err != nil || gotRecord == nil {
		t.Fatalf("FindIfdianRecordByOutTradeNo = (%v, %v)", gotRecord, err)
	}
	if records := ListIfdianRecords(); len(records) != 1 {
		t.Fatalf("ListIfdianRecords len = %d, want 1", len(records))
	}

	// AppVersion
	v := &models.AppVersion{Platform: "android", Version: "1.0.0", VersionCode: 66, Status: 1}
	if err := InsertAppVersion(v); err != nil {
		t.Fatalf("InsertAppVersion: %v", err)
	}
	gotV, err := FindAppVersionByID(v.ID)
	if err != nil || gotV == nil || gotV.VersionCode != 66 {
		t.Fatalf("FindAppVersionByID = (%v, %v)", gotV, err)
	}
	if err := UpdateAppVersionByID(v.ID, map[string]interface{}{"Status": 0}); err != nil {
		t.Fatalf("UpdateAppVersionByID: %v", err)
	}
	if versions := ListAppVersions("VersionCode desc"); len(versions) != 1 || versions[0].Status != 0 {
		t.Fatalf("ListAppVersions = %v", versions)
	}
	if !DeleteAppVersionByID(v.ID) {
		t.Fatal("DeleteAppVersionByID = false, want true")
	}

	// APIKey
	key := &models.APIKey{Provider: "vision", Name: "vision", APIKeyEncrypted: "enc", IsActive: true}
	if err := InsertAPIKey(key); err != nil {
		t.Fatalf("InsertAPIKey: %v", err)
	}
	gotKey, err := FindAPIKeyByProvider("vision")
	if err != nil || gotKey == nil || gotKey.ID != key.ID {
		t.Fatalf("FindAPIKeyByProvider = (%v, %v)", gotKey, err)
	}
	if err := UpdateAPIKeyByID(key.ID, map[string]interface{}{"IsActive": false}); err != nil {
		t.Fatalf("UpdateAPIKeyByID: %v", err)
	}
	if keys := ListAPIKeys(); len(keys) != 1 || keys[0].IsActive {
		t.Fatalf("ListAPIKeys = %v", keys)
	}
	if !DeleteAPIKeyByID(key.ID) {
		t.Fatal("DeleteAPIKeyByID = false, want true")
	}

	// UserAgent
	ua := &models.UserAgent{UserID: 9, Name: "贴身助理"}
	if err := InsertUserAgent(ua); err != nil {
		t.Fatalf("InsertUserAgent: %v", err)
	}
	if err := InsertUserAgent(&models.UserAgent{UserID: 8, Name: "别人的"}); err != nil {
		t.Fatalf("InsertUserAgent other: %v", err)
	}
	if mine := ListUserAgentsByUser(9); len(mine) != 1 || mine[0].Name != "贴身助理" {
		t.Fatalf("ListUserAgentsByUser = %v", mine)
	}
	gotUA, err := FindUserAgentByID(ua.ID)
	if err != nil || gotUA == nil {
		t.Fatalf("FindUserAgentByID = (%v, %v)", gotUA, err)
	}
	if err := UpdateUserAgentByID(ua.ID, map[string]interface{}{"Name": "改名"}); err != nil {
		t.Fatalf("UpdateUserAgentByID: %v", err)
	}
	if !DeleteUserAgentByID(ua.ID) {
		t.Fatal("DeleteUserAgentByID = false, want true")
	}

}

func TestSyncStore(t *testing.T) {
	setupStoreTestDB(t)

	row := map[string]interface{}{"ClientID": "c1", "Name": "智能体"}
	upserted, err := SyncBatchUpsertByUserIDClientID("SyncAgent", 5, []map[string]interface{}{row})
	if err != nil || upserted != 1 {
		t.Fatalf("SyncBatchUpsertByUserIDClientID = (%d, %v), want (1, nil)", upserted, err)
	}

	items := SyncFindAllByUserID("SyncAgent", 5)
	if len(items) != 1 {
		t.Fatalf("SyncFindAllByUserID len = %d, want 1", len(items))
	}
	if max := SyncMaxUpdatedAtByUserID("SyncAgent", 5); max == "" {
		t.Fatal("SyncMaxUpdatedAtByUserID = empty, want non-empty")
	}

	inserted, err := SyncInsertTombstones([]map[string]interface{}{
		{"UserID": 5, "TableName": "agents", "ClientID": "c1"},
	})
	if err != nil || inserted != 1 {
		t.Fatalf("SyncInsertTombstones = (%d, %v), want (1, nil)", inserted, err)
	}
	tombs := SyncTombstonesByUserID(5)
	if len(tombs) != 1 {
		t.Fatalf("SyncTombstonesByUserID len = %d, want 1", len(tombs))
	}
	if max := SyncTombstoneMaxUpdatedAtByUserID(5); max == "" {
		t.Fatal("SyncTombstoneMaxUpdatedAtByUserID = empty, want non-empty")
	}

	if deleted := SyncBatchDeleteByUserIDClientID("SyncAgent", 5, []string{"c1"}); deleted != 1 {
		t.Fatalf("SyncBatchDeleteByUserIDClientID = %d, want 1", deleted)
	}

	// 事务封装：写入可见，handlers 侧不再需要 import database
	err = WithSyncTx(t.Context(), func(tx *SyncTx) error {
		return tx.Insert("SyncTombstone", &models.SyncTombstone{UserID: 5, TableName: "agents", ClientID: "c2"})
	})
	if err != nil {
		t.Fatalf("WithSyncTx: %v", err)
	}
	if tombs := SyncTombstonesByUserID(5); len(tombs) != 2 {
		t.Fatalf("SyncTombstonesByUserID after tx len = %d, want 2", len(tombs))
	}

	for _, tomb := range SyncTombstonesByUserID(5) {
		if id, ok := tomb["ID"].(float64); ok {
			if !SyncDeleteTombstoneByID(uint(id)) {
				t.Fatalf("SyncDeleteTombstoneByID(%v) = false", id)
			}
		}
	}
	if tombs := SyncTombstonesByUserID(5); len(tombs) != 0 {
		t.Fatalf("SyncTombstonesByUserID after delete len = %d, want 0", len(tombs))
	}
}
