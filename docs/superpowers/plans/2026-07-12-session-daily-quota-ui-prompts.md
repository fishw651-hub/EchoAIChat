# 回响自动会话、每日额度与界面优化 Implementation Plan

> **For agentic workers:** Execute task-by-task with tests before production changes. Steps use checkbox syntax for tracking.

**Goal:** 自动恢复未主动退出的登录，客户端触发每日免费或订阅额度，移除签到，并完成微信骨架加回响质感的会话与首页画像。

**Architecture:** Flutter 在安全存储中保存 JWT、refresh token、账号和密码，按 JWT、refresh token、账号密码的顺序恢复。客户端在认证完成和恢复前台时调用 Go 的幂等日额度接口。Go 保留既有 DailyCheckInBonus 存储字段，但将它改为免费日额度的语义。现有会话数据加载保持不变，只抽取视觉组件。

**Tech Stack:** Flutter、Riverpod、flutter_secure_storage、sqflite、Gin、Go、JSON 文件数据库。

## Global Constraints

- 新增中文文案；Flutter 颜色由 ColorScheme 派生，透明度使用 withValues(alpha: ...)。
- 记忆和消息查询必须保持 agent_id 或 group_id 隔离；不改 lib/agreements。
- Go 新 User 字段必须兼容历史 JSON 零值；不使用 SQL 迁移。
- 不删除 CheckInRecord 历史数据，不改永久充值余额，不创建 Git 提交。
- 当前工作树有未提交改动；仅修改以下文件并使用最小增量。

---

### Task 1: 安全保存账号密码

**Files:**
- Modify: lib/services/secure_session_store.dart
- Test: test/secure_session_store_test.dart

**Interfaces:**
- Produces: SecureSession.username、SecureSession.password。
- Produces: SecureSessionStore 对凭据的安全保存和清除。

- [ ] **Step 1: 写失败测试**

    test('stores credentials securely and clears them with the session', () async {
      final storage = _FakeSecureStorage();
      final store = SecureSessionStore(storage: storage);
      await store.save(const SecureSession(username: 'alice', password: 'secret'));
      expect((await store.read())?.username, 'alice');
      expect((await store.read())?.password, 'secret');
      await store.clear();
      expect(storage.values, isEmpty);
    });

- [ ] **Step 2: 运行失败测试**

    Run: flutter test test/secure_session_store_test.dart --plain-name "stores credentials securely and clears them with the session"
    Expected: 编译失败，因为 SecureSession 没有 username 和 password。

- [ ] **Step 3: 最小实现**

    在 SecureSession 增加 nullable username、password；
    在 SecureSessionStore 增加 auth_username、auth_password；
    在 read、save、clear、loadAndMigrate 中按 JWT 相同路径处理两个字段；
    只迁移旧 SharedPreferences 凭据一次，迁移后仍调用 removeLegacyAuthData。

- [ ] **Step 4: 验证**

    Run: flutter test test/secure_session_store_test.dart
    Expected: SecureSessionStore 全部测试通过。

### Task 2: 恢复会话和客户端日额度刷新

**Files:**
- Modify: lib/services/auth_service.dart
- Modify: lib/providers/auth_provider.dart
- Modify: lib/main.dart
- Test: test/secure_session_store_test.dart

**Interfaces:**
- Produces: AuthService.refreshDailyAllowance()。
- Produces: AuthNotifier.refreshDailyAllowance()。
- Consumes: POST /api/v1/user/daily-allowance/refresh。

- [ ] **Step 1: 写 API 调用目标**

    Future<Map<String, dynamic>> refreshDailyAllowance() {
      return _post('/api/v1/user/daily-allowance/refresh', const {});
    }

- [ ] **Step 2: 确认 Task 1 已绿**

    Run: flutter test test/secure_session_store_test.dart
    Expected: 安全凭据测试通过，认证恢复尚未支持账号密码兜底。

- [ ] **Step 3: 实现恢复顺序**

    Future<bool> _restoreWithStoredCredentials(SecureSession session) async {
      final username = session.username;
      final password = session.password;
      if (username == null || username.isEmpty || password == null || password.isEmpty) return false;
      return _loginWithCredentials(username: username, password: password, silent: true);
    }

    login、register、registerWithCode 保存账号密码；
    _init 和 refresh token 失败时先调用该方法；
    只有没有可用凭据或凭据认证失败时才标记 sessionExpired；
    logout 继续调用 _sessionStore.clear，以清除凭据。

- [ ] **Step 4: 实现生命周期刷新**

    Future<void> refreshDailyAllowance() async {
      if (!state.isLoggedIn || state.jwtToken == null) return;
      final data = await _authService.refreshDailyAllowance();
      state = state.copyWith(user: state.user?.copyWith(
        dailyQuotaLeft: (data['daily_quota_left'] as num?)?.toDouble(),
        subscriptionQuotaLeft: (data['subscription_quota_left'] as num?)?.toDouble(),
        balance: (data['balance'] as num?)?.toDouble(),
      ));
      await _saveToStorage();
    }

    AuthNotifier 初始化和登录成功后调用刷新；
    _AppShellState 实现 WidgetsBindingObserver，在 resumed 调用刷新；
    删除 _checkInChecked、签到弹窗和 autoCheckIn 调用；日额度网络错误不阻断 UI。

- [ ] **Step 5: 验证**

    Run: flutter test test/secure_session_store_test.dart && flutter analyze
    Expected: 测试通过，flutter analyze 为 0 errors。

### Task 3: 服务端每日额度接口

**Files:**
- Modify: website/API/models/user.go
- Modify: website/API/services/quota_service.go
- Modify: website/API/services/auth_service.go
- Modify: website/API/services/billing_service.go
- Modify: website/API/services/billing_reservation.go
- Modify: website/API/handlers/user.go
- Modify: website/API/routes/routes.go
- Modify: website/API/main.go
- Create: website/API/services/daily_allowance_test.go

**Interfaces:**
- Produces: services.RefreshDailyAllowance(userID uint)。
- Produces: POST /api/v1/user/daily-allowance/refresh。

- [ ] **Step 1: 写失败测试**

    func TestRefreshDailyAllowanceGrantsFreeQuotaOncePerDay(t *testing.T) {
      user := insertDailyAllowanceUser(t, models.User{Username: "free", Status: 1})
      insertDailyAllowanceConfig(t, "default_daily_quota", "0.5")
      first, refreshed, err := RefreshDailyAllowance(user.ID)
      if err != nil || !refreshed || first.DailyCheckInBonus != 0.5 {
        t.Fatalf("first refresh = %#v, %v, %v", first, refreshed, err)
      }
      second, refreshed, err := RefreshDailyAllowance(user.ID)
      if err != nil || refreshed || second.DailyCheckInBonus != 0.5 {
        t.Fatalf("second refresh = %#v, %v, %v", second, refreshed, err)
      }
    }

    同文件增加订阅用户测试，断言免费额度为 0、SubscriptionQuotaUsed 为 0、Balance 不变。

- [ ] **Step 2: 运行失败测试**

    Run: go test ./services -run TestRefreshDailyAllowance -count=1
    Working directory: website/API
    Expected: 失败，因为 RefreshDailyAllowance 不存在。

- [ ] **Step 3: 最小实现**

    User 增加 DailyAllowanceDate 字段。RefreshDailyAllowance 按服务器日期读取用户：
    当 DailyAllowanceDate 是今天时只返回当前用户和 false；
    有有效订阅时设置 DailyCheckInBonus=0、DailyQuotaUsed=0、SubscriptionQuotaUsed=0；
    无订阅时把 default_daily_quota 写入 DailyCheckInBonus 并清零两类已用额度；
    两种情况都写入 DailyAllowanceDate 与 QuotaResetDate，绝不改 Balance。

    删除 main.go 的 StartQuotaResetJob 调用；
    AuthService、BillingService、BillingReservation 跨日逻辑不再清空 DailyCheckInBonus，只重置已用计数。

- [ ] **Step 4: 增加 Gin 端点**

    func (h *UserHandler) RefreshDailyAllowance(c *gin.Context) {
      user, refreshed, err := services.RefreshDailyAllowance(c.GetUint("user_id"))
      if err != nil { utils.BadRequest(c, err.Error()); return }
      freeLeft, subLeft, balance := services.GetUserBalanceTiers(&user)
      utils.Success(c, gin.H{
        "daily_quota_left": freeLeft,
        "subscription_quota_left": subLeft,
        "balance": balance,
        "total_balance": freeLeft + subLeft + balance,
        "refreshed": refreshed,
      })
    }

    在认证 userGroup 注册 POST("/user/daily-allowance/refresh", userHandler.RefreshDailyAllowance)。

- [ ] **Step 5: 验证**

    Run: go test ./services -run TestRefreshDailyAllowance -count=1
    Working directory: website/API
    Expected: 免费、订阅、同日幂等、永久余额测试通过。

### Task 4: 删除签到功能

**Files:**
- Modify: lib/services/auth_service.dart
- Modify: lib/providers/auth_provider.dart
- Modify: lib/l10n/app_localizations.dart
- Modify: website/API/handlers/user.go
- Modify: website/API/routes/routes.go
- Modify: website/API/handlers/admin.go
- Modify: website/API/admin/index.html
- Modify: website/API/admin/js/app.js
- Modify: website/API/API文档.md
- Create: website/API/routes/checkin_route_test.go

**Interfaces:**
- Removes: getCheckInStatus、doCheckIn、AuthNotifier.autoCheckIn、GET/POST /user/checkin。
- Produces: 管理端“额度测试重置”。

- [ ] **Step 1: 写失败路由测试**

    func TestCheckInRoutesAreNotRegistered(t *testing.T) {
      router := buildTestRouter(t)
      for _, method := range []string{http.MethodGet, http.MethodPost} {
        req := httptest.NewRequest(method, "/api/v1/user/checkin", nil)
        recorder := httptest.NewRecorder()
        router.ServeHTTP(recorder, req)
        if recorder.Code != http.StatusNotFound {
          t.Fatalf("%s status = %d, want 404", method, recorder.Code)
        }
      }
    }

- [ ] **Step 2: 运行失败测试**

    Run: go test ./routes -run TestCheckInRoutesAreNotRegistered -count=1
    Working directory: website/API
    Expected: 失败，因为签到路由仍存在。

- [ ] **Step 3: 最小实现**

    删除 UserHandler 的签到方法和 routes.go 的两条签到路由；
    删除 Dart 签到 API、provider 方法、启动弹窗、本地化键；
    管理端重置不再处理 CheckInRecord，只清 DailyQuotaUsed、SubscriptionQuotaUsed 和 DailyAllowanceDate；
    API 文档将签到章节替换为每日额度刷新接口说明。

- [ ] **Step 4: 验证**

    Run: flutter analyze && go test ./routes ./handlers ./services
    Working directory for Go command: website/API
    Expected: Flutter 无错误，签到路由为 404，Go 测试通过。

### Task 5: 复用微信骨架会话行

**Files:**
- Create: lib/widgets/echo_conversation_tile.dart
- Modify: lib/widgets/conversation_list.dart
- Modify: lib/widgets/contact_list.dart
- Modify: lib/widgets/group_list_tab.dart
- Create: test/echo_conversation_tile_test.dart

**Interfaces:**
- Produces: EchoConversationTile(avatar, title, preview, timestamp, unreadCount, onTap)。
- Consumes: AgentAvatar、GroupAvatar、ColorScheme、现有最后消息查询。

- [ ] **Step 1: 写失败组件测试**

    testWidgets('renders title preview time and unread badge', (tester) async {
      await tester.pumpWidget(testApp(EchoConversationTile(
        avatar: const SizedBox(key: Key('avatar')),
        title: '林夏', preview: '今天过得怎么样？',
        timestamp: DateTime.now(), unreadCount: 2, onTap: () {},
      )));
      expect(find.text('林夏'), findsOneWidget);
      expect(find.text('今天过得怎么样？'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

- [ ] **Step 2: 运行失败测试**

    Run: flutter test test/echo_conversation_tile_test.dart
    Expected: 编译失败，因为 EchoConversationTile 不存在。

- [ ] **Step 3: 最小实现**

    新组件使用 48px 圆角方形头像、名称与时间首行、单行预览与未读徽标次行；
    使用 surfaceContainerLow、AppTheme.brLg、低对比边框和轻阴影，不显示 chevron。
    三个列表仅替换视觉组件，保留现有最后消息加载、跳转和长按菜单。
    群聊沿用 GroupAvatar 的自定义头像、颜色和图标回退，不增加成员头像拼图查询。

- [ ] **Step 4: 验证**

    Run: flutter test test/echo_conversation_tile_test.dart && flutter analyze
    Expected: 会话行测试通过，分析无错误。

### Task 6: 首页“我眼中的你”摘要

**Files:**
- Create: lib/widgets/home_profile_summary_card.dart
- Modify: lib/screens/home_tab_screen.dart
- Modify: lib/screens/memory_screen.dart
- Modify: lib/widgets/profile_mindmap_widget.dart
- Create: test/home_profile_summary_card_test.dart

**Interfaces:**
- Produces: HomeProfileSummaryCard(onOpenProfile)。
- Produces: MemoryScreen(initialTabIndex: 3)。
- Consumes: userProfileProvider、ProfileEntry。

- [ ] **Step 1: 写失败组件测试**

    testWidgets('shows profile insight and complete profile action', (tester) async {
      await tester.pumpWidget(profileProviderApp(
        grouped: {'personality': [
          ProfileEntry(id: '1', category: 'personality', key: '理性',
            value: '偏好先给结论', confidence: 90),
        ]},
        child: HomeProfileSummaryCard(onOpenProfile: () {}),
      ));
      expect(find.text('我眼中的你'), findsOneWidget);
      expect(find.text('理性'), findsOneWidget);
      expect(find.text('查看完整画像'), findsOneWidget);
    });

- [ ] **Step 2: 运行失败测试**

    Run: flutter test test/home_profile_summary_card_test.dart
    Expected: 编译失败，因为 HomeProfileSummaryCard 不存在。

- [ ] **Step 3: 最小实现**

    摘要显示总观察数、最近更新时间、最多三个 ProfileEntry.key 和一条 ProfileEntry.value；
    空状态显示“和智能体聊得越久，它越能理解你”。
    点击卡片或“查看完整画像”均跳转：

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const MemoryScreen(initialTabIndex: 3),
    ));

    MemoryScreen 增加 initialTabIndex；ProfileMindMapWidget 保留编辑、删除、补充问题和清空，
    顶部改为标题、更新时间、观察数、完整度的卡片式布局。

- [ ] **Step 4: 放置到首页并验证**

    在 HomeTabScreen 余额/最近会话区域下方、ConversationListWidget 之前插入 HomeProfileSummaryCard；
    下拉刷新同时刷新用户资料、最近会话和 userProfileProvider。

    Run: flutter test test/home_profile_summary_card_test.dart && flutter analyze
    Expected: 首页摘要、空状态、完整画像入口测试通过，分析无错误。

### Task 7: 收敛提示词并全量验证

**Files:**
- Modify: lib/providers/chat_provider.dart
- Modify: lib/services/memory_ai_service.dart
- Modify: lib/services/profile_ai_service.dart
- Modify: lib/providers/group_provider.dart
- Modify: lib/services/group_service.dart
- Create: test/ai_prompt_policy_test.dart

**Interfaces:**
- Produces: 用户与智能体身份分离、记忆证据优先、导演只选人、旁白 150 字、NPC 工具约束。

- [ ] **Step 1: 写失败策略测试**

    test('narrator prompt requires third-person output within 150 characters', () {
      expect(GroupProvider.narratorPersonaTemplate, contains('第三人称'));
      expect(GroupProvider.narratorPersonaTemplate, contains('150'));
    });

    test('profile prompt rejects assistant facts as user facts', () {
      expect(ProfileAiService.systemPromptForTest,
        contains('不要把智能体本人的信息误归到用户画像'));
    });

- [ ] **Step 2: 运行失败测试**

    Run: flutter test test/ai_prompt_policy_test.dart
    Expected: 提示词常量未暴露或旧 250 字限制导致失败。

- [ ] **Step 3: 最小实现与验证**

    私聊按身份、世界观、画像、长期记忆、基础记忆、近期对话、当前任务排列；
    记忆和画像只记录有证据的稳定事实，不记录智能体自身信息，不推断敏感属性；
    导演只选择角色顺序；两处旁白模板均为第三人称、单次 150 字；
    NPC 必须先 manage_character 后 chatgroup。

    Run: flutter test test/ai_prompt_policy_test.dart && flutter analyze && flutter test
    Expected: 策略测试、分析和完整 Flutter 测试通过。

- [ ] **Step 4: 验证服务端和工作树**

    Run: go test ./... && go build -o aichat-api.exe .
    Working directory: website/API
    Expected: Go 测试通过并成功构建。

    Run: git diff --check && git status --short
    Expected: 没有空白错误；不执行 git add 或 git commit。
