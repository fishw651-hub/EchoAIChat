# 回响波纹与自适应网络吞吐实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将首页回响波纹改为固定中心扩散，并让聊天保持高优先级、同步流量根据客户端与服务器压力自动调节吞吐。

**Architecture:** Flutter 将波纹几何计算与绘制分离，并用可测试的同步退避控制器合并通知、避免 SQLite 并发写。Go 后端复用 DeepSeek HTTP Transport，并在同步路由前增加进程内 AIMD 后台并发控制器；聊天路由不经过该控制器。

**Tech Stack:** Flutter/Dart、Riverpod、`package:http`、Go、Gin、`net/http`、标准库同步原语。

## Global Constraints

- 聊天请求不等待后台同步额度。
- 同一客户端同时只执行一个同步，运行期间的新通知合并为下一次同步。
- 后台额度必须有安全最小值和最大值，不创建无限队列或无限 goroutine。
- 不限制单连接字节速率，由 TCP 自然利用可用带宽。
- Flutter 新代码使用 `withValues(alpha:)`，颜色来自主题或传入颜色。
- 不修改同步协议表结构，不删除现有数据库列。
- 不擅自创建 Git 提交。

---

### Task 1: 固定中心扩散波纹

**Files:**
- Modify: `lib/widgets/echo_profile_motion.dart`
- Create: `test/echo_profile_motion_test.dart`

**Interfaces:**
- Produces: `EchoRippleGeometry.sample(Size size, double progress)`
- Produces: `EchoRippleFrame.center` 与 `EchoRippleFrame.rings`
- Consumes: `EchoOrbitRings` 当前 `AnimationController`

- [ ] **Step 1: 写失败测试**

测试三个动画进度的 `center` 完全相同，并验证单个圆环在未跨周期的两个采样点半径增大、透明度降低：

```dart
test('echo rings expand from one fixed center', () {
  const size = Size.square(150);
  final early = EchoRippleGeometry.sample(size, 0.10);
  final later = EchoRippleGeometry.sample(size, 0.20);

  expect(early.center, later.center);
  expect(later.rings.first.radius, greaterThan(early.rings.first.radius));
  expect(later.rings.first.opacity, lessThan(early.rings.first.opacity));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/echo_profile_motion_test.dart`

Expected: FAIL，因为 `EchoRippleGeometry` 尚不存在。

- [ ] **Step 3: 实现最小几何模型与 Painter**

在 `echo_profile_motion.dart` 增加不可变采样类型：

```dart
class EchoRippleRing {
  const EchoRippleRing({required this.radius, required this.opacity});
  final double radius;
  final double opacity;
}

class EchoRippleFrame {
  const EchoRippleFrame({required this.center, required this.rings});
  final Offset center;
  final List<EchoRippleRing> rings;
}

class EchoRippleGeometry {
  static EchoRippleFrame sample(Size size, double progress) {
    final center = Offset(size.width * 0.54, size.height * 0.47);
    final rings = List.generate(3, (index) {
      final phase = (progress + index / 3) % 1.0;
      return EchoRippleRing(
        radius: 30 + 58 * Curves.easeOut.transform(phase),
        opacity: (1 - phase).clamp(0.0, 1.0),
      );
    });
    return EchoRippleFrame(center: center, rings: rings);
  }
}
```

`_OrbitRingsPainter.paint` 遍历 `frame.rings`，始终使用 `frame.center`，删除 `sin/cos` 圆心漂移。

- [ ] **Step 4: 验证测试与现有卡片测试**

Run: `flutter test test/echo_profile_motion_test.dart test/home_profile_summary_card_test.dart`

Expected: PASS。

---

### Task 2: Flutter 共享 HTTP Client

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `lib/services/sync_service.dart`
- Create: `test/api_service_client_reuse_test.dart`

**Interfaces:**
- Produces: `ApiService({..., http.Client? client})`
- Produces: `ApiService` 实例内 `_client`，默认指向应用级共享 Client
- Produces: `SyncService` 内应用级共享 Client

- [ ] **Step 1: 写失败测试**

用记录请求次数的 `MockClient` 注入 `ApiService`，连续执行两个请求，断言都经过同一个 Client；测试构造器目前不接受 `client`，因此先失败。

```dart
final service = ApiService(
  baseUrl: 'https://example.test',
  apiKey: 'token',
  model: 'deepseek-v4-flash',
  client: client,
);
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/api_service_client_reuse_test.dart`

Expected: FAIL，提示没有命名参数 `client`。

- [ ] **Step 3: 注入并复用 Client**

`ApiService` 增加：

```dart
static final http.Client _sharedClient = http.Client();
final http.Client _client;

ApiService({... , http.Client? client}) : _client = client ?? _sharedClient;
```

将 `http.post` 改为 `_client.post`。`SyncService` 增加单例生命周期 `_client`，替换全部顶层 `http.get/post/put/delete` 调用。

- [ ] **Step 4: 验证客户端测试**

Run: `flutter test test/api_service_client_reuse_test.dart test/sync_status_probe_test.dart`

Expected: PASS。

---

### Task 3: Flutter 同步单飞与自适应退避

**Files:**
- Create: `lib/services/adaptive_sync_scheduler.dart`
- Create: `test/adaptive_sync_scheduler_test.dart`
- Modify: `lib/providers/sync_provider.dart`

**Interfaces:**
- Produces: `AdaptiveSyncScheduler.recordSuccess(Duration elapsed)`
- Produces: `AdaptiveSyncScheduler.recordFailure()`
- Produces: `AdaptiveSyncScheduler.nextDelay({required bool foregroundBusy})`
- Consumes: `chatProvider.state.isLoading`、`groupProvider.state.isLoading`

- [ ] **Step 1: 写失败测试**

覆盖三条行为：连续快速成功缩短延迟、失败扩大延迟、前台聊天繁忙时延迟不低于两秒。

```dart
test('failure backs off and foreground chat gets priority', () {
  final scheduler = AdaptiveSyncScheduler();
  final initial = scheduler.nextDelay(foregroundBusy: false);
  scheduler.recordFailure();
  expect(scheduler.nextDelay(foregroundBusy: false), greaterThan(initial));
  expect(
    scheduler.nextDelay(foregroundBusy: true),
    greaterThanOrEqualTo(const Duration(seconds: 2)),
  );
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/adaptive_sync_scheduler_test.dart`

Expected: FAIL，因为调度器尚不存在。

- [ ] **Step 3: 实现纯状态调度器**

使用 300ms 最小延迟、8s 最大延迟、失败翻倍、快速成功每次减少 100ms；前台繁忙时至少 2s。加入确定性的轻量抖动接口，但单元测试使用 `jitter: Duration.zero`。

- [ ] **Step 4: 接入 SyncNotifier 单飞逻辑**

增加 `_realtimePending`。通知到来时设置 pending 并调度；同步运行中不丢弃 pending。执行前读取聊天与群聊 `isLoading`，繁忙则重新调度；结束后记录成功/失败并在 pending 为真时安排下一次。继续保证 Provider 刷新只发生在同步成功后。

- [ ] **Step 5: 验证调度器与同步范围测试**

Run: `flutter test test/adaptive_sync_scheduler_test.dart test/sync_scope_test.dart test/sync_response_applier_test.dart`

Expected: PASS。

---

### Task 4: Go 网络配置与共享 Transport

**Files:**
- Modify: `website/API/config/config.go`
- Modify: `website/API/config.yaml`
- Create: `website/API/services/http_transport.go`
- Create: `website/API/services/http_transport_test.go`
- Modify: `website/API/services/deepseek_service.go`

**Interfaces:**
- Produces: `config.NetworkConfig`
- Produces: `services.NewUpstreamTransport(config.NetworkConfig) *http.Transport`
- Produces: 包级共享普通 Client、流式 Client、模型列表 Client

- [ ] **Step 1: 写失败测试**

测试非法配置回退到默认值，并测试 Transport 的 `MaxIdleConnsPerHost`、`MaxConnsPerHost` 和超时来自规范化配置。

```go
func TestNewUpstreamTransportUsesNormalizedPoolLimits(t *testing.T) {
	cfg := config.NetworkConfig{UpstreamIdleConns: 32, UpstreamMaxConnsPerHost: 64}
	transport := NewUpstreamTransport(cfg)
	if transport.MaxIdleConnsPerHost != 32 || transport.MaxConnsPerHost != 64 {
		t.Fatalf("pool = %d/%d", transport.MaxIdleConnsPerHost, transport.MaxConnsPerHost)
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `go test ./services -run TestNewUpstreamTransportUsesNormalizedPoolLimits -count=1`

Expected: FAIL，因为类型和函数尚不存在。

- [ ] **Step 3: 增加配置与边界校验**

默认值：后台最小并发 2、最大并发 32、健康阈值 800ms、过载阈值 3000ms、上游空闲连接 32、每主机最大连接 64。确保最大值不小于最小值，连接上限不小于空闲连接数。

- [ ] **Step 4: 实现共享 Transport 与 Client**

Transport 配置 `MaxIdleConns`、`MaxIdleConnsPerHost`、`MaxConnsPerHost`、`IdleConnTimeout`、`TLSHandshakeTimeout`、`ResponseHeaderTimeout`、`ExpectContinueTimeout`、`ForceAttemptHTTP2`。`DeepSeekService` 的普通、流式和模型请求复用同一个 Transport，移除每次调用内新建 Client。

- [ ] **Step 5: 验证服务测试**

Run: `go test ./services -run 'TestNewUpstreamTransport|TestNormalizeNetworkConfig' -count=1`

Expected: PASS。

---

### Task 5: Go AIMD 后台压力控制

**Files:**
- Create: `website/API/services/adaptive_limiter.go`
- Create: `website/API/services/adaptive_limiter_test.go`
- Create: `website/API/middleware/background_pressure.go`
- Create: `website/API/middleware/background_pressure_test.go`
- Modify: `website/API/routes/routes.go`

**Interfaces:**
- Produces: `AdaptiveLimiter.TryAcquire() bool`
- Produces: `AdaptiveLimiter.Release(status int, elapsed time.Duration)`
- Produces: `middleware.BackgroundPressure(limiter *services.AdaptiveLimiter) gin.HandlerFunc`

- [ ] **Step 1: 写 AIMD 失败测试**

表驱动测试：健康成功逐步增加且不超过最大值；429、5xx 或超过过载阈值时减半且不低于最小值；满额时 `TryAcquire` 返回 false。

- [ ] **Step 2: 运行测试并确认失败**

Run: `go test ./services -run TestAdaptiveLimiter -count=1`

Expected: FAIL，因为 `AdaptiveLimiter` 尚不存在。

- [ ] **Step 3: 实现并发安全 AIMD 控制器**

用 `sync.Mutex` 保护 `limit`、`inFlight` 和 `healthyStreak`。临界区内只修改整数状态，不执行 I/O。健康成功累计到当前额度次数后 `limit++`；失败或过载执行 `max(min, limit/2)`。

- [ ] **Step 4: 写中间件失败测试**

占满额度后请求同步测试路由，断言 HTTP 429、`Retry-After: 1`；同时注册不使用中间件的聊天测试路由，断言仍返回 200。

- [ ] **Step 5: 实现并挂载中间件**

中间件拒绝时直接返回标准 429。允许时记录开始时间，`c.Next()` 后用最终状态码和耗时反馈控制器。只挂载到 `/api/v1/sync` 组；聊天路由保持在组外。

- [ ] **Step 6: 验证服务与中间件测试**

Run: `go test ./services ./middleware -run 'TestAdaptiveLimiter|TestBackgroundPressure' -count=1`

Expected: PASS。

---

### Task 6: 完整验证与部署构建

**Files:**
- Verify only

- [ ] **Step 1: Flutter 定向验证**

Run:

```bash
flutter test test/echo_profile_motion_test.dart test/home_profile_summary_card_test.dart test/api_service_client_reuse_test.dart test/adaptive_sync_scheduler_test.dart test/sync_scope_test.dart test/sync_response_applier_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 2: Flutter 静态分析**

Run: `flutter analyze --no-pub`

Expected: 0 errors；允许项目既有 info，但本次修改不得新增 info。

- [ ] **Step 3: Go 定向与竞态验证**

Run:

```bash
go test ./services ./middleware ./routes -count=1
go test -race ./services ./middleware -run 'TestAdaptiveLimiter|TestBackgroundPressure' -count=1
```

Expected: PASS。

- [ ] **Step 4: Go 全量验证**

Run: `go test ./... -count=1`

Expected: PASS；若仅出现已知 Windows SQLite 临时文件锁清理失败，记录具体测试并确认新增定向测试全部通过。

- [ ] **Step 5: Go 构建**

Run: `go build -o aichat-api.exe .`

Expected: exit code 0。构建产物不纳入 Git。
