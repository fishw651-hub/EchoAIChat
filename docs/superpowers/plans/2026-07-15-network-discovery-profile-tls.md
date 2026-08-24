# 发现页、同步 TLS 与用户画像优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复偶发同步 TLS 中断，将网络页改名为发现，并提升全设备思维导图画像的可用性。

**Architecture:** 将幂等同步探测重试封装为独立可测试服务，Go TLS 配置使用统一工厂。画像保持现有 Provider 和数据模型，只改善画布变换、控件和节点展示。

**Tech Stack:** Flutter、package:http、Riverpod、Go `crypto/tls`、AutoCert

## Global Constraints

- 不关闭 TLS 证书校验。
- 只重试幂等云状态 GET，一次且延迟 250ms。
- 不改变画像数据库和同步协议。
- 新 Flutter 颜色来自 `ColorScheme`，使用 `withValues(alpha:)`。
- 不创建分支、不提交、不回滚用户现有修改。

### Task 1: 同步探测重试

**Files:**
- Create: `lib/services/sync_status_probe.dart`
- Create: `test/sync_status_probe_test.dart`
- Modify: `lib/services/sync_service.dart`

- [ ] 写失败测试：首次连接异常后第二次成功；连续失败只请求两次。
- [ ] 运行 `flutter test --no-pub test/sync_status_probe_test.dart` 确认红灯。
- [ ] 实现 12 秒超时和 250ms 单次重试并接入 `checkCloudUpdate`。
- [ ] 重跑测试确认绿灯。

### Task 2: 服务端 TLS 配置

**Files:**
- Modify: `website/API/services/tls_service.go`
- Modify: `website/API/main.go`
- Create: `website/API/services/tls_service_test.go`

- [ ] 写失败测试：配置包含证书回调、TLS 1.2、HTTP/1.1 与 ACME ALPN。
- [ ] 运行 `go test ./services -run TestNewServerTLSConfig` 确认红灯。
- [ ] 实现统一 TLS 配置工厂并接入 AutoCert/手动证书监听。
- [ ] 重跑测试确认绿灯。

### Task 3: 发现页命名

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/network_content_tab.dart`
- Create: `test/discovery_label_test.dart`

- [ ] 写失败测试验证导航标题常量为“发现”。
- [ ] 将主导航和页面标题统一为“发现”。
- [ ] 运行测试与定向分析。

### Task 4: 思维导图交互

**Files:**
- Modify: `lib/widgets/profile_mindmap_widget.dart`
- Create: `lib/widgets/profile_mindmap_controls.dart`
- Create: `test/profile_mindmap_controls_test.dart`

- [ ] 写失败 Widget 测试验证放大、缩小、复位操作。
- [ ] 实现可测试控制栏、可读默认缩放和尺寸变化复位。
- [ ] 优化中心、分类、叶子和“更多”节点。
- [ ] 运行画像测试和静态分析。

### Task 5: 全量验证

- [ ] 运行 `flutter test --no-pub`。
- [ ] 运行 `flutter analyze --no-pub`，要求 0 error。
- [ ] 运行 `cd website/API && go test ./...`。
- [ ] 运行 `cd website/API && go build ./...`。

