import 'platform_encryption.dart';

/// 加密服务（条件导入委托给平台实现）
class EncryptionService {
  EncryptionService._();

  static String encrypt(String plainText) => PlatformEncryption.encrypt(plainText);
  static String decrypt(String encryptedText) => PlatformEncryption.decrypt(encryptedText);
}
