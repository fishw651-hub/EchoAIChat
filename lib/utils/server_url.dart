import '../config/server_config.dart';

/// 解析服务端返回的资源路径为完整 URL：
/// - 完整 URL（http/https）原样返回
/// - 相对路径（/uploads/...）拼接 baseUrl
/// - 空字符串/null 返回 null
String? resolveServerUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '${ServerConfig.baseUrl}$raw';
  return '${ServerConfig.baseUrl}/$raw';
}
