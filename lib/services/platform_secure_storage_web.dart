import 'dart:async';
import 'dart:convert';
import 'dart:html' show window;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 全局 crypto 对象（JS interop）
@JS('crypto')
external JSObject get _cryptoObj;

/// Web 端安全存储实现。
///
/// 优先使用 SubtleCrypto AES-GCM 256 位加密（通过 dart:js_interop 动态访问，
/// 因为 dart:html 的 SubtleCrypto 在当前 SDK 版本不暴露方法），密钥以 raw 格式
/// （Base64）存 IndexedDB，后续会话复用。
///
/// 若 SubtleCrypto 不可用或运行时出错，回退到 XOR + 硬编码密钥
/// （与 EncryptionService / platform_encryption 相同的算法）。
///
/// 存储格式：
/// - AES 路径：`aes:` + Base64(iv(12B) + ciphertext)
/// - XOR 路径：`xor:` + Base64(xor(plaintext))
class PlatformSecureStorage {
  static const String _dbName = 'aichat_secure_db';
  static const String _keyStore = 'key_store';
  static const String _dataStore = 'secure_data';
  static const String _keyRecordId = 'master_aes_key';

  static const String _aesPrefix = 'aes:';
  static const String _xorPrefix = 'xor:';

  // Fallback XOR 密钥材料（与 platform_encryption 一致，保证兼容）
  static const String _kp1 = 'aichat';
  static const String _kp2 = '_memory_';
  static const String _kp3 = 'key_v1';
  static const String _sp1 = 'aichat';
  static const String _sp2 = '_salt_';
  static const String _sp3 = '2026';

  static final String _fallbackKey = _deriveFallbackKey();
  // dart:html 的 IndexedDB Database 类名在当前 SDK 不可用，用 dynamic 持有
  static dynamic _dbInstance;
  // 密钥初始化互斥锁，防止并发 write 生成不同密钥导致数据无法解密
  static Future<JSAny?>? _keyInitFuture;

  static String _deriveFallbackKey() {
    final password = '$_kp1$_kp2$_kp3';
    final salt = '$_sp1$_sp2$_sp3';
    final bytes = utf8.encode('$password$salt');
    final digest = sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }

  static String _xorTransform(String input, {bool decode = false}) {
    final bytes = decode ? base64Decode(input) : utf8.encode(input);
    final keyBytes = utf8.encode(_fallbackKey);
    final result = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      result.add(bytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    if (decode) return utf8.decode(result);
    return base64Encode(result);
  }

  // ===== IndexedDB（dart:html window.indexedDB，Database 类型用 dynamic）=====

  static Future<dynamic> _getDb() async {
    if (_dbInstance != null) return _dbInstance;
    final idb = window.indexedDB;
    if (idb == null) {
      throw StateError('IndexedDB 不可用，Web 端安全存储无法工作');
    }
    final completer = Completer<dynamic>();
    final request = idb.open(_dbName, 1);
    request.onSuccess.listen((_) => completer.complete(request.result));
    request.onError.listen((e) => completer.completeError(e));
    request.onUpgradeNeeded.listen((_) {
      final db = request.result;
      final storeNames = db.objectStoreNames;
      if (!storeNames.contains(_keyStore)) {
        db.createObjectStore(_keyStore);
      }
      if (!storeNames.contains(_dataStore)) {
        db.createObjectStore(_dataStore);
      }
    });
    _dbInstance = await completer.future;
    return _dbInstance;
  }

  static Future<Object?> _idbGet(String storeName, String key) async {
    final db = await _getDb();
    final tx = db.transaction(storeName, 'readonly');
    final store = tx.objectStore(storeName);
    final req = store.getObject(key);
    final completer = Completer<Object?>();
    req.onSuccess.listen((_) => completer.complete(req.result));
    req.onError.listen((e) => completer.completeError(e));
    return completer.future;
  }

  static Future<void> _idbPut(String storeName, String key, Object value) async {
    final db = await _getDb();
    final tx = db.transaction(storeName, 'readwrite');
    final store = tx.objectStore(storeName);
    final req = store.put(value, key);
    final completer = Completer<void>();
    req.onSuccess.listen((_) => completer.complete());
    req.onError.listen((e) => completer.completeError(e));
    await completer.future;
  }

  static Future<void> _idbDelete(String storeName, String key) async {
    final db = await _getDb();
    final tx = db.transaction(storeName, 'readwrite');
    final store = tx.objectStore(storeName);
    final req = store.delete(key);
    final completer = Completer<void>();
    req.onSuccess.listen((_) => completer.complete());
    req.onError.listen((e) => completer.completeError(e));
    await completer.future;
  }

  // ===== SubtleCrypto AES-GCM 256（dart:js_interop_unsafe 动态访问）=====

  static JSObject get _subtle => _cryptoObj['subtle'] as JSObject;

  static Future<JSAny?> _getOrCreateKey() async {
    // 互斥锁：并发调用时复用同一个初始化 Future，避免生成不同密钥
    if (_keyInitFuture != null) return _keyInitFuture!;
    _keyInitFuture = _doGetOrCreateKey();
    try {
      return await _keyInitFuture!;
    } finally {
      _keyInitFuture = null;
    }
  }

  static Future<JSAny?> _doGetOrCreateKey() async {
    final existing = await _idbGet(_keyStore, _keyRecordId);
    if (existing != null) {
      final keyB64 = existing as String;
      final rawBytes = Uint8List.fromList(base64Decode(keyB64));
      final algorithm = JSObject();
      algorithm['name'] = 'AES-GCM'.toJS;
      final promise = _subtle.callMethod(
        'importKey'.toJS,
        <JSAny?>[
          'raw'.toJS,
          rawBytes.toJS,
          algorithm,
          true.toJS,
          <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
        ].toJS,
      ) as JSPromise;
      return await promise.toDart;
    }
    final genAlgorithm = JSObject();
    genAlgorithm['name'] = 'AES-GCM'.toJS;
    genAlgorithm['length'] = 256.toJS;
    final genPromise = _subtle.callMethod(
      'generateKey'.toJS,
      <JSAny?>[
        genAlgorithm,
        true.toJS,
        <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
      ].toJS,
    ) as JSPromise;
    final key = await genPromise.toDart;
    // 导出 raw 密钥并存 IndexedDB
    final exportPromise = _subtle.callMethod(
      'exportKey'.toJS,
      <JSAny?>['raw'.toJS, key].toJS,
    ) as JSPromise;
    final rawResult = await exportPromise.toDart;
    final rawBuffer = rawResult! as JSArrayBuffer;
    final rawBytes = Uint8List.view(rawBuffer.toDart);
    await _idbPut(_keyStore, _keyRecordId, base64Encode(rawBytes));
    return key;
  }

  static Future<String> _aesEncrypt(String plainText) async {
    final key = await _getOrCreateKey();
    // 12 字节随机 IV
    final ivJS = Uint8List(12).toJS;
    _cryptoObj.callMethod('getRandomValues'.toJS, <JSAny?>[ivJS].toJS);
    final iv = ivJS.toDart;
    final data = Uint8List.fromList(utf8.encode(plainText));
    final algorithm = JSObject();
    algorithm['name'] = 'AES-GCM'.toJS;
    algorithm['iv'] = iv.toJS;
    final encPromise = _subtle.callMethod(
      'encrypt'.toJS,
      <JSAny?>[algorithm, key, data.toJS].toJS,
    ) as JSPromise;
    final cipherResult = await encPromise.toDart;
    final cipherBuffer = cipherResult! as JSArrayBuffer;
    final cipherBytes = Uint8List.view(cipherBuffer.toDart);
    // 组合 iv + ciphertext
    final combined = Uint8List(iv.length + cipherBytes.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, cipherBytes);
    return '$_aesPrefix${base64Encode(combined)}';
  }

  static Future<String> _aesDecrypt(String payload) async {
    final key = await _getOrCreateKey();
    final combined = base64Decode(payload);
    final iv = Uint8List.fromList(combined.sublist(0, 12));
    final cipherBytes = Uint8List.fromList(combined.sublist(12));
    final algorithm = JSObject();
    algorithm['name'] = 'AES-GCM'.toJS;
    algorithm['iv'] = iv.toJS;
    final decPromise = _subtle.callMethod(
      'decrypt'.toJS,
      <JSAny?>[algorithm, key, cipherBytes.toJS].toJS,
    ) as JSPromise;
    final plainResult = await decPromise.toDart;
    final plainBuffer = plainResult! as JSArrayBuffer;
    final plainBytes = Uint8List.view(plainBuffer.toDart);
    return utf8.decode(plainBytes);
  }

  // ===== Public API =====

  static Future<String?> read(String key) async {
    try {
      final raw = await _idbGet(_dataStore, key);
      if (raw == null) return null;
      final value = raw as String;
      if (value.startsWith(_aesPrefix)) {
        try {
          return await _aesDecrypt(value.substring(_aesPrefix.length));
        } catch (_) {
          return null;
        }
      } else if (value.startsWith(_xorPrefix)) {
        try {
          return _xorTransform(value.substring(_xorPrefix.length), decode: true);
        } catch (_) {
          return null;
        }
      }
      return value;
    } catch (_) {
      // IndexedDB 不可用或读取失败，返回 null 而非抛错
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    String encoded;
    try {
      encoded = await _aesEncrypt(value);
    } catch (_) {
      encoded = '$_xorPrefix${_xorTransform(value)}';
    }
    await _idbPut(_dataStore, key, encoded);
  }

  static Future<void> delete(String key) async {
    await _idbDelete(_dataStore, key);
  }
}
