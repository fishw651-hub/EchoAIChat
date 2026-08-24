import 'package:aichat/services/voice_input_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pcm16(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

void main() {
  group('wrapVoiceRecognizedText', () {
    test('回复模式：去首尾空白后原样返回', () {
      expect(wrapVoiceRecognizedText('  你好呀  ', VoiceSendMode.reply), '你好呀');
    });

    test('动作模式：用全角括号包裹', () {
      expect(wrapVoiceRecognizedText('笑着看你', VoiceSendMode.action), '（笑着看你）');
    });

    test('动作模式：已包裹的不重复加括号', () {
      expect(wrapVoiceRecognizedText('（叹气）', VoiceSendMode.action), '（叹气）');
    });

    test('空文本（含纯空白）两种模式都返回空串', () {
      expect(wrapVoiceRecognizedText('', VoiceSendMode.reply), '');
      expect(wrapVoiceRecognizedText('   ', VoiceSendMode.action), '');
    });

    test('动作模式：括号包裹后去空白再判断', () {
      expect(wrapVoiceRecognizedText('  （点头） ', VoiceSendMode.action), '（点头）');
    });
  });

  group('toggleVoiceSendMode', () {
    test('回复 ⇄ 动作 互切', () {
      expect(toggleVoiceSendMode(VoiceSendMode.reply), VoiceSendMode.action);
      expect(toggleVoiceSendMode(VoiceSendMode.action), VoiceSendMode.reply);
    });
  });

  group('voiceModeForPosition', () {
    test('左半侧（含起点）→ 语言（reply）', () {
      expect(voiceModeForPosition(0, 300), VoiceSendMode.reply);
      expect(voiceModeForPosition(149, 300), VoiceSendMode.reply);
    });

    test('右半侧（含中线）→ （动作）（action）', () {
      expect(voiceModeForPosition(150, 300), VoiceSendMode.action);
      expect(voiceModeForPosition(300, 300), VoiceSendMode.action);
    });

    test('来回滑动按实时位置判定（同一位置结果稳定）', () {
      expect(voiceModeForPosition(290, 300), VoiceSendMode.action);
      expect(voiceModeForPosition(10, 300), VoiceSendMode.reply);
      expect(voiceModeForPosition(290, 300), VoiceSendMode.action);
    });

    test('栏宽未就绪（<= 0）保守返回语言', () {
      expect(voiceModeForPosition(100, 0), VoiceSendMode.reply);
      expect(voiceModeForPosition(100, -1), VoiceSendMode.reply);
    });
  });

  group('voiceErrorKindFor', () {
    test('模型缺失/加载失败（含旧系统识别服务缺失错误码）', () {
      expect(
        voiceErrorKindFor('error_model_missing'),
        VoiceErrorKind.modelMissing,
      );
      expect(
        voiceErrorKindFor('error_model_load_failed: onnxruntime error'),
        VoiceErrorKind.modelMissing,
      );
      expect(
        voiceErrorKindFor('error_speech_recognizer_missing'),
        VoiceErrorKind.modelMissing,
      );
      expect(
        voiceErrorKindFor('error_language_not_supported'),
        VoiceErrorKind.modelMissing,
      );
    });

    test('未识别到语音 / 超时', () {
      expect(voiceErrorKindFor('error_no_match'), VoiceErrorKind.noMatch);
      expect(voiceErrorKindFor('error_speech_timeout'), VoiceErrorKind.timeout);
    });

    test('权限被拒', () {
      expect(
        voiceErrorKindFor('error_permission_denied'),
        VoiceErrorKind.permission,
      );
      expect(
        voiceErrorKindFor('Microphone permission denied'),
        VoiceErrorKind.permission,
      );
    });

    test('服务忙 / 网络错误', () {
      expect(voiceErrorKindFor('error_busy'), VoiceErrorKind.busy);
      expect(voiceErrorKindFor('error_network'), VoiceErrorKind.network);
      expect(
        voiceErrorKindFor('error_network_timeout'),
        VoiceErrorKind.network,
      );
      expect(voiceErrorKindFor('error_server'), VoiceErrorKind.network);
    });

    test('未知错误', () {
      expect(voiceErrorKindFor('error_audio_error'), VoiceErrorKind.unknown);
      expect(voiceErrorKindFor(''), VoiceErrorKind.unknown);
      expect(voiceErrorKindFor('some_random_failure'), VoiceErrorKind.unknown);
    });
  });

  group('voiceErrorL10nKey', () {
    test('每种错误类别都有独立 l10n key', () {
      final keys = VoiceErrorKind.values.map(voiceErrorL10nKey).toSet();
      expect(keys.length, VoiceErrorKind.values.length);
      expect(
        voiceErrorL10nKey(VoiceErrorKind.modelMissing),
        'voiceErrorModelMissing',
      );
      expect(voiceErrorL10nKey(VoiceErrorKind.unknown), 'voiceErrorGeneric');
    });
  });

  group('isVoiceInputSupported', () {
    test('Web 一律不支持', () {
      expect(
        isVoiceInputSupported(isWeb: true, platform: TargetPlatform.android),
        isFalse,
      );
    });

    test('Android/iOS/macOS/Windows 支持，Linux 不支持', () {
      expect(
        isVoiceInputSupported(isWeb: false, platform: TargetPlatform.android),
        isTrue,
      );
      expect(
        isVoiceInputSupported(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        isVoiceInputSupported(isWeb: false, platform: TargetPlatform.macOS),
        isTrue,
      );
      expect(
        isVoiceInputSupported(isWeb: false, platform: TargetPlatform.windows),
        isTrue,
      );
      expect(
        isVoiceInputSupported(isWeb: false, platform: TargetPlatform.linux),
        isFalse,
      );
    });
  });

  group('pcm16BytesToFloat32', () {
    test('小端 int16 归一化到 [-1, 1]', () {
      final out = pcm16BytesToFloat32(_pcm16([0, 32767, -32768, 16384]));
      expect(out.length, 4);
      expect(out[0], 0.0);
      expect(out[1], closeTo(32767 / 32768.0, 1e-7));
      expect(out[2], -1.0);
      expect(out[3], closeTo(0.5, 1e-7));
    });

    test('空输入返回空数组；奇数字节丢弃末尾半采样', () {
      expect(pcm16BytesToFloat32(Uint8List(0)).length, 0);
      expect(pcm16BytesToFloat32(Uint8List(3)).length, 1);
    });
  });

  group('pcm16SoundLevel', () {
    test('静音返回区间下限 -2', () {
      expect(pcm16SoundLevel(_pcm16(List.filled(512, 0))), -2);
      expect(pcm16SoundLevel(Uint8List(0)), -2);
    });

    test('满幅方波返回区间上限 10', () {
      expect(pcm16SoundLevel(_pcm16(List.filled(512, 32767))), 10);
    });

    test('电平随振幅单调上升，且落在 [-2, 10] 区间', () {
      double levelFor(int amp) => pcm16SoundLevel(
        _pcm16(List.generate(512, (i) => i.isEven ? amp : -amp)),
      );
      final quiet = levelFor(100);
      final mid = levelFor(3000);
      final loud = levelFor(20000);
      expect(quiet, greaterThanOrEqualTo(-2));
      expect(loud, lessThanOrEqualTo(10));
      expect(quiet, lessThan(mid));
      expect(mid, lessThan(loud));
    });
  });
}
