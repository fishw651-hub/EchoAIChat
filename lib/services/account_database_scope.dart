import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class AccountDatabaseScope {
  static const guestDatabaseName = 'aichat_guest.db';

  static String databaseNameFor(int userId) {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId', '必须为正整数');
    }
    final digest = sha256.convert(utf8.encode('echo-account-db-v1:$userId'));
    return 'aichat_u_${digest.toString().substring(0, 24)}.db';
  }

  static String databaseNameForUser(int? userId) =>
      userId == null ? guestDatabaseName : databaseNameFor(userId);

  static String databaseNameForOpaqueKey(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key');
    final digest = sha256.convert(utf8.encode('echo-session-db-v1:$key'));
    return 'aichat_s_${digest.toString().substring(0, 24)}.db';
  }
}
