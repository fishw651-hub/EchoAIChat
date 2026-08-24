import 'auth_service.dart';
import 'device_id_service.dart';

/// 封禁状态
class BanStatus {
  final bool banned;

  /// 本次封禁的总天数（如 1、2、4、8…）
  final int banDays;

  /// 剩余封禁天数（向上取整，未封禁为 0）
  final int remainingDays;

  /// 解封时间（未封禁为 null）
  final DateTime? banUntil;

  const BanStatus({
    required this.banned,
    this.banDays = 0,
    this.remainingDays = 0,
    this.banUntil,
  });

  static const notBanned = BanStatus(banned: false);
}

/// 设备账号切换封禁（防盗用 API）— 状态存储在服务器。
///
/// 规则（服务器 `device_ban_service.go` 执行）：
/// - 14 天窗口内登录 ≥3 个不同账号 → 封禁，第 N 次 = 2^(N-1) 天封顶 365。
/// - 到期自动解封；有激活订阅的账号不计入、不受限。
///
/// 客户端职责：启动时与登录后调用服务器查询封禁状态并展示。
/// 网络失败时放行（fail-open），避免离线无法使用。
class AccountGuardService {
  /// 解析服务器响应为 BanStatus（纯函数，便于测试）
  /// [data] 来自 /auth/device-status 或 /auth/login 响应。
  static BanStatus parseBan(Map<String, dynamic> data, {DateTime? now}) {
    // login 响应字段为 device_banned，device-status 为 banned
    final banned =
        data['banned'] == true || data['device_banned'] == true;
    final banDays = (data['ban_days'] as num?)?.toInt() ?? 0;
    DateTime? until;
    final rawUntil = data['ban_until'];
    if (rawUntil is String && rawUntil.isNotEmpty) {
      until = DateTime.tryParse(rawUntil)?.toLocal();
    }
    if (!banned) return BanStatus.notBanned;

    final ref = now ?? DateTime.now();
    var remaining = banDays;
    if (until != null) {
      final diff = until.difference(ref);
      remaining = diff.isNegative ? 0 : (diff.inHours / 24).ceil();
      if (remaining <= 0) return BanStatus.notBanned;
    }
    return BanStatus(
      banned: true,
      banDays: banDays,
      remainingDays: remaining,
      banUntil: until,
    );
  }

  /// 每次启动调用：向服务器查询本设备封禁状态。网络失败放行。
  static Future<BanStatus> checkBan() async {
    try {
      final deviceId = await DeviceIdService.id;
      final data = await AuthService().getDeviceStatus(deviceId);
      return parseBan(data);
    } catch (_) {
      return BanStatus.notBanned;
    }
  }
}
