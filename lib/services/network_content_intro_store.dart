import 'package:shared_preferences/shared_preferences.dart';

class NetworkContentIntroStore {
  NetworkContentIntroStore._();

  static String _key(String type, int networkId, int? version) =>
      'network_content_intro_${type}_${networkId}_${version ?? 0}';

  static Future<bool> isDismissed({
    required String type,
    required int networkId,
    required int? version,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(type, networkId, version)) ?? false;
  }

  static Future<void> dismiss({
    required String type,
    required int networkId,
    required int? version,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(type, networkId, version), true);
  }
}
