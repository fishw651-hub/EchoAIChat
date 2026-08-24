import 'package:aichat/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies every balance field returned by the server snapshot', () {
    final profile = UserProfile(
      id: 1,
      uuid: 'user-1',
      username: 'test-user',
      email: 'test@example.com',
      balance: 12,
      dailyQuotaUsed: 2,
      dailyQuotaLeft: 8,
      subscriptionQuotaLeft: 5,
    );

    final updated = profile.withBalanceSnapshot({
      'balance': 9.5,
      'daily_quota_used': 3.5,
      'daily_quota_left': 6.5,
      'subscription_quota_left': 4.5,
    });

    expect(updated.balance, 9.5);
    expect(updated.dailyQuotaUsed, 3.5);
    expect(updated.dailyQuotaLeft, 6.5);
    expect(updated.subscriptionQuotaLeft, 4.5);
  });

  test('fromJson parses avatar_url returned by the server', () {
    // 服务器 GetProfile / 登录响应使用 avatar_url 键（handlers/auth.go）
    final profile = UserProfile.fromJson({
      'id': 1,
      'username': 'u',
      'avatar_url': '/uploads/avatars/abc.png',
    });
    expect(profile.avatar, '/uploads/avatars/abc.png');
  });

  test('fromJson still accepts legacy avatar key', () {
    final profile = UserProfile.fromJson({
      'id': 1,
      'username': 'u',
      'avatar': '/uploads/avatars/legacy.png',
    });
    expect(profile.avatar, '/uploads/avatars/legacy.png');
  });
}
