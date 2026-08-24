import 'dart:convert';

/// 多图消息的 image_paths 列（JSON 数组字符串）编解码。
/// 纯 Dart 无 Flutter/IO 依赖，便于单元测试；DB / 模型 / 视觉构建共用。
///
/// 存储兼容规则：写入时同时填 image_path（首图，兼容旧版读取）与
/// image_paths（完整 JSON 数组）；读取时优先 image_paths，为空回退 image_path。
class ImagePathsCodec {
  ImagePathsCodec._();

  /// 编码为 DB 列值：null/空列表 → null（列保持 NULL，读取端回退 image_path）
  static String? encode(List<String>? paths) {
    if (paths == null || paths.isEmpty) return null;
    return jsonEncode(paths);
  }

  /// 解码 image_paths 列值；非法 JSON 静默返回空列表（读取端容错）
  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 读取兼容：优先 image_paths（JSON 数组），为空回退 image_path 单图列。
  static List<String> resolve({String? imagePathsRaw, String? imagePath}) {
    final paths = decode(imagePathsRaw);
    if (paths.isNotEmpty) return paths;
    if (imagePath != null && imagePath.isNotEmpty) return [imagePath];
    return const [];
  }
}
