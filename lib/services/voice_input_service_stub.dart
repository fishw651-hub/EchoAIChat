/// Web / 无 dart:io 平台的 stub：端侧语音模型依赖原生库，不可用。
/// UI 层通过 [VoiceInputService.platformSupported] 隐藏语音入口。
class VoiceInputService {
  bool get isAvailable => false;
  bool get isListening => false;

  static bool get platformSupported => false;

  Future<bool> initialize({
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async =>
      false;

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
  }) async {}

  Future<void> stopListening() async {}

  Future<void> cancelListening() async {}

  void dispose() {}
}
