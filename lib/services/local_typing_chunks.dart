import 'package:characters/characters.dart';

/// 将完整回复拆成本地打字动画使用的 Unicode 字素簇分段。
///
/// 长文本会自适应增大每段大小，使动画更新次数不超过 [maxSteps]。
List<String> localTypingChunks(String text, {int maxSteps = 120}) {
  if (text.isEmpty) return const [];
  if (maxSteps <= 0) {
    throw ArgumentError.value(maxSteps, 'maxSteps', 'must be greater than 0');
  }

  final graphemes = text.characters.toList(growable: false);
  final chunkSize = (graphemes.length / maxSteps).ceil();
  return [
    for (var start = 0; start < graphemes.length; start += chunkSize)
      graphemes.skip(start).take(chunkSize).join(),
  ];
}
