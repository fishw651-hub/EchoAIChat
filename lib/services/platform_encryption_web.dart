import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Web 端加密实现（与 io 端相同的 XOR + Base64，保证同步数据兼容）
class PlatformEncryption {
  static const String _kp1 = 'aichat';
  static const String _kp2 = '_memory_';
  static const String _kp3 = 'key_v1';
  static const String _sp1 = 'aichat';
  static const String _sp2 = '_salt_';
  static const String _sp3 = '2026';

  static final String _cachedKey = _deriveKey();

  static String _deriveKey() {
    final password = '$_kp1$_kp2$_kp3';
    final salt = '$_sp1$_sp2$_sp3';
    final bytes = utf8.encode('$password$salt');
    final digest = sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }

  static String _xorTransform(String input, {bool decode = false}) {
    final bytes = decode ? base64Decode(input) : utf8.encode(input);
    final keyBytes = utf8.encode(_cachedKey);
    final result = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      result.add(bytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    if (decode) return utf8.decode(result);
    return base64Encode(result);
  }

  static String encrypt(String plainText) => _xorTransform(plainText);

  static String decrypt(String encryptedText) {
    try {
      return _xorTransform(encryptedText, decode: true);
    } catch (_) {
      return '';
    }
  }
}
