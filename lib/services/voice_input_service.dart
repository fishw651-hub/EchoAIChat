import 'dart:math';

import 'package:flutter/foundation.dart';

// VoiceInputService 按平台条件导出：原生平台用 sherpa-onnx + record 端侧识别，
// Web 等无 dart:io 平台用 stub（恒不可用，UI 层隐藏入口）。
export 'voice_input_service_stub.dart'
    if (dart.library.io) 'voice_input_service_io.dart';

/// 语音发送模式：
/// - [reply]：识别文本作为普通消息发送
/// - [action]：识别文本用全角括号 `（）` 包裹，作为动作内容发送
enum VoiceSendMode { reply, action }

/// 按模式包装识别结果（纯函数）。
/// 空文本返回空串；动作模式加全角括号，已包裹的不重复加。
String wrapVoiceRecognizedText(String rawText, VoiceSendMode mode) {
  final text = rawText.trim();
  if (text.isEmpty) return '';
  if (mode == VoiceSendMode.reply) return text;
  if (text.length > 2 && text.startsWith('（') && text.endsWith('）')) {
    return text;
  }
  return '（$text）';
}

/// 点按模式标签：回复 ⇄ 动作 互相切换（纯函数）。
VoiceSendMode toggleVoiceSendMode(VoiceSendMode current) {
  return current == VoiceSendMode.reply
      ? VoiceSendMode.action
      : VoiceSendMode.reply;
}

/// 语音栏手指横坐标 → 发送模式（纯函数）：以栏宽中线为界，
/// 左半侧回复（语言）、右半侧动作（dx >= width/2 即动作）。
/// 按住说话期间按手指实时位置判定，来回滑动来回切换，不按累计位移；
/// width <= 0（布局未就绪）时保守返回回复。
VoiceSendMode voiceModeForPosition(double dx, double width) {
  if (width <= 0) return VoiceSendMode.reply;
  return dx >= width / 2 ? VoiceSendMode.action : VoiceSendMode.reply;
}

/// 识别失败原因分类（纯函数，便于 UI 映射 l10n 文案并测试）。
enum VoiceErrorKind {
  /// 模型文件缺失/损坏或识别引擎加载失败
  modelMissing,

  /// 未识别到语音（error_no_match）
  noMatch,

  /// 说话超时未检测到语音（error_speech_timeout）
  timeout,

  /// 麦克风权限被拒
  permission,

  /// 识别服务/麦克风忙
  busy,

  /// 识别服务网络错误
  network,

  /// 其他/未知（UI 层附原始 errorMsg 便于定位）
  unknown,
}

/// 语音服务的 errorMsg（如 error_permission_denied / error_model_load_failed）
/// → 失败原因分类（纯函数）。
VoiceErrorKind voiceErrorKindFor(String errorMsg) {
  final msg = errorMsg.toLowerCase();
  if (msg.contains('model_missing') ||
      msg.contains('model_load_failed') ||
      msg.contains('model_not_found') ||
      msg.contains('recognizer_missing') ||
      msg.contains('not_available') ||
      msg.contains('language_not_supported') ||
      msg.contains('language_unavailable')) {
    return VoiceErrorKind.modelMissing;
  }
  if (msg.contains('permission') || msg.contains('denied')) {
    return VoiceErrorKind.permission;
  }
  if (msg.contains('no_match')) return VoiceErrorKind.noMatch;
  if (msg.contains('speech_timeout')) return VoiceErrorKind.timeout;
  if (msg.contains('busy')) return VoiceErrorKind.busy;
  if (msg.contains('network') || msg.contains('server')) {
    return VoiceErrorKind.network;
  }
  return VoiceErrorKind.unknown;
}

/// 失败原因 → l10n key（纯函数）。unknown 由 UI 拼接原始 errorMsg。
String voiceErrorL10nKey(VoiceErrorKind kind) {
  switch (kind) {
    case VoiceErrorKind.modelMissing:
      return 'voiceErrorModelMissing';
    case VoiceErrorKind.noMatch:
      return 'voiceErrorNoMatch';
    case VoiceErrorKind.timeout:
      return 'voiceErrorTimeout';
    case VoiceErrorKind.permission:
      return 'voiceErrorPermission';
    case VoiceErrorKind.busy:
      return 'voiceErrorBusy';
    case VoiceErrorKind.network:
      return 'voiceErrorNetwork';
    case VoiceErrorKind.unknown:
      return 'voiceErrorGeneric';
  }
}

/// 平台是否具备本地语音识别能力（纯函数，便于测试）。
/// sherpa-onnx + record 支持 Android/iOS/macOS/Windows；Web 与 Linux 不支持。
bool isVoiceInputSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return false;
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
}

/// PCM16 小端字节流 → Float32 采样（归一化到 [-1, 1]，纯函数）。
/// 奇数字节长度会丢弃末尾半个采样，防止越界。
Float32List pcm16BytesToFloat32(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  if (n == 0) return out;
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// PCM16 字节块 → 音量电平（纯函数）。
/// 计算 RMS 得 dBFS，[-50, -5] dB 线性映射到 [-2, 10]，
/// 与旧系统 SpeechRecognizer 的电平区间一致（UI 按 (level+2)/12 归一化）。
double pcm16SoundLevel(Uint8List bytes) {
  const minDb = -50.0;
  const maxDb = -5.0;
  final n = bytes.length ~/ 2;
  if (n == 0) return -2;
  final view = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final s = view.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  final rms = sqrt(sum / n);
  if (rms < 1e-6) return -2;
  final db = 20 * (log(rms) / ln10);
  final t = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  return -2 + t * 12;
}
