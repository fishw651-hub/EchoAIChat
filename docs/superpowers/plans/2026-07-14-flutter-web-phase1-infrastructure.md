# Flutter Web 客户端 - 阶段 1：Web 基础设施 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Flutter Web 端能在 Chrome 中启动、登录、IndexedDB 数据库读写，为后续功能阶段打好基础。

**Architecture:** 使用条件导入 (conditional imports) 分离平台实现。将 `database_service.dart`、`device_id_service.dart`、`encryption_service.dart`、`secure_storage` 拆为接口+io实现+web实现。在 `main.dart` 用 `kIsWeb` 跳过应用更新和应用使用统计。Go 服务器添加 `/web` 静态文件路由。

**Tech Stack:** Flutter Web, sqflite_common_ffi_web, SubtleCrypto (Web Crypto API), IndexedDB, Go/Gin

## Global Constraints

- Flutter SDK: ^3.11.1
- 项目名: aichat, 当前版本: 5.0.0-beta+50
- 数据库版本: v25 (sqflite, WAL 模式)
- 服务器域名: https://example.com
- web/ 目录已存在（标准 PWA 模板，含 index.html/manifest.json/icons/）
- 条件导入模式: `import 'foo_stub.dart' if (dart.library.io) 'foo_io.dart' if (dart.library.html) 'foo_web.dart'`
- Go 服务器静态文件挂载模式: `http.FileServer(http.Dir("./web"))` + `http.StripPrefix("/web", ...)` + `gin.WrapH(...)`
- 不改动移动端现有行为，所有适配通过新增 web 实现实现

---

## 文件结构

### 新建文件

| 文件路径 | 职责 |
|---|---|
| `lib/services/database_service_web.dart` | Web 端 Database 实现（sqflite_common_ffi_web） |
| `lib/services/database_service_interface.dart` | Database 接口定义 + 工厂方法 |
| `lib/services/platform_device_id.dart` | 设备 ID 条件导入入口 |
| `lib/services/platform_device_id_io.dart` | 移动端设备 ID 实现（现有逻辑迁移） |
| `lib/services/platform_device_id_web.dart` | Web 端设备 ID 实现（localStorage UUID） |
| `lib/services/platform_encryption.dart` | 加密条件导入入口 |
| `lib/services/platform_encryption_io.dart` | 移动端加密实现（现有 XOR 逻辑迁移） |
| `lib/services/platform_encryption_web.dart` | Web 端加密实现（SubtleCrypto AES-GCM） |
| `lib/services/platform_secure_storage.dart` | 安全存储条件导入入口 |
| `lib/services/platform_secure_storage_io.dart` | 移动端安全存储（flutter_secure_storage） |
| `lib/services/platform_secure_storage_web.dart` | Web 端安全存储（SubtleCrypto + IndexedDB） |

### 修改文件

| 文件路径 | 修改内容 |
|---|---|
| `pubspec.yaml` | 添加 sqflite_common_ffi_web、sqflite_common 依赖 |
| `lib/services/database_service.dart` | 改为条件导入，委托给 io/web 实现 |
| `lib/services/device_id_service.dart` | 改为条件导入委托 |
| `lib/services/encryption_service.dart` | 改为条件导入委托 |
| `lib/services/update_service.dart` | 添加 kIsWeb 守卫 |
| `lib/services/app_usage_service.dart` | 添加 kIsWeb 守卫 |
| `lib/main.dart` | kIsWeb 时跳过 UpdateService.checkUpdate() |
| `website/API/routes/routes.go` | 添加 /web 静态文件路由 |
| `web/index.html` | 配置 base-href、meta |

---

## Task 1: 添加 Web 平台依赖

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: sqflite_common_ffi_web 可用，供 Task 3 使用

- [ ] **Step 1: 读取 pubspec.yaml 当前 dependencies**

Run: `Read pubspec.yaml`
确认 dependencies 区域内容。

- [ ] **Step 2: 添加 web 依赖**

在 `dependencies:` 区域的 `sqflite: ^2.4.1` 下方添加：

```yaml
  sqflite_common: ^2.5.4
  sqflite_common_ffi_web: ^0.4.5+1
```

- [ ] **Step 3: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 无错误退出

- [ ] **Step 4: 验证 web 依赖可用**

Run: `flutter pub deps | findstr sqflite_common`
Expected: 输出包含 `sqflite_common_ffi_web`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(web): add sqflite_common_ffi_web for web platform support"
```

---

## Task 2: 添加 kIsWeb 守卫到 UpdateService 和 AppUsageService

**Files:**
- Modify: `lib/services/update_service.dart`
- Modify: `lib/services/app_usage_service.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `package:flutter/foundation.dart` 的 `kIsWeb`
- Produces: Web 平台调用 update/app_usage 不再抛异常

- [ ] **Step 1: 修改 update_service.dart 的 checkUpdate 方法**

在 `lib/services/update_service.dart` 的 `checkUpdate()` 方法开头添加 kIsWeb 守卫：

找到：
```dart
  static Future<void> checkUpdate() async {
    if (_checked) return;
```

改为：
```dart
  static Future<void> checkUpdate() async {
    if (_checked) return;
    if (kIsWeb) {
      _checked = true;
      return; // Web 端无需检查更新，云端即最新
    }
```

- [ ] **Step 2: 修改 app_usage_service.dart 添加 kIsWeb 守卫**

在 `lib/services/app_usage_service.dart` 顶部确认是否已 import `package:flutter/foundation.dart`。如果没有，添加：

```dart
import 'package:flutter/foundation.dart';
```

在 `hasPermission`、`openPermissionSettings`、`getTodayUsage`、`getTodaySummary` 四个方法的开头（`if (!Platform.isAndroid)` 之前）添加：

```dart
    if (kIsWeb) return false; // hasPermission
    if (kIsWeb) return;       // openPermissionSettings
    if (kIsWeb) return [];    // getTodayUsage
    if (kIsWeb) return '';    // getTodaySummary
```

- [ ] **Step 3: 修改 main.dart 的 _AppShellState.initState**

在 `lib/main.dart` 的 `_AppShellState.initState` 中，找到：

```dart
    // 启动后自动检查更新（仅一次，放在 initState 避免每次 build 重复注册回调）
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateService.checkUpdate());
```

改为：

```dart
    // 启动后自动检查更新（仅一次，Web 端跳过）
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => UpdateService.checkUpdate());
    }
```

确认 `main.dart` 顶部已 import `package:flutter/foundation.dart`（已有，因为用了 `debugPrint`）。

- [ ] **Step 4: 验证 flutter analyze**

Run: `flutter analyze lib/services/update_service.dart lib/services/app_usage_service.dart lib/main.dart`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/services/update_service.dart lib/services/app_usage_service.dart lib/main.dart
git commit -m "fix(web): add kIsWeb guards to UpdateService and AppUsageService"
```

---

## Task 3: 创建 DatabaseService Web 实现

这是最关键的 task。`DatabaseService` 是全静态方法类，有 100+ 个方法。不能用接口+实现的方式逐个重写（工作量爆炸且易错）。策略：保留 `DatabaseService` 类名和所有静态方法签名不变，只把底层的 `Database` 对象获取方式改为条件导入。

**Files:**
- Create: `lib/services/database_service_web.dart`
- Modify: `lib/services/database_service.dart`

**Interfaces:**
- Consumes: `sqflite_common_ffi_web`
- Produces: `DatabaseService.database` getter 在 Web 上返回 ffi_web 数据库实例

**关键思路**：`database_service.dart` 中 `static Future<Database> get database async` 是所有操作的入口。只需让这个 getter 在 Web 上返回 ffi_web 的 Database 实例，其余 100+ 方法代码完全不动。SQLite 语句在 io 和 web 上完全一致。

- [ ] **Step 1: 创建 database_service_web.dart**

创建 `lib/services/database_service_web.dart`：

```dart
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Web 端数据库工厂初始化
/// 在 main() 中调用一次，将 sqflite 工厂切换到 ffi_web
Future<void> initWebDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiWeb;
}
```

- [ ] **Step 2: 修改 database_service.dart 的 database getter**

在 `lib/services/database_service.dart` 顶部确认 import。需要添加 `kIsWeb` 引用和 web 初始化 import：

找到文件顶部的 import 区域，添加：

```dart
import 'package:flutter/foundation.dart';
```

添加条件导入（放在文件底部 import 区域）：

```dart
import 'database_service_web.dart' if (dart.library.io) 'database_service_noop.dart';
```

创建 `lib/services/database_service_noop.dart`（移动端的空实现，因为移动端不需要 initWebDatabase）：

```dart
/// 移动端空实现，无需初始化 ffi_web
Future<void> initWebDatabase() async {}
```

- [ ] **Step 3: 修改 database getter 添加 Web 初始化**

在 `lib/services/database_service.dart` 中找到 `static Future<Database> get database async` 方法。

在方法开头（`if (_database != null)` 之后）添加 Web 初始化：

```dart
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    // Web 平台需要先初始化 ffi_web
    if (kIsWeb) {
      await initWebDatabase();
    }
    
    _database = await _initDatabase();
    return _database!;
  }
```

注意：`_initDatabase()` 内部使用 `getDatabasesPath()`。在 Web 上 `getDatabasesPath()` 会抛异常。需要修改 `_initDatabase()` 中的路径获取：

找到 `_initDatabase()` 中的：

```dart
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aichat.db');
```

改为：

```dart
    String path;
    if (kIsWeb) {
      // ffi_web 使用 in-memory 或 IndexedDB，路径只需文件名
      path = 'aichat.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'aichat.db');
    }
```

- [ ] **Step 4: 修改 main.dart 添加 Web 数据库初始化**

在 `lib/main.dart` 的 `main()` 函数开头（`WidgetsFlutterBinding.ensureInitialized()` 之后）添加：

```dart
  // Web 平台初始化 ffi_web 数据库工厂
  if (kIsWeb) {
    await initWebDatabase();
  }
```

在 `main.dart` 顶部添加 import：

```dart
import 'services/database_service_web.dart' if (dart.library.io) 'services/database_service_noop.dart';
```

- [ ] **Step 5: 验证 flutter analyze**

Run: `flutter analyze lib/services/database_service.dart lib/services/database_service_web.dart lib/services/database_service_noop.dart lib/main.dart`
Expected: No issues found

- [ ] **Step 6: 验证 Web 端能启动（不崩溃）**

Run: `flutter run -d chrome --web-port=8080`
Expected: Chrome 打开，不抛 Platform 异常（可能因为 API 配置而停在登录页或报连接错误，但不应该崩溃）

手动验证后 Ctrl+C 停止。

- [ ] **Step 7: Commit**

```bash
git add lib/services/database_service.dart lib/services/database_service_web.dart lib/services/database_service_noop.dart lib/main.dart
git commit -m "feat(web): add sqflite_common_ffi_web database support for web platform"
```

---

## Task 4: 创建 DeviceIdService 条件导入

**Files:**
- Create: `lib/services/platform_device_id.dart`
- Create: `lib/services/platform_device_id_io.dart`
- Create: `lib/services/platform_device_id_web.dart`
- Modify: `lib/services/device_id_service.dart`

**Interfaces:**
- Produces: `DeviceIdService.id` 和 `DeviceIdService.deviceName` 在 Web 上可用

**思路**：`DeviceIdService` 用 `dart:io` 的 `Platform.operatingSystem`，Web 上会崩。创建条件导入替换底层实现。

- [ ] **Step 1: 创建 platform_device_id_io.dart**

创建 `lib/services/platform_device_id_io.dart`：

```dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 移动端设备 ID 实现
class PlatformDeviceId {
  static String? _cached;

  static Future<String> getId() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('device_id');
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }
    final newId = const Uuid().v4();
    await prefs.setString('device_id', newId);
    _cached = newId;
    return newId;
  }

  static String getDeviceName() {
    return '${Platform.operatingSystem} 设备';
  }
}
```

- [ ] **Step 2: 创建 platform_device_id_web.dart**

创建 `lib/services/platform_device_id_web.dart`：

```dart
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

/// Web 端设备 ID 实现（localStorage 持久化）
class PlatformDeviceId {
  static String? _cached;
  static const _storageKey = 'aichat_device_id';

  static Future<String> getId() async {
    if (_cached != null) return _cached!;

    // 优先从 localStorage 读取
    final stored = html.window.localStorage[_storageKey];
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    // 生成新 UUID
    final newId = const Uuid().v4();
    html.window.localStorage[_storageKey] = newId;
    _cached = newId;
    return newId;
  }

  static String getDeviceName() {
    // 从 User Agent 推断设备类型
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('android')) return 'Android 浏览器';
    if (ua.contains('iphone') || ua.contains('ipad')) return 'iOS 浏览器';
    if (ua.contains('mac')) return 'Mac 浏览器';
    if (ua.contains('win')) return 'Windows 浏览器';
    if (ua.contains('linux')) return 'Linux 浏览器';
    return 'Web 浏览器';
  }
}
```

注意：`dart:html` 在非 Web 平台不可用，但条件导入保证此文件只在 Web 上加载。

- [ ] **Step 3: 创建 platform_device_id.dart 入口**

创建 `lib/services/platform_device_id.dart`：

```dart
// 条件导入：Web 用 html 实现，其他平台用 io 实现
export 'platform_device_id_io.dart' if (dart.library.html) 'platform_device_id_web.dart';
```

- [ ] **Step 4: 修改 device_id_service.dart 委托给条件导入**

读取 `lib/services/device_id_service.dart` 当前内容。

将整个文件改为：

```dart
import 'platform_device_id.dart';

/// 设备 ID 服务（条件导入委托给平台实现）
class DeviceIdService {
  DeviceIdService._();

  static Future<String> get id async => PlatformDeviceId.getId();

  static String get deviceName => PlatformDeviceId.getDeviceName();
}
```

- [ ] **Step 5: 验证 flutter analyze**

Run: `flutter analyze lib/services/device_id_service.dart lib/services/platform_device_id.dart lib/services/platform_device_id_io.dart lib/services/platform_device_id_web.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/services/device_id_service.dart lib/services/platform_device_id.dart lib/services/platform_device_id_io.dart lib/services/platform_device_id_web.dart
git commit -m "feat(web): add conditional import for DeviceIdService (localStorage UUID on web)"
```

---

## Task 5: 创建 EncryptionService 条件导入

**Files:**
- Create: `lib/services/platform_encryption_io.dart`
- Create: `lib/services/platform_encryption_web.dart`
- Create: `lib/services/platform_encryption.dart`
- Modify: `lib/services/encryption_service.dart`

**Interfaces:**
- Produces: `EncryptionService.encrypt()` 和 `decrypt()` 在 Web 上可用

**思路**：现有 `EncryptionService` 用 XOR+Base64，密钥硬编码。Web 端用 SubtleCrypto AES-GCM。但为了兼容（Web 端可能需要解密移动端同步过来的数据），Web 端也用相同的 XOR 算法。SubtleCrypto 留给 SecureStorage（Task 6）。

- [ ] **Step 1: 读取现有 encryption_service.dart**

Run: `Read lib/services/encryption_service.dart`
获取完整的 XOR 加密实现代码（`_deriveKey`、`_xorTransform`、`encrypt`、`decrypt`、`_kp1`/`_kp2`/`_kp3`/`_sp1`/`_sp2`/`_sp3` 常量）。

- [ ] **Step 2: 创建 platform_encryption_io.dart**

创建 `lib/services/platform_encryption_io.dart`，将现有 `encryption_service.dart` 的全部实现（常量 + `_deriveKey` + `_xorTransform` + `encrypt` + `decrypt`）复制到此类，类名改为 `PlatformEncryption`：

```dart
/// 移动端加密实现（XOR + Base64，与现有逻辑一致）
class PlatformEncryption {
  static const String _kp1 = 'aichat_';
  static const String _kp2 = 'memory_';
  static const String _kp3 = 'key_v1';
  static const String _sp1 = 'aichat_';
  static const String _sp2 = 'salt_';
  static const String _sp3 = '2026';
  static String? _cachedKey;

  static String _deriveKey() {
    if (_cachedKey != null) return _cachedKey!;
    final password = _kp1 + _kp2 + _kp3;
    final salt = _sp1 + _sp2 + _sp3;
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    _cachedKey = base64.encode(digest.bytes);
    return _cachedKey!;
  }

  static String _xorTransform(String input, {bool decode = false}) {
    final key = _deriveKey();
    final keyBytes = decode ? base64.decode(key) : utf8.encode(key);
    final inputBytes = decode ? base64.decode(input) : utf8.encode(input);
    final outputBytes = List<int>.generate(inputBytes.length, (i) {
      return inputBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return decode ? utf8.decode(outputBytes) : base64.encode(outputBytes);
  }

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    return _xorTransform(plainText);
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return '';
    try {
      return _xorTransform(encryptedText, decode: true);
    } catch (e) {
      return '';
    }
  }
}
```

注意：需要 `import 'dart:convert';` 和 `import 'package:crypto/crypto.dart';`。

- [ ] **Step 3: 创建 platform_encryption_web.dart**

创建 `lib/services/platform_encryption_web.dart`。Web 端使用与 io 相同的 XOR 算法（保证同步数据兼容）：

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Web 端加密实现（与 io 端相同的 XOR + Base64，保证数据兼容）
class PlatformEncryption {
  static const String _kp1 = 'aichat_';
  static const String _kp2 = 'memory_';
  static const String _kp3 = 'key_v1';
  static const String _sp1 = 'aichat_';
  static const String _sp2 = 'salt_';
  static const String _sp3 = '2026';
  static String? _cachedKey;

  static String _deriveKey() {
    if (_cachedKey != null) return _cachedKey!;
    final password = _kp1 + _kp2 + _kp3;
    final salt = _sp1 + _sp2 + _sp3;
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    _cachedKey = base64.encode(digest.bytes);
    return _cachedKey!;
  }

  static String _xorTransform(String input, {bool decode = false}) {
    final key = _deriveKey();
    final keyBytes = decode ? base64.decode(key) : utf8.encode(key);
    final inputBytes = decode ? base64.decode(input) : utf8.encode(input);
    final outputBytes = List<int>.generate(inputBytes.length, (i) {
      return inputBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return decode ? utf8.decode(outputBytes) : base64.encode(outputBytes);
  }

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    return _xorTransform(plainText);
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return '';
    try {
      return _xorTransform(encryptedText, decode: true);
    } catch (e) {
      return '';
    }
  }
}
```

- [ ] **Step 4: 创建 platform_encryption.dart 入口**

创建 `lib/services/platform_encryption.dart`：

```dart
export 'platform_encryption_io.dart' if (dart.library.html) 'platform_encryption_web.dart';
```

- [ ] **Step 5: 修改 encryption_service.dart 委托**

将 `lib/services/encryption_service.dart` 整个文件改为：

```dart
import 'platform_encryption.dart';

/// 加密服务（条件导入委托给平台实现）
class EncryptionService {
  EncryptionService._();

  static String encrypt(String plainText) => PlatformEncryption.encrypt(plainText);
  static String decrypt(String encryptedText) => PlatformEncryption.decrypt(encryptedText);
}
```

- [ ] **Step 6: 验证 flutter analyze**

Run: `flutter analyze lib/services/encryption_service.dart lib/services/platform_encryption.dart lib/services/platform_encryption_io.dart lib/services/platform_encryption_web.dart`
Expected: No issues found

- [ ] **Step 7: Commit**

```bash
git add lib/services/encryption_service.dart lib/services/platform_encryption.dart lib/services/platform_encryption_io.dart lib/services/platform_encryption_web.dart
git commit -m "feat(web): add conditional import for EncryptionService (XOR algorithm shared for sync compatibility)"
```

---

## Task 6: 创建 SecureStorage 条件导入

**Files:**
- Create: `lib/services/platform_secure_storage_io.dart`
- Create: `lib/services/platform_secure_storage_web.dart`
- Create: `lib/services/platform_secure_storage.dart`

**Interfaces:**
- Produces: `PlatformSecureStorage.read()`、`write()`、`delete()` 在 io 和 web 上均可用

**说明**：项目当前使用 `flutter_secure_storage`（移动端）。Web 端用 SubtleCrypto AES-GCM + IndexedDB。这是新服务，不在现有 `encryption_service.dart` 范畴。

- [ ] **Step 1: 创建 platform_secure_storage_io.dart**

创建 `lib/services/platform_secure_storage_io.dart`：

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 移动端安全存储实现（flutter_secure_storage）
class PlatformSecureStorage {
  static final _storage = const FlutterSecureStorage();

  static Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
```

- [ ] **Step 2: 创建 platform_secure_storage_web.dart**

创建 `lib/services/platform_secure_storage_web.dart`：

```dart
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Web 端安全存储实现（SubtleCrypto AES-GCM + IndexedDB）
class PlatformSecureStorage {
  static const _dbName = 'AichatSecureStorage';
  static const _storeName = 'kv';
  static const _keyStoreName = 'keys';
  static Uint8List? _aesKey;

  static Future<void> _ensureKey() async {
    if (_aesKey != null) return;

    final db = await _openDb();
    // 尝试读取已有密钥
    final existing = await _getObject(db, _keyStoreName, 'aes-key');
    if (existing != null) {
      _aesKey = existing as Uint8List;
      return;
    }

    // 生成新密钥（AES-GCM 256 位）
    final crypto = html.window.crypto;
    final keyBuffer = Uint8List(32);
    crypto.getRandomValues(keyBuffer);
    _aesKey = keyBuffer;
    await _putObject(db, _keyStoreName, 'aes-key', keyBuffer);
  }

  static Future<dynamic> _openDb() async {
    final completer = Completer<dynamic>();
    final request = html.window.indexedDB!.open(_dbName, 1);
    request.onSuccess.listen((_) {
      final db = request.result;
      if (!db.objectStoreNames!.contains(_storeName)) {
        completer.completeError('store not found');
        return;
      }
      completer.complete(db);
    });
    request.onError.listen((e) => completer.completeError(e));
    request.onUpgradeNeeded.listen((_) {
      final db = request.result;
      if (!db.objectStoreNames!.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
      if (!db.objectStoreNames!.contains(_keyStoreName)) {
        db.createObjectStore(_keyStoreName);
      }
    });
    return completer.future;
  }

  static Future<Uint8List?> _getObject(db, String store, String key) async {
    final completer = Completer<Uint8List?>();
    final tx = db.transaction(store, 'readonly');
    final store_ = tx.objectStore(store);
    final req = store_.getObject(key);
    req.onSuccess.listen((_) {
      final result = req.result;
      if (result == null) {
        completer.complete(null);
      } else {
        completer.complete(Uint8List.fromList(result as List<int>));
      }
    });
    req.onError.listen((e) => completer.completeError(e));
    return completer.future;
  }

  static Future<void> _putObject(db, String store, String key, Uint8List value) async {
    final completer = Completer<void>();
    final tx = db.transaction(store, 'readwrite');
    final store_ = tx.objectStore(store);
    store_.put(value, key);
    tx.onComplete.listen((_) => completer.complete());
    tx.onError.listen((e) => completer.completeError(e));
    return completer.future;
  }

  static Future<String> _encryptValue(String plainText) async {
    await _ensureKey();
    final iv = Uint8List(12);
    html.window.crypto.getRandomValues(iv);

    final crypto = html.window.crypto;
    final key = await crypto.subtle.importKey(
      'raw',
      _aesKey!,
      {'name': 'AES-GCM', 'length': 256},
      false,
      ['encrypt'],
    );

    final encoded = utf8.encode(plainText);
    final encrypted = await crypto.subtle.encrypt(
      {'name': 'AES-GCM', 'iv': iv},
      key,
      Uint8List.fromList(encoded),
    );

    // 存储格式：iv(12) + ciphertext，Base64 编码
    final combined = Uint8List.fromList([...iv, ...encrypted]);
    return base64.encode(combined);
  }

  static Future<String> _decryptValue(String encryptedText) async {
    await _ensureKey();
    final combined = base64.decode(encryptedText);
    final iv = combined.sublist(0, 12);
    final ciphertext = combined.sublist(12);

    final crypto = html.window.crypto;
    final key = await crypto.subtle.importKey(
      'raw',
      _aesKey!,
      {'name': 'AES-GCM', 'length': 256},
      false,
      ['decrypt'],
    );

    final decrypted = await crypto.subtle.decrypt(
      {'name': 'AES-GCM', 'iv': iv},
      key,
      ciphertext,
    );

    return utf8.decode(decrypted);
  }

  static Future<String?> read(String key) async {
    final db = await _openDb();
    final stored = await _getObject(db, _storeName, key);
    if (stored == null) return null;
    return await _decryptValue(String.fromCharCodes(stored));
  }

  static Future<void> write(String key, String value) async {
    final encrypted = await _encryptValue(value);
    final db = await _openDb();
    await _putObject(db, _storeName, key, Uint8List.fromList(encrypted.codeUnits));
  }

  static Future<void> delete(String key) async {
    final db = await _openDb();
    final tx = db.transaction(_storeName, 'readwrite');
    tx.objectStore(_storeName).delete(key);
  }
}
```

注意：`dart:html` 的 crypto.subtle API 在不同 Flutter Web 版本可能有差异。如果编译失败，需在 Task 中用 JS interop 替代。此实现可能需要调试。

- [ ] **Step 3: 创建 platform_secure_storage.dart 入口**

创建 `lib/services/platform_secure_storage.dart`：

```dart
export 'platform_secure_storage_io.dart' if (dart.library.html) 'platform_secure_storage_web.dart';
```

- [ ] **Step 4: 验证 flutter analyze**

Run: `flutter analyze lib/services/platform_secure_storage.dart lib/services/platform_secure_storage_io.dart lib/services/platform_secure_storage_web.dart`
Expected: No issues found（如有 dart:html API 问题，需修正）

- [ ] **Step 5: Commit**

```bash
git add lib/services/platform_secure_storage.dart lib/services/platform_secure_storage_io.dart lib/services/platform_secure_storage_web.dart
git commit -m "feat(web): add PlatformSecureStorage with SubtleCrypto AES-GCM for web"
```

---

## Task 7: 添加 Go 服务器 /web 静态文件路由

**Files:**
- Modify: `website/API/routes/routes.go`

**Interfaces:**
- Produces: `https://example.com/web` 提供 Flutter Web 构建产物

- [ ] **Step 1: 读取 routes.go 当前静态文件挂载代码**

Run: `Read website/API/routes/routes.go` 前 50 行，确认 landing/admin 挂载模式。

- [ ] **Step 2: 在 routes.go 中添加 /web 路由**

在 `SetupRoutes` 函数中，找到落地页 landing 挂载代码之后（`r.Static("/uploads", "./uploads")` 之前），添加：

```go
	// Flutter Web 静态文件服务
	webFS := http.FileServer(http.Dir("./web"))
	r.GET("/web/*filepath", gin.WrapH(http.StripPrefix("/web", webFS)))
	r.GET("/web", func(c *gin.Context) {
		c.Redirect(302, "/web/")
	})
```

- [ ] **Step 3: 验证 Go 编译**

Run: `cd website/API && go build -o aichat-api.exe ./...`
Expected: 编译成功无错误

- [ ] **Step 4: Commit**

```bash
git add website/API/routes/routes.go
git commit -m "feat(web): add /web static file route for Flutter Web client"
```

---

## Task 8: 配置 web/index.html 和 PWA manifest

**Files:**
- Modify: `web/index.html`

**Interfaces:**
- Produces: Web 端正确加载，base-href 为 /web/

- [ ] **Step 1: 读取 web/index.html 当前内容**

Run: `Read web/index.html`
确认当前 base-href 和 meta 配置。

- [ ] **Step 2: 修改 web/index.html**

将 `<base href="/">` 改为 `<base href="/web/">`。

确认 `<meta name="viewport">` 存在。如果没有，添加：

```html
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
```

- [ ] **Step 3: 验证 flutter build web**

Run: `flutter build web --release --base-href "/web/"`
Expected: 构建成功，`build/web/` 目录生成

- [ ] **Step 4: Commit**

```bash
git add web/index.html
git commit -m "feat(web): configure base-href and viewport for /web/ deployment"
```

---

## Task 9: 端到端验证

**Files:**
- 无（验证 task）

**目标**: 验证 Web 端能启动、不崩溃、能到达登录页

- [ ] **Step 1: flutter analyze 全项目**

Run: `flutter analyze`
Expected: 0 errors（warnings/info 可接受）

- [ ] **Step 2: flutter build web**

Run: `flutter build web --release --base-href "/web/"`
Expected: 构建成功

- [ ] **Step 3: 本地启动 web 验证**

Run: `flutter run -d chrome --web-port=8080`
Expected:
- Chrome 打开
- 不抛 Platform/UnsupportedError
- 能看到登录页或引导页
- IndexedDB 中能看到 aichat 数据库（Chrome DevTools → Application → IndexedDB）

手动验证后 Ctrl+C 停止。

- [ ] **Step 4: 验证移动端未受影响**

Run: `flutter analyze lib/services/ lib/main.dart`
Expected: No issues found

确认移动端代码路径未被破坏（条件导入在移动端加载 io 实现，行为不变）。

- [ ] **Step 5: Commit（如有遗留修改）**

```bash
git add -A
git commit -m "chore(web): phase 1 web infrastructure complete"
```

---

## 阶段 1 完成标准

- [ ] `flutter build web --release` 成功
- [ ] Web 端能启动，不崩溃
- [ ] IndexedDB 能读写（数据库初始化成功）
- [ ] 移动端行为完全不变（`flutter analyze` 无 error）
- [ ] Go 服务器 /web 路由可用（需部署后验证）
- [ ] UpdateService 和 AppUsageService 在 Web 上不抛异常

## 后续阶段

阶段 2-4 将在阶段 1 完成后单独编写实施计划，因为细节依赖阶段 1 的实际结果。
