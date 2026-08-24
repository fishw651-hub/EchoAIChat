import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'encryption_service.dart';

class SecureSession {
  final int? userId;
  final String? jwtToken;
  final String? refreshToken;
  final String? apiKey;
  final String? apiKeyId;
  final String? username;
  final String? password;

  const SecureSession({
    this.userId,
    this.jwtToken,
    this.refreshToken,
    this.apiKey,
    this.apiKeyId,
    this.username,
    this.password,
  });

  bool get isEmpty =>
      userId == null &&
      (jwtToken == null || jwtToken!.isEmpty) &&
      (refreshToken == null || refreshToken!.isEmpty) &&
      (apiKey == null || apiKey!.isEmpty) &&
      (apiKeyId == null || apiKeyId!.isEmpty) &&
      (username == null || username!.isEmpty) &&
      (password == null || password!.isEmpty);
}

abstract class SecureStorageBackend {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class _FlutterSecureStorageBackend implements SecureStorageBackend {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }
}

class SecureSessionStore {
  static const userIdKey = 'auth_user_id';
  static const jwtKey = 'auth_jwt';
  static const refreshKey = 'auth_refresh';
  static const apiKey = 'auth_api_key';
  static const apiKeyId = 'auth_api_key_id';
  static const usernameKey = 'auth_saved_username';
  // 注意：存储密码是安全反模式，后续应改为只存 JWT token + refresh token。
  // 当前保留以维持"记住密码"功能，密码以 secure storage（平台钥匙串/密钥库）保存。
  static const passwordKey = 'auth_saved_password';

  static const legacyJwtKey = jwtKey;
  static const legacyRefreshKey = refreshKey;
  static const legacyApiKey = apiKey;
  static const legacyApiKeyId = apiKeyId;
  static const legacyLoginUsernameKey = 'auth_login_username';
  static const legacyLoginPassword = 'auth_login_password';

  final SecureStorageBackend _storage;

  SecureSessionStore({SecureStorageBackend? storage})
    : _storage = storage ?? _FlutterSecureStorageBackend();

  Future<SecureSession?> read() async {
    final session = SecureSession(
      userId: int.tryParse(await _storage.read(key: userIdKey) ?? ''),
      jwtToken: await _storage.read(key: jwtKey),
      refreshToken: await _storage.read(key: refreshKey),
      apiKey: await _storage.read(key: apiKey),
      apiKeyId: await _storage.read(key: apiKeyId),
      username: await _storage.read(key: usernameKey),
      password: await _storage.read(key: passwordKey),
    );
    return session.isEmpty ? null : session;
  }

  Future<void> save(SecureSession session) async {
    await _writeOrDelete(userIdKey, session.userId?.toString());
    await _writeOrDelete(jwtKey, session.jwtToken);
    await _writeOrDelete(refreshKey, session.refreshToken);
    await _writeOrDelete(apiKey, session.apiKey);
    await _writeOrDelete(apiKeyId, session.apiKeyId);
    await _writeOrDelete(usernameKey, session.username);
    await _writeOrDelete(passwordKey, session.password);
  }

  Future<void> clear() async {
    await _storage.delete(key: userIdKey);
    await _storage.delete(key: jwtKey);
    await _storage.delete(key: refreshKey);
    await _storage.delete(key: apiKey);
    await _storage.delete(key: apiKeyId);
    await _storage.delete(key: usernameKey);
    await _storage.delete(key: passwordKey);
  }

  Future<SecureSession?> loadAndMigrate(SharedPreferences preferences) async {
    final secureSession = await read();
    if (secureSession?.jwtToken?.isNotEmpty == true) {
      await removeLegacyAuthData(preferences);
      return secureSession;
    }

    final jwt = _readLegacy(preferences, legacyJwtKey);
    if (jwt == null || jwt.isEmpty) {
      await removeLegacyAuthData(preferences);
      return secureSession;
    }

    final migrated = SecureSession(
      jwtToken: jwt,
      refreshToken: _readLegacy(preferences, legacyRefreshKey),
      apiKey: _readLegacy(preferences, legacyApiKey),
      apiKeyId: _readLegacy(preferences, legacyApiKeyId),
      username: _readLegacy(preferences, legacyLoginUsernameKey),
      password: _readLegacy(preferences, legacyLoginPassword),
    );
    await save(migrated);
    await removeLegacyAuthData(preferences);
    return migrated;
  }

  Future<void> removeLegacyAuthData(SharedPreferences preferences) async {
    await preferences.remove(legacyJwtKey);
    await preferences.remove(legacyRefreshKey);
    await preferences.remove(legacyApiKey);
    await preferences.remove(legacyApiKeyId);
    await preferences.remove(legacyLoginUsernameKey);
    await preferences.remove(legacyLoginPassword);
  }

  Future<void> _writeOrDelete(String key, String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: key);
    }
    return _storage.write(key: key, value: value);
  }

  String? _readLegacy(SharedPreferences preferences, String key) {
    final encrypted = preferences.getString(key);
    if (encrypted == null || encrypted.isEmpty) return null;
    final value = EncryptionService.decrypt(encrypted);
    return value.isEmpty ? null : value;
  }
}
