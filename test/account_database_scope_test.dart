import 'package:aichat/services/account_database_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('不同账号得到不同且不含账号明文的数据库名', () {
    final first = AccountDatabaseScope.databaseNameFor(12);
    final second = AccountDatabaseScope.databaseNameFor(13);

    expect(first, isNot(second));
    expect(first, startsWith('aichat_u_'));
    expect(first, isNot(contains('12')));
    expect(first, endsWith('.db'));
  });

  test('游客数据库与账号数据库分离', () {
    expect(AccountDatabaseScope.databaseNameForUser(null), 'aichat_guest.db');
    expect(
      AccountDatabaseScope.databaseNameForUser(12),
      AccountDatabaseScope.databaseNameFor(12),
    );
  });

  test('拒绝无效账号 ID', () {
    expect(() => AccountDatabaseScope.databaseNameFor(0), throwsArgumentError);
    expect(() => AccountDatabaseScope.databaseNameFor(-1), throwsArgumentError);
  });
}
