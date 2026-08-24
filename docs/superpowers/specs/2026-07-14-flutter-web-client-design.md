# Flutter Web 客户端设计

**日期**: 2026-07-14
**状态**: 设计已确认，待实施
**决策者**: 产品经理

## 1. 目标

为回响项目增加网页版客户端，基础功能与手机版一致。网页版作为云端应用，每次访问即为最新版本，无需应用更新机制。浏览器本地存储完整数据并参与多端同步，订阅用户可在手机和网页间无缝切换。

## 2. 已确认决策

| 决策项 | 选择 | 理由 |
|---|---|---|
| 技术栈 | Flutter Web | 复用 90%+ Dart 业务代码 |
| 功能范围 | 全部功能 | 与手机版一致 |
| 本地存储 | IndexedDB 完整本地库 + 参与同步 | 与手机端行为一致 |
| 部署方式 | 嵌入现有 Go 服务器 /web 路由 | 复用 HTTPS/TLS，部署最简 |
| OCR | 服务端 gosseract + Tesseract | 客户端零下载，手机端移除 ML Kit 减小体积 |
| 危险功能处理 | 推荐方案（见下表） | — |

## 3. 架构

```
┌─────────────────────────────────────────────────────────┐
│  现有 Go 服务器 (https://example.com)              │
│  ├─ /api/v1/*          API 端点（不变 + 新增 /ocr）       │
│  ├─ /admin             后台管理（不变）                   │
│  ├─ /                  落地页（不变）                     │
│  └─ /web               【新增】Flutter Web 构建产物       │
│                        build/web/ 静态文件服务            │
└─────────────────────────────────────────────────────────┘
            ▲                          ▲
            │ HTTPS API                │ WebSocket /sync/ws
            │                          │
┌───────────┴──────────────────────────┴───────────────────┐
│  Flutter Web 客户端 (浏览器)                              │
│  ├─ 复用 90%+ Dart 业务代码 (providers/services/screens)  │
│  ├─ IndexedDB 本地数据库 (sqflite_common_ffi_web)         │
│  │  复刻 17 张表，参与多端同步                             │
│  ├─ SubtleCrypto + IndexedDB (替代 flutter_secure_storage)│
│  ├─ Web Notification API (替代 flutter_local_notifications)│
│  └─ OCR: 纯 HTTP 调用服务端 /api/v1/ocr/recognize        │
└──────────────────────────────────────────────────────────┘
```

## 4. 平台适配策略

使用 **条件导入 (conditional imports)** 分离平台实现。每个涉及原生能力的服务拆为接口 + 两个实现：

```
lib/services/
  database_service.dart          → 接口 + 工厂
  database_service_io.dart       → sqflite (mobile, 现有代码)
  database_service_web.dart      → sqflite_common_ffi_web (web)

  notification_service.dart      → 接口 + 工厂
  notification_service_io.dart   → flutter_local_notifications
  notification_service_web.dart  → Web Notification API + Service Worker

  secure_storage_service.dart    → 接口 + 工厂
  secure_storage_service_io.dart → flutter_secure_storage
  secure_storage_service_web.dart→ SubtleCrypto + IndexedDB

  device_id_service.dart         → 接口 + 工厂
  device_id_service_io.dart      → 原生标识 (现有)
  device_id_service_web.dart     → localStorage UUID
```

OCR 不再需要条件导入（统一 HTTP 调用），移除 `ocr_service_io.dart` / `ocr_service_web.dart` 分裂。

## 5. 功能处理清单

| 功能 | 移动端 (现状) | Web 端 | 说明 |
|---|---|---|---|
| 认证（登录/注册/找回密码） | ✅ | ✅ | 不变 |
| 私聊（流式响应） | ✅ HTTP stream | ✅ 同 | SSE 在浏览器原生支持 |
| 智能体 CRUD | ✅ | ✅ | 不变 |
| 三层记忆 | ✅ | ✅ | 不变 |
| 群聊 | ✅ | ✅ | 不变 |
| 网络市场 | ✅ | ✅ | 纯 API 调用，无需适配 |
| 计划消息 | ✅ | ✅ | 不变 |
| 用户画像 | ✅ | ✅ | 不变 |
| 订阅/支付 | ✅ WebView | ✅ 新窗口打开 | webview_flutter 不可用，改用 `window.open()` |
| 多端同步 | ✅ | ✅ | WebSocket 浏览器原生支持 |
| 小说生成 | ✅ | ✅ | 不变 |
| 反馈截图 | ✅ screenshot 包 | ✅ html2canvas | screenshot 包不支持 web |
| 设置/账户中心 | ✅ | ✅ | 不变 |
| **OCR** | ✅ ML Kit (本地) | ✅ HTTP 调用 | **改为服务端运算**，手机端也改为 HTTP 调用 |
| **本地通知** | ✅ flutter_local_notifications | ✅ Web Notification API | 需 Service Worker + 用户授权 |
| **相机/相册** | ✅ image_picker | ✅ 文件上传 input | `<input type="file" accept="image/*">` |
| **加密存储** | ✅ flutter_secure_storage | ✅ SubtleCrypto + IndexedDB | AES-GCM via Web Crypto API |
| **文件导出** | ✅ open_file | ✅ 浏览器 download | `<a download>` 或 Blob URL |
| **设备 ID** | ✅ 原生标识 | ✅ localStorage UUID | 首次生成存 localStorage |
| **应用更新/强制更新** | ✅ | ❌ **完全移除** | 云端即最新，无需更新 |
| **应用使用统计** | ✅ | ❌ **移除** | 浏览器无法获取应用使用时长 |

## 6. OCR 云端化设计

### 6.1 新增服务端端点

```
POST /api/v1/ocr/recognize
Content-Type: multipart/form-data
Authorization: Bearer <token>

Body:
  image: <binary>     // 图片文件 (jpg/png, ≤10MB)

Response 200:
{
  "code": 0,
  "data": {
    "text": "识别出的文字内容",
    "confidence": 0.87
  }
}

Response 400 (图片过大/格式不支持):
{ "code": 4001, "message": "图片格式不支持或超过 10MB" }

Response 429 (配额不足):
{ "code": 4005, "message": "OCR 次数已用尽" }
```

### 6.2 服务端实现

- **文件**: `website/API/handlers/ocr.go`
- **依赖**: `github.com/otiai10/gosseract/v2`
- **逻辑**:
  1. 认证中间件验证 token
  2. 接收 multipart 图片，校验大小 ≤10MB、格式 jpg/png/webp
  3. 保存到临时文件（gosseract 需要文件路径或 bytes）
  4. 调用 gosseract，语言设为 `chi_sim+eng`
  5. 扣减 OCR 配额（独立计数，每日免费 N 次，订阅用户更多）
  6. 返回识别文本和置信度
  7. 删除临时文件

### 6.3 客户端改动

**移除**: `google_mlkit_text_recognition` 依赖（pubspec.yaml）
**移除**: `lib/services/ocr_service.dart` 中的 ML Kit 实现
**新增**: `OcrService.recognize(File image)` → HTTP POST `/api/v1/ocr/recognize`
**共用**: mobile 和 web 使用同一个 `OcrService` 实现（纯 HTTP）

### 6.4 服务器部署

```bash
# Ubuntu/Debian
apt install tesseract-ocr tesseract-ocr-chi-sim

# 验证
tesseract --version
tesseract --list-langs  # 应包含 chi_sim
```

## 7. 数据库与同步

### 7.1 Web 端数据库

使用 `sqflite_common_ffi_web` 在浏览器中通过 WASM+IndexedDB 模拟 SQLite。

- 17 张表结构与移动端完全一致
- 数据库迁移逻辑复用 `database_service.dart` 中的 migration 代码
- WAL 模式在 web 上自动退化（ffi_web 不支持 WAL，使用默认 journal mode）

### 7.2 同步参与

Web 端作为一台"设备"参与多端同步：
- 设备 ID: localStorage UUID
- WebSocket: 浏览器原生 `WebSocket` API（`web_socket_channel` 包已支持 web）
- 同步流程: 登录后 → `POST /api/v1/sync/all` 拉取全量 → 本地写入 → 后续变更推送
- 墓碑机制: 与移动端一致
- 同时聊天锁: 与移动端一致（同一 agent 不能多端同时聊天）

## 8. 部署

### 8.1 Go 服务器路由

在 `website/API/routes/routes.go` 添加：

```go
// Flutter Web 静态文件服务
webFS := http.FileServer(http.Dir("./web"))
router.GET("/web", func(c *gin.Context) {
    c.File("./web/index.html")
})
router.GET("/web/*filepath", func(c *gin.Context) {
    c.Request.URL.Path = c.Param("filepath")
    webFS.ServeHTTP(c.Writer, c.Request)
})
```

### 8.2 构建与发布

```bash
# 构建 web 产物
flutter build web --release --base-href "/web/"

# 部署到服务器
scp -r build/web/* user@server:/path/to/website/API/web/
```

`--base-href "/web/"` 确保所有资源路径以 `/web/` 为前缀。

### 8.3 CORS

由于 web 端和 API 同域（都在 `https://example.com`），无需额外 CORS 配置。WebSocket 同域也无需特殊处理。

## 9. Web Notification 实现

### 9.1 Service Worker

在 `web/` 目录添加 `sw.js`（Flutter Web 模板生成后手动添加）：

```js
// web/sw.js
self.addEventListener('push', (event) => {
  // 处理 push 通知（如果未来需要服务端推送）
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({type: 'window'}).then(clientList => {
    if (clientList.length > 0) clientList[0].focus();
    else clients.openWindow('/web/');
  }));
});
```

### 9.2 客户端

```dart
// notification_service_web.dart
// 1. 请求权限: Notification.requestPermission()
// 2. 注册 SW: navigator.serviceWorker.register('sw.js')
// 3. 显示通知: Notification(title, {body, icon})
// 4. 点击处理: SW 的 notificationclick 事件
```

限制：
- 需要 HTTPS（已有）
- 需用户主动授权
- 浏览器关闭后无法接收（除非有 Push API + Service Worker，这需要额外的推送服务器，首期不做）

## 10. 实施阶段

### 阶段 1: Web 基础设施
**目标**: web 端能启动、能登录、数据库能读写

- [ ] `flutter create . --platforms web` 生成 web/ 模板
- [ ] 添加 web 平台依赖: `sqflite_common_ffi_web`、`web` 等
- [ ] 实现 `DatabaseService` 条件导入 (io + web 两个实现)
- [ ] 实现 `EncryptionService` Web 实现 (SubtleCrypto AES-GCM)
- [ ] 实现 `SecureStorageService` 条件导入
- [ ] 实现 `DeviceIdService` Web 实现 (localStorage UUID)
- [ ] 条件导入骨架搭建（所有需要分裂的服务）
- [ ] Go 服务器添加 `/web` 静态文件路由
- [ ] web/index.html 配置 base-href、meta、PWA manifest
- [ ] 处理 `kIsWeb` 平台判断，跳过应用更新、应用使用统计
- [ ] **验证**: `flutter run -d chrome` 能启动、能登录、IndexedDB 能读写

### 阶段 2: P0 核心功能
**目标**: 完整私聊闭环

- [ ] 聊天流式响应在 web 上正常工作（SSE）
- [ ] 图片上传：`image_picker` → web 上用 `file_picker` 或 HTML input
- [ ] 智能体 CRUD 全功能
- [ ] 三层记忆查看与编辑
- [ ] 设置页面（主题、温度、思考模式等）
- [ ] 账户中心
- [ ] 图片上传功能适配（相机 → 文件选择）
- [ ] **验证**: 能与 AI 完整对话、创建智能体、管理记忆

### 阶段 3: P1 扩展功能
**目标**: 群聊、网络市场、计划、画像、订阅

- [ ] 群聊全功能（创建、管理、聊天）
- [ ] 网络市场（浏览、下载、上传、我的内容）
- [ ] 计划消息管理
- [ ] 用户画像初始化向导与 AI 分析
- [ ] 订阅中心 + 支付（新窗口打开）
- [ ] Web Notification 实现（Service Worker + 授权 + 显示）
- [ ] **验证**: 所有 P1 功能可用

### 阶段 4: P2 完整功能 + OCR 云端化
**目标**: 与手机端完全对齐 + OCR 迁移

- [ ] 多端同步（WebSocket + tombstones + 全量拉取）
- [ ] 小说生成
- [ ] 反馈截图（html2canvas 替代 screenshot 包）
- [ ] **OCR 云端化**:
  - 服务端: 新增 `handlers/ocr.go` + gosseract 依赖 + `/api/v1/ocr/recognize` 路由
  - 服务端: 配额扣减逻辑
  - 客户端: 重写 `OcrService` 为 HTTP 调用（mobile + web 共用）
  - 客户端: 移除 `google_mlkit_text_recognition` 依赖
  - 服务器部署: `apt install tesseract-ocr tesseract-ocr-chi-sim`
- [ ] **验证**: OCR 上传图片能识别文字；手机端 APK 体积减小；web 端与手机端数据互通

## 11. 关键风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| sqflite_common_ffi_web 性能 | 大数据量时比原生慢 | 首期可接受；如成为瓶颈，后续考虑 sql.js 或直接 IndexedDB |
| Flutter Web 包体积 | 首次加载 2-3MB JS | 启用 tree-shaking、deferred components、HTTP/2 gzip |
| Web Notification 限制 | 浏览器关闭后无法收 | 首期接受；未来可接 Web Push API + 推送服务器 |
| gosseract 部署 | 需服务器安装 tesseract | 文档化部署步骤；提供 Docker 镜像可选 |
| 条件导入复杂度 | 代码结构变复杂 | 统一接口 + 工厂模式，保持调用方无感知 |

## 12. 不做的事 (Out of Scope)

- **Web Push API**: 需要额外的 VAPID 推送服务器，首期不做。Web Notification 仅在浏览器打开时生效。
- **PWA 离线模式**: 首期不做 Service Worker 缓存策略，仅用于 Notification。
- **Web 端应用更新**: 完全移除，云端即最新。
- **Web 端应用使用统计**: 完全移除，浏览器无法获取。
- **OCR 支持手写体**: Tesseract 对手写支持差，首期仅支持印刷体。
