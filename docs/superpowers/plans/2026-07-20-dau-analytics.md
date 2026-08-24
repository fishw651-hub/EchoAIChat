# DAU Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 记录真实产品用户的每日活跃，并向管理仪表盘提供 7/30/90 天 DAU 趋势。

**Architecture:** 鉴权成功后调用轻量追踪服务；服务以内存键避免重复访问数据库，并在互斥区内用 `UserID + ActiveDate` 持久化去重。仪表盘服务按日期聚合记录并补齐缺失日期。

**Tech Stack:** Go、Gin、项目内 SQLite 记录存储、标准库 `sync`/`time`。

## Global Constraints

- 普通用户访问已鉴权 API 才计入 DAU，管理员不计入。
- 同一用户同一天只计一次，多设备不重复。
- 追踪失败不得阻断正常用户请求。
- `days` 仅允许 7、30、90。
- 不提交 Git commit。

---

### Task 1: 活跃记录模型与去重服务

**Files:**
- Create: `website/API/models/daily_active_user.go`
- Create: `website/API/services/daily_active_service.go`
- Test: `website/API/services/daily_active_service_test.go`

**Interfaces:**
- Produces: `NewDailyActiveService() *DailyActiveService`
- Produces: `(*DailyActiveService).Track(userID uint, role string, now time.Time) error`
- Produces: `GetDailyActiveStats(days int, now time.Time) (DailyActiveStats, error)`

- [ ] **Step 1: 写失败测试**

覆盖同用户同日去重、不同用户分别计数、管理员不计数、跨日分别计数和缺失日期补零。

- [ ] **Step 2: 验证测试失败**

Run: `cd website/API && go test ./services -run DailyActive -count=1`

Expected: FAIL，提示缺少 `DailyActiveService`。

- [ ] **Step 3: 实现模型和服务**

```go
type DailyActiveUser struct {
    ID            uint      `json:"id"`
    UserID        uint      `json:"user_id"`
    ActiveDate    string    `json:"active_date"`
    FirstActiveAt time.Time `json:"first_active_at"`
    CreatedAt     time.Time `json:"created_at"`
}

type DailyActivePoint struct {
    Date  string `json:"date"`
    Count int    `json:"count"`
}

type DailyActiveStats struct {
    Today         int                `json:"today"`
    Yesterday     int                `json:"yesterday"`
    ChangePercent float64            `json:"change_percent"`
    Peak          int                `json:"peak"`
    Average       float64            `json:"average"`
    Trend         []DailyActivePoint `json:"trend"`
}
```

`Track` 对 `role != "user"` 立即返回；缓存键包含数据库实例地址、日期和用户 ID；首次命中在互斥区内使用 `FilterAll(FilterEq("UserID", userID), FilterEq("ActiveDate", date))` 再检查后插入。

- [ ] **Step 4: 验证服务测试通过**

Run: `cd website/API && go test ./services -run DailyActive -count=1`

Expected: PASS。

### Task 2: 鉴权采集与仪表盘接口

**Files:**
- Modify: `website/API/middleware/auth.go`
- Modify: `website/API/handlers/admin.go`
- Test: `website/API/handlers/admin_dashboard_test.go`

**Interfaces:**
- Consumes: `DailyActiveService.Track`
- Consumes: `GetDailyActiveStats`
- Produces: `GET /api/v1/admin/dashboard?days=7|30|90`

- [ ] **Step 1: 写仪表盘失败测试**

测试非法 `days` 返回 400；合法请求返回 `active_users_today`、`active_users_yesterday`、`active_change_percent`、`dau_peak`、`dau_average`、`dau_trend`，且趋势长度等于 `days`。

- [ ] **Step 2: 验证测试失败**

Run: `cd website/API && go test ./handlers -run DashboardDAU -count=1`

Expected: FAIL，响应缺少 DAU 字段。

- [ ] **Step 3: 接入鉴权采集**

```go
if err := dailyActiveTracker.Track(user.ID, user.Role, time.Now()); err != nil {
    log.Printf("daily active tracking failed for user %d: %v", user.ID, err)
}
```

调用放在 JWT 和用户状态校验成功后、`c.Next()` 前。

- [ ] **Step 4: 扩展 Dashboard**

解析 `days`，只接受 7、30、90；获取聚合结果并把六个 DAU 字段合并到现有响应，保留所有旧字段。

- [ ] **Step 5: 验证后端测试**

Run: `cd website/API && go test ./handlers -run DashboardDAU -count=1 && go test ./...`

Expected: PASS。

