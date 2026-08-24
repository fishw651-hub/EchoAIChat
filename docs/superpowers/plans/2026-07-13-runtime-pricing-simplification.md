# 运行设置收敛与峰谷计费实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development`（推荐）或 `executing-plans` 逐任务执行。步骤以复选框跟踪。

**Goal:** 让普通聊天固定使用 Flash、非思考、温度 1.3，移除客户端和订阅后台的 Pro/模型限制，并提供可审计的峰谷价格配置与计费。

**Architecture:** Flutter 通过一个只读运行策略模块统一普通聊天和系统任务的调用参数，`SettingsState` 只保留真正的用户偏好。Go 服务在基础价和活动折扣计算完成后，根据 `SystemConfig` 中的中国时区峰谷规则应用倍率，并把倍率快照存进预留与用量记录。订阅计划不再参与模型和思考权限判定。

**Tech Stack:** Flutter / Dart / Riverpod / SharedPreferences；Go / Gin / JSON 文件数据库；原生后台 HTML / JavaScript。

## 全局约束

- 仅修改本需求直接涉及的文件；工作树已有大量用户未提交改动，不覆盖或重置无关改动。
- Flutter 新代码使用 `withValues(alpha: ...)`，不使用弃用的 `withOpacity`。
- 所有消息、记忆查询继续按 `agent_id` 或 `group_id` 隔离；本需求不得改变该约束。
- 峰谷时间固定使用 `Asia/Shanghai`，谷时段为 `[start, end)`，支持跨午夜；默认 `00:00–08:00`，两个倍率均为 `1.0`。
- 普通私聊、普通群聊、记忆处理固定 `deepseek-v4-flash`、非思考、温度 `1.3`；OCR、提示词生成、模拟器保持代码内的特殊思考策略。
- 不自动执行 Git 提交、重置或清理工作树。

---

### Task 1: 建立客户端运行策略并删除旧持久化设置

**Files:**
- Create: `lib/services/chat_runtime_policy.dart`
- Modify: `lib/providers/settings_provider.dart`
- Modify: `lib/services/api_service.dart`
- Modify: `lib/services/ai_prompt_writer_service.dart`
- Modify: `lib/services/ocr_service.dart`
- Modify: `lib/services/memory_ai_service.dart`
- Modify: `lib/services/profile_ai_service.dart`
- Modify: `lib/services/feedback_analysis_service.dart`
- Test: `test/chat_runtime_policy_test.dart`
- Test: `test/settings_provider_runtime_cleanup_test.dart`

**Interfaces:**
- Produces `ChatRuntimePolicy.standard`, `ChatRuntimePolicy.qualityTask` 和 `ChatRuntimePolicy.simulator`，每个值包含 `model`、`thinkingMode`、`temperature`。
- `ChatRuntimePolicy.standard` 的精确值为 `('deepseek-v4-flash', false, 1.3)`；思考策略的温度为 `null`，使 `ApiService` 不发送温度。
- `SettingsNotifier` 不再暴露 `setSelectedModel`、`setThinkingMode`、`setTemperature`、`setAllowedModels`、`setThinkingAllowed` 或 `effectiveModel`。

- [ ] **Step 1: 写出运行策略的失败测试**

```dart
test('标准聊天策略固定为 Flash 非思考和温度 1.3', () {
  const policy = ChatRuntimePolicy.standard;

  expect(policy.model, 'deepseek-v4-flash');
  expect(policy.thinkingMode, isFalse);
  expect(policy.temperature, 1.3);
});

test('高质量任务策略启用思考且不传温度', () {
  const policy = ChatRuntimePolicy.qualityTask;

  expect(policy.thinkingMode, isTrue);
  expect(policy.temperature, isNull);
});
```

- [ ] **Step 2: 验证测试失败**

运行：`flutter test test/chat_runtime_policy_test.dart`

预期：因 `ChatRuntimePolicy` 尚未定义而失败。

- [ ] **Step 3: 实现最小运行策略与 API 默认参数**

```dart
class ChatRuntimePolicy {
  final String model;
  final bool thinkingMode;
  final double? temperature;

  const ChatRuntimePolicy({
    required this.model,
    required this.thinkingMode,
    required this.temperature,
  });

  static const standard = ChatRuntimePolicy(
    model: 'deepseek-v4-flash',
    thinkingMode: false,
    temperature: 1.3,
  );
  static const qualityTask = ChatRuntimePolicy(
    model: 'deepseek-v4-flash',
    thinkingMode: true,
    temperature: null,
  );
}
```

让 `ApiService` 的温度参数为 `double?`，仅当非思考且温度非空时写入请求。将提示词生成、OCR、画像和反馈分析改为显式使用 `qualityTask`，让它们不再依赖全局设置。

- [ ] **Step 4: 写出旧偏好清理的失败测试**

```dart
test('初始化删除模型思考和温度偏好但保留主题', () async {
  SharedPreferences.setMockInitialValues({
    'selected_model': 'deepseek-v4-pro',
    'thinking_mode': true,
    'temperature': 0.2,
    'theme_mode': 'dark',
  });
  final notifier = SettingsNotifier();
  await Future<void>.delayed(Duration.zero);
  final prefs = await SharedPreferences.getInstance();

  expect(prefs.containsKey('selected_model'), isFalse);
  expect(prefs.containsKey('thinking_mode'), isFalse);
  expect(prefs.containsKey('temperature'), isFalse);
  expect(notifier.state.themeMode, 'dark');
});
```

- [ ] **Step 5: 验证偏好清理测试失败**

运行：`flutter test test/settings_provider_runtime_cleanup_test.dart`

预期：旧偏好仍存在或状态仍包含旧字段而失败。

- [ ] **Step 6: 最小化 SettingsState 并清理持久化键**

在 `_init()` 中移除三个旧键，并从状态、`copyWith`、导入导出配置中删除模型/思考/温度字段。保留主题、语言、记忆轮数和 token 统计。不得调用 `SharedPreferences.clear()`。

- [ ] **Step 7: 验证客户端策略测试通过**

运行：`flutter test test/chat_runtime_policy_test.dart test/settings_provider_runtime_cleanup_test.dart`

预期：两个文件全部通过。

### Task 2: 迁移普通聊天调用点并移除客户端控制界面

**Files:**
- Modify: `lib/providers/chat_provider.dart`
- Modify: `lib/providers/group_provider.dart`
- Modify: `lib/screens/chat_screen.dart`
- Modify: `lib/screens/group_create_screen.dart`
- Modify: `lib/screens/agent_create_screen.dart`
- Modify: `lib/widgets/profile_mindmap_widget.dart`
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/main.dart`
- Delete: `lib/screens/agent_settings_screen.dart`
- Modify: 每个引用 `agent_settings_screen.dart` 的 Dart 文件
- Test: `test/chat_runtime_policy_usage_test.dart`
- Test: `test/settings_screen_runtime_controls_test.dart`

**Interfaces:**
- Consumes `ChatRuntimePolicy.standard` 和 `ChatRuntimePolicy.qualityTask`。
- `ChatState` 不再包含 `ModelSwitchRequest`；`ChatNotifier` 不再有模型切换确认或订阅限制造成的自动重试状态。
- 普通聊天和群聊的 `ApiService.fromConfig` 参数必须来自 `ChatRuntimePolicy.standard`。

- [ ] **Step 1: 写出普通调用策略的失败测试**

```dart
test('普通聊天策略不受旧订阅模型响应影响', () {
  const policy = ChatRuntimePolicy.standard;

  expect(policy.model, 'deepseek-v4-flash');
  expect(policy.thinkingMode, isFalse);
  expect(policy.temperature, 1.3);
});
```

测试需同时静态断言 `SettingsState` 不再提供 `effectiveModel`，并在可注入的聊天请求构造路径上断言传给 `ApiService.fromConfig` 的三项参数等于 `standard`。

- [ ] **Step 2: 验证测试失败**

运行：`flutter test test/chat_runtime_policy_usage_test.dart`

预期：现有聊天构造仍读取 `settings.effectiveModel`、`thinkingMode` 或 `temperature`。

- [ ] **Step 3: 替换普通调用与删除模型回退流程**

将 `chat_provider.dart`、`group_provider.dart`、创建智能体后的记忆处理与画像展示中的普通调用替换为策略常量。删除 `ModelSwitchRequest`、`ModelNotAllowedException`/`ThinkingNotAllowedException` 的界面提示与 `confirmModelSwitch`、`cancelModelSwitch`。保留一般网络和余额错误的显示。

- [ ] **Step 4: 写出设置 UI 的失败测试**

```dart
testWidgets('设置页不显示模型、思考或温度控制', (tester) async {
  SharedPreferences.setMockInitialValues({'is_first_run': false});
  await tester.pumpWidget(const ProviderScope(
    child: MaterialApp(home: SettingsScreen()),
  ));
  await tester.pumpAndSettle();

  expect(find.text('模型与模式'), findsNothing);
  expect(find.text('思考模式'), findsNothing);
  expect(find.text('温度'), findsNothing);
});
```

测试文件应导入 `flutter_riverpod`、`shared_preferences`、`settings_screen.dart` 和 `settings_provider.dart`，并为 `MaterialApp` 配置项目的本地化委托及 `Locale('zh')`；测试只检查中文文案或相应的 control key，避免依赖设备主题。

- [ ] **Step 5: 验证 UI 测试失败**

运行：`flutter test test/settings_screen_runtime_controls_test.dart`

预期：当前模型选择、温度滑块和思考开关仍被找到。

- [ ] **Step 6: 删除设置入口和首次主题弹窗**

删除 `SettingsScreen._buildModelSection`、`ModelPillToggle` import 和仅服务于该区块的局部方法。移除 `AgentSettingsScreen` 的导航及文件。删除 `_AppShell.initState` 中的 `_checkInitialTheme` 回调、`_checkInitialTheme`、`_showThemePicker` 和 `theme_initial_choice_done` 读写；保留设置页的主题模式与主题颜色控件。

- [ ] **Step 7: 验证客户端行为**

运行：`flutter test test/chat_runtime_policy_usage_test.dart test/settings_screen_runtime_controls_test.dart && flutter analyze`

预期：测试通过，`flutter analyze` 为 0 errors（既有非 error 提示可记录但不新增）。

### Task 3: 引入可测试的峰谷定价解析与配置接口

**Files:**
- Create: `website/API/services/time_of_use_pricing.go`
- Create: `website/API/services/time_of_use_pricing_test.go`
- Modify: `website/API/handlers/config.go`
- Create: `website/API/handlers/config_time_of_use_test.go`
- Modify: `website/API/routes/routes.go`

**Interfaces:**
- Produces `services.TimeOfUsePricing`：`ValleyStart string`、`ValleyEnd string`、`PeakMultiplier float64`、`ValleyMultiplier float64`。
- Produces `LoadTimeOfUsePricing() (TimeOfUsePricing, error)`、`SaveTimeOfUsePricing(TimeOfUsePricing) error` 和 `MultiplierAt(time.Time) (period string, multiplier float64, err error)`。
- 管理接口：`GET /api/v1/admin/time-of-use-pricing`，`PUT /api/v1/admin/time-of-use-pricing`。

- [ ] **Step 1: 写出峰谷边界的失败测试**

```go
func TestTimeOfUsePricingMultiplierAtUsesShanghaiHalfOpenValley(t *testing.T) {
	pricing := TimeOfUsePricing{
		ValleyStart: "00:00", ValleyEnd: "08:00",
		PeakMultiplier: 1.2, ValleyMultiplier: 0.8,
	}
	for _, testCase := range []struct {
		hour, minute int
		period string
		want float64
	}{{0, 0, "valley", 0.8}, {7, 59, "valley", 0.8}, {8, 0, "peak", 1.2}} {
		at := time.Date(2026, 7, 13, testCase.hour, testCase.minute, 0, 0, time.UTC)
		period, got, err := pricing.MultiplierAt(at)
		if err != nil || period != testCase.period || got != testCase.want { t.Fatalf("period=%s multiplier=%v err=%v", period, got, err) }
	}
}
```

另写一个 `22:00–06:00` 跨午夜测试与非法相同起止时间、零倍率测试。

- [ ] **Step 2: 验证解析测试失败**

运行：`go test ./services -run TestTimeOfUsePricing -count=1`

预期：`TimeOfUsePricing` 未定义而失败。

- [ ] **Step 3: 实现默认值、校验和持久化**

```go
const timeOfUsePricingKey = "time_of_use_pricing"

func DefaultTimeOfUsePricing() TimeOfUsePricing {
	return TimeOfUsePricing{
		ValleyStart: "00:00", ValleyEnd: "08:00",
		PeakMultiplier: 1, ValleyMultiplier: 1,
	}
}
```

解析 `HH:mm` 为分钟数，将输入时刻转换到 `Asia/Shanghai` 后判断 `[start,end)`；当 `start > end` 时使用 `minute >= start || minute < end`。从 `SystemConfig` 的该键 JSON 读取，记录不存在时返回默认值；无效已存值返回安全默认值并记录错误。保存时拒绝无效请求，不覆盖旧值。

- [ ] **Step 4: 写出管理接口的失败测试**

```go
func TestConfigHandlerUpdatesTimeOfUsePricing(t *testing.T) {
	request := httptest.NewRequest(http.MethodPut, "/pricing",
		strings.NewReader(`{"valley_start":"22:00","valley_end":"06:00","peak_multiplier":1.2,"valley_multiplier":0.8}`))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	gin.New().PUT("/pricing", (&ConfigHandler{}).UpdateTimeOfUsePricing).ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK { t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String()) }
}
```

- [ ] **Step 5: 验证接口测试失败**

运行：`go test ./handlers -run TestConfigHandlerUpdatesTimeOfUsePricing -count=1`

预期：处理器方法未定义而失败。

- [ ] **Step 6: 实现管理员接口并注册路由**

在 `ConfigHandler` 添加读取和更新方法，使用 `ShouldBindJSON` 绑定 `valley_start`、`valley_end`、`peak_multiplier`、`valley_multiplier`，校验错误调用 `utils.BadRequest`。在 `adminGroup` 注册两个路由，沿用现有管理员认证中间件。

- [ ] **Step 7: 验证峰谷配置模块**

运行：`go test ./services ./handlers -run 'Test(TimeOfUsePricing|ConfigHandlerUpdatesTimeOfUsePricing)' -count=1`

预期：全部通过。

### Task 4: 将峰谷倍率快照接入预留、结算和用量审计

**Files:**
- Modify: `website/API/services/billing_reservation.go`
- Modify: `website/API/services/billing_service.go`
- Modify: `website/API/models/usage_record.go`
- Modify: `website/API/services/billing_reservation_test.go`
- Modify: `website/API/services/billing_service_test.go`

**Interfaces:**
- `billingReservationRecord` 新增 `PricingPeriod string` 与 `PriceMultiplier float64`。
- `models.UsageRecord` 新增同名字段，历史零值倍率按 `1.0` 解释。
- 产生费用的内部函数接收可选倍率，`Reserve` 和 `Settle` 对同一 `reservationID` 使用同一快照。
- `BillingService` 新增可选 `now func() time.Time` 字段；`currentTime()` 在字段为空时返回 `time.Now()`，测试可在同一服务实例上推进时间。

- [ ] **Step 1: 写出跨时段结算的失败测试**

```go
func TestSettleUsesReservationPriceMultiplierSnapshot(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	user := insertBillingUserWithBonus(t, 0, 10)
	if err := SaveTimeOfUsePricing(TimeOfUsePricing{ValleyStart: "00:00", ValleyEnd: "08:00", PeakMultiplier: 2, ValleyMultiplier: 0.5}); err != nil { t.Fatal(err) }

	now := time.Date(2026, 7, 13, 1, 0, 0, 0, time.UTC)
	service := &BillingService{now: func() time.Time { return now }}
	reservation, err := service.Reserve(user.ID, "deepseek-v4-flash", 128, false)
	if err != nil { t.Fatal(err) }
	now = time.Date(2026, 7, 13, 12, 0, 0, 0, time.UTC)
	cost, err := service.Settle(reservation.ID, user.Username, "deepseek-v4-flash", 1000, 0, 1000, 1000, false)
	if err != nil { t.Fatal(err) }
	if cost <= 0 { t.Fatalf("cost=%v, want positive", cost) }
	var records []models.UsageRecord
	database.Get().Register("UsageRecord").FindAll(&records, nil, "", 0, 0)
	if len(records) != 1 || records[0].PricingPeriod != "valley" || records[0].PriceMultiplier != 0.5 { t.Fatalf("records=%+v", records) }
}
```

测试通过同一 `BillingService` 的 `now` 闭包控制预留和结算时刻，不能依赖机器当前时间；断言结算费用和 UsageRecord 都使用预留时的谷倍率。

- [ ] **Step 2: 验证快照测试失败**

运行：`go test ./services -run TestSettleUsesReservationPriceMultiplierSnapshot -count=1`

预期：预留记录没有倍率字段或结算重新按当前时段计算而失败。

- [ ] **Step 3: 实现倍率快照和成本应用**

让 `CalculateCost` 保持基础成本加活动折扣的语义，新增仅供预留/结算调用的包装函数：

```go
func applyPriceMultiplier(cost, multiplier float64) float64 {
	if multiplier <= 0 || math.IsNaN(multiplier) || math.IsInf(multiplier, 0) {
		multiplier = 1
	}
	return math.Round(cost*multiplier*1_000_000) / 1_000_000
}
```

`Reserve` 加载当前峰谷配置、快照时段和倍率后再预留；`Settle` 使用记录中的倍率，旧记录的 `0` 回退 `1`。把快照值写到 `UsageRecord`。`Release` 继续按预留金额返还，无需重算。

- [ ] **Step 4: 写出免费和订阅额度都按倍率扣减的失败测试**

```go
func TestDeductAndRecordAppliesValleyMultiplierToFreeQuota(t *testing.T) {
	initReservationTestDatabase(t)
	insertModelPrice(t)
	if err := SaveTimeOfUsePricing(TimeOfUsePricing{ValleyStart: "00:00", ValleyEnd: "23:59", PeakMultiplier: 1, ValleyMultiplier: 0.5}); err != nil { t.Fatal(err) }
	user := insertBillingUserWithBonus(t, 0, 1)

	service := &BillingService{now: func() time.Time { return time.Date(2026, 7, 13, 12, 0, 0, 0, time.UTC) }}
	cost, _, err := service.DeductAndRecord(user.ID, user.Username, "deepseek-v4-flash", 1000, 0, 1000, 1000, false)
	if err != nil { t.Fatal(err) }
	if cost != 0.0015 { t.Fatalf("cost=%v, want 0.0015", cost) }
}
```

再为 `insertSubscription` 用户写相同断言，验证 `SubscriptionQuotaUsed` 等于倍率后的费用而非基础费用。

- [ ] **Step 5: 验证额度测试失败**

运行：`go test ./services -run 'Test(DeductAndRecordAppliesValleyMultiplier|SettleUsesReservationPriceMultiplierSnapshot)' -count=1`

预期：当前服务忽略峰谷倍率而失败。

- [ ] **Step 6: 在非流式旧扣费路径保持一致**

让 `DeductAndRecord` 同样通过峰谷策略应用当前倍率并记录时段、倍率，确保旧调用路径和流式预留路径一致。不要修改账户永久余额的扣减语义。

- [ ] **Step 7: 验证计费回归**

运行：`go test ./services -count=1`

预期：服务测试全部通过，包括既有的预留释放和每日免费/订阅额度测试。

### Task 5: 删除 Pro/订阅模型权限并更新后台管理界面

**Files:**
- Modify: `website/API/models/model_price.go`
- Modify: `website/API/models/subscription_plan.go`
- Modify: `website/API/services/deepseek_service.go`
- Modify: `website/API/handlers/chat.go`
- Modify: `website/API/handlers/config.go`
- Modify: `website/API/handlers/plan.go`
- Modify: `website/API/handlers/payment.go`
- Modify: `website/API/routes/routes.go`（仅在 Task 3 路由旁校验，无额外权限变更）
- Modify: `website/API/admin/index.html`
- Modify: `website/API/admin/js/app.js`
- Create: `website/API/handlers/chat_model_access_test.go`
- Modify: `website/API/handlers/plan_test.go`

**Interfaces:**
- `checkModelAllowed(userID, requestModel, thinkingEnabled)` 仅根据 `ModelPrice.Status` 和 `ModelPrice.ThinkingStatus` 返回拒绝信息；不查询订阅计划或 `SubscriptionPlanModel`。
- `ModelPrice` 不再包含 `ProOnly`；计划创建、更新、列表响应不包含 `ModelRestrict` 或 `AllowedModels`。
- 后台有一个独立的峰谷配置表单，调用 Task 3 的管理员接口。

- [ ] **Step 1: 写出取消 Pro 限制的失败测试**

```go
func TestCheckModelAllowedDoesNotRestrictEnabledProNamedModelBySubscription(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil { t.Fatal(err) }
	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID: "deepseek-v4-pro", ModelName: "Pro", Status: 1, ThinkingStatus: 1,
	}); err != nil { t.Fatal(err) }

	if got := checkModelAllowed(42, "deepseek-v4-pro", false); got != nil {
		t.Fatalf("restriction=%v, want nil", got)
	}
}
```

再写一个模型 `Status == 0` 被拒绝、一个 `ThinkingStatus == 0` 的思考请求被拒绝的测试，确保移除订阅限制不等于移除模型可用性保护。

- [ ] **Step 2: 验证权限测试失败**

运行：`go test ./handlers -run TestCheckModelAllowedDoesNotRestrictEnabledProNamedModelBySubscription -count=1`

预期：现有 `ProOnly` 或订阅计划逻辑拒绝该模型。

- [ ] **Step 3: 最小化后端模型权限与计划 DTO**

从 `ModelPrice`、模型同步、定价更新请求和响应删除 `ProOnly`。从订阅计划模型、计划请求/响应、支付计划响应和计划控制器删除模型限制字段；不删除历史 JSON 文件或 `SubscriptionPlanModel` 表。简化 `checkModelAllowed` 为先读取 `ModelPrice`，再检查启用与思考状态，未知模型保持现有明确错误。

- [ ] **Step 4: 写出计划接口不再持久化模型限制的失败测试**

```go
func TestPlanHandlerCreateIgnoresLegacyModelRestrictionFields(t *testing.T) {
	// POST 的 legacy model_restrict / allowed_models 不应影响保存结果，
	// 保存的 SubscriptionPlan 也不应暴露或依赖这些字段。
}
```

请求体使用 `model_restrict:true` 和一个 `allowed_models` 项；断言正常创建计划、`SubscriptionPlanModel` 表未新增记录，并保留 `allow_sync` 的既有断言。

- [ ] **Step 5: 验证计划接口测试失败**

运行：`go test ./handlers -run TestPlanHandlerCreateIgnoresLegacyModelRestrictionFields -count=1`

预期：当前处理器仍会创建限制规则而失败。

- [ ] **Step 6: 更新已被路由服务的后台静态界面**

从 `admin/index.html` 的模型定价弹窗/表格删除“仅订阅”控件，从计划弹窗删除模型限制和允许模型表。同步修改 `admin/js/app.js`：删除 `pro_only`、`model_restrict`、`allowed_models` 的渲染与提交。

在“系统配置”面板上方或“模型定价”旁新增峰谷计费表单，包含谷开始、谷结束、峰倍率、谷倍率和保存按钮；页面加载时 `GET /admin/time-of-use-pricing`，保存时 `PUT` 同一路径。表单默认值必须与后端默认一致，提交失败时显示已有 `toast` 错误。

- [ ] **Step 7: 验证后端权限与计划回归**

运行：`go test ./handlers -count=1`

预期：聊天权限、计划处理器和已有 handlers 测试全部通过。

### Task 6: 全量回归与交付检查

**Files:**
- Modify: `docs/superpowers/specs/2026-07-13-runtime-pricing-simplification-design.md`（仅在实现与已确认设计不一致时同步修订）
- Modify: `docs/superpowers/plans/2026-07-13-runtime-pricing-simplification.md`（勾选已完成步骤）

**Interfaces:**
- 不新增生产接口；验证 Tasks 1–5 的接口可共同编译与运行。

- [ ] **Step 1: 格式化 Go 变更**

运行：`gofmt -w website/API/services/time_of_use_pricing.go website/API/services/time_of_use_pricing_test.go website/API/services/billing_reservation.go website/API/services/billing_reservation_test.go website/API/services/billing_service.go website/API/services/billing_service_test.go website/API/handlers/config.go website/API/handlers/config_time_of_use_test.go website/API/handlers/chat.go website/API/handlers/chat_model_access_test.go website/API/handlers/plan.go website/API/handlers/plan_test.go website/API/models/model_price.go website/API/models/subscription_plan.go website/API/models/usage_record.go website/API/routes/routes.go`

- [ ] **Step 2: 运行 Flutter 全套验证**

运行：`flutter test && flutter analyze`

预期：所有测试通过，分析结果为 0 errors。

- [ ] **Step 3: 运行 Go 全套验证**

运行：`go test ./...`

工作目录：`website/API`

预期：退出码 0。

- [ ] **Step 4: 核对变更范围与设计覆盖**

运行：`git diff --check` 和 `git diff -- <本计划列出的路径>`。

核对：不再有用户模型/思考/温度设置和首次主题弹窗；普通聊天使用标准策略；特殊功能使用固定特殊策略；后台无 Pro/订阅模型限制；峰谷配置、倍率快照和审计字段均已实现。

- [ ] **Step 5: 报告验证证据**

在交付说明中记录执行的测试命令、退出状态，以及无法验证的真实设备流程（如有）。不要提交、重置或清理用户的工作树。
