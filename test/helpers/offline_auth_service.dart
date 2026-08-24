import 'package:aichat/models/user_profile.dart';
import 'package:aichat/services/auth_service.dart';

/// 已登录场景的离线认证桩，避免 provider 测试访问真实服务器。
class OfflineAuthService extends AuthService {
  @override
  Future<Map<String, dynamic>> registerCurrentDevice() async => {};

  @override
  Future<Map<String, dynamic>> refreshDailyAllowance() async => {};

  @override
  Future<UserProfile> getCurrentUser() async => UserProfile(
    id: 1,
    uuid: 'offline-user',
    username: 'offline-user',
    email: '',
    nickname: '',
    avatar: '',
    role: 'user',
    balance: 0,
  );

  @override
  Future<Map<String, dynamic>> getBalance() async => {};

  @override
  Future<List<dynamic>> getMySubscription() async => [];
}
