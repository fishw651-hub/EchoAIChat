import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/account_guard_service.dart';

/// 当前本地账号封禁状态（启动时与登录后刷新）
final accountGuardProvider = StateProvider<BanStatus>(
  (ref) => BanStatus.notBanned,
);
