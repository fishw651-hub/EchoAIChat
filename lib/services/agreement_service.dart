import 'package:shared_preferences/shared_preferences.dart';
import '../agreements/user_agreement.dart';
import '../agreements/privacy_policy.dart';
import '../agreements/network_usage_agreement.dart';

class AgreementService {
  AgreementService._();
  static final AgreementService instance = AgreementService._();

  static const _prefix = 'agreement_';

  /// 检查某份协议是否已同意（且版本号匹配）
  Future<bool> hasAgreed(String key, String currentVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final agreedVersion = prefs.getString('${_prefix}version_$key');
    final agreed = prefs.getBool('${_prefix}agreed_$key') ?? false;
    return agreed && agreedVersion == currentVersion;
  }

  /// 标记同意（记录版本号 + 时间戳）
  Future<void> markAgreed(String key, String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefix}agreed_$key', true);
    await prefs.setString('${_prefix}version_$key', version);
    await prefs.setInt('${_prefix}time_$key', DateTime.now().millisecondsSinceEpoch);
  }

  /// 三份协议是否全部已同意
  Future<bool> allAgreed() async {
    return await hasAgreed('user_agreement', UserAgreement.version) &&
           await hasAgreed('privacy_policy', PrivacyPolicy.version) &&
           await hasAgreed('network_usage', NetworkUsageAgreement.version);
  }
}
