import 'package:shared_preferences/shared_preferences.dart';

/// 本地记录未绑定邮箱的账号（这类账号无法通过邮箱找回密码）。
/// 仅作本地判断提示用，不上传服务器。
class NoEmailAccountStore {
  static const _prefix = 'no_email_account_';

  static Future<void> mark(String username, bool noEmail) async {
    if (username.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (noEmail) {
      await prefs.setBool('$_prefix$username', true);
    } else {
      await prefs.remove('$_prefix$username');
    }
  }

  static Future<bool> isNoEmail(String username) async {
    if (username.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$username') ?? false;
  }
}
