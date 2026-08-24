import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_input_service.dart';

/// 客户端本地语音输入服务（sherpa-onnx 端侧识别 + record 采集，
/// 识别完全在设备本地完成，不经过应用服务器与系统识别服务）。
///
/// 识别模型为 sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23
/// （int8 encoder/joiner + fp32 decoder，中文流式 zipformer），
/// 打包在 assets/voice_model/，首次初始化时拷贝到应用文档目录后加载。
///
/// 按住说话：start 后开始采集并定时喂流解码、回调部分结果（全量文本），
/// stop 后喂尾巴 + flush 并回调最终结果。模型缺失/加载失败或权限被拒时
/// initialize 返回 false 并经 onError 报出明确错误码，由 UI 层提示。
class VoiceInputService {
  /// 采样率/采集参数：sherpa 特征提取按 16kHz 单声道配置
  static const int _sampleRate = 16000;

  /// 解码节拍：每 250ms 把缓冲的 PCM 喂给识别流并取一次部分结果
  static const Duration _decodeInterval = Duration(milliseconds: 250);

  /// assets 内的模型文件清单（同步注册在 pubspec assets/voice_model/）
  static const List<String> _modelFileNames = [
    'encoder-epoch-99-avg-1.int8.onnx',
    'decoder-epoch-99-avg-1.onnx',
    'joiner-epoch-99-avg-1.int8.onnx',
    'tokens.txt',
  ];

  /// sherpa 原生绑定全进程只需初始化一次
  static bool _bindingsReady = false;

  sherpa.OnlineRecognizer? _recognizer;
  AudioRecorder? _recorder;
  bool _available = false;
  bool _listening = false;
  Future<bool>? _initFuture;

  /// 当前识别会话
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _decodeTimer;
  BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  String _lastPartialText = '';

  /// initialize 时登记的回调，识别中途出错经此报出
  void Function(String error)? _onError;
  void Function(String status)? _onStatus;

  void Function(String text, bool isFinal)? _onResult;
  void Function(double level)? _onSoundLevel;

  bool get isAvailable => _available;
  bool get isListening => _listening;

  /// 当前编译平台是否可能支持（运行时能力仍以 [initialize] 结果为准）
  static bool get platformSupported => isVoiceInputSupported(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// 初始化：申请麦克风权限 → 拷贝模型文件（首次）→ 构建识别器。
  /// 幂等且并发安全（并发调用共享同一次初始化）。返回 false = 不可用。
  Future<bool> initialize({
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) {
    _onError = onError;
    _onStatus = onStatus;
    if (!platformSupported) return Future.value(false);
    if (_available) return Future.value(true);
    return _initFuture ??= _doInitialize().whenComplete(() {
      _initFuture = null;
    });
  }

  Future<bool> _doInitialize() async {
    // 1. 麦克风权限（record 会在 request=true 时触发系统权限弹窗）
    final recorder = AudioRecorder();
    try {
      final granted = await recorder.hasPermission();
      if (!granted) {
        _onError?.call('error_permission_denied');
        await recorder.dispose();
        return false;
      }
    } catch (e) {
      _onError?.call('error_permission_denied: $e');
      await recorder.dispose();
      return false;
    }

    // 2. 模型文件从 assets 拷贝到可写目录（sherpa 需要文件路径）
    final String modelDir;
    try {
      modelDir = await _ensureModelFiles();
    } catch (e) {
      _onError?.call('error_model_missing: $e');
      await recorder.dispose();
      return false;
    }

    // 3. 构建端侧识别器
    try {
      if (!_bindingsReady) {
        sherpa.initBindings();
        _bindingsReady = true;
      }
      final config = sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: _sampleRate,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$modelDir/encoder-epoch-99-avg-1.int8.onnx',
            decoder: '$modelDir/decoder-epoch-99-avg-1.onnx',
            joiner: '$modelDir/joiner-epoch-99-avg-1.int8.onnx',
          ),
          tokens: '$modelDir/tokens.txt',
          modelType: 'zipformer',
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        // 按住说话语义：一次按压 = 一条语句，不做端点切分
        enableEndpoint: false,
      );
      _recognizer = sherpa.OnlineRecognizer(config);
      _recorder = recorder;
      _available = true;
      return true;
    } catch (e) {
      _onError?.call('error_model_load_failed: $e');
      await recorder.dispose();
      return false;
    }
  }

  /// 把 assets/voice_model 下的模型文件拷贝到应用文档目录（已存在且
  /// 大小一致则跳过），返回拷贝目标目录路径。
  Future<String> _ensureModelFiles() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/voice_model');
    await dir.create(recursive: true);
    for (final name in _modelFileNames) {
      final data = await rootBundle.load('assets/voice_model/$name');
      final bytes = data.buffer.asUint8List();
      final file = File('${dir.path}/$name');
      if (!file.existsSync() || file.lengthSync() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
    return dir.path;
  }

  /// 开始识别。[onResult] 回调（当前已识别全量文本, 是否最终结果），
  /// [onSoundLevelChange] 回调音量电平（驱动 UI 收音指示）。
  /// 须在 [initialize] 成功后调用。
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
  }) async {
    final recognizer = _recognizer;
    final recorder = _recorder;
    if (!_available || recognizer == null || recorder == null) return;
    if (_listening) return;
    _listening = true;
    _onResult = onResult;
    _onSoundLevel = onSoundLevelChange;
    _lastPartialText = '';
    _pcmBuffer = BytesBuilder(copy: false);

    final stream = recognizer.createStream();
    _stream = stream;

    final Stream<Uint8List> micStream;
    try {
      micStream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
    } catch (e) {
      stream.free();
      _stream = null;
      _listening = false;
      _onError?.call('error_mic_start_failed: $e');
      return;
    }

    if (!_listening) {
      // 启动采集期间已被 stop/cancel：停掉刚开启的采集，不再挂监听
      try {
        await recorder.stop();
      } catch (_) {
        // 停止失败无需上报
      }
      return;
    }

    _micSub = micStream.listen(
      (chunk) {
        if (!_listening) return;
        _pcmBuffer.add(chunk);
      },
      onError: (Object e) {
        _onError?.call('error_mic_stream: $e');
      },
    );
    _onStatus?.call('listening');

    _decodeTimer = Timer.periodic(_decodeInterval, (_) => _pumpDecode());
  }

  /// 把缓冲的 PCM 喂入识别流，驱动解码并回调部分结果与音量电平。
  void _pumpDecode() {
    if (!_listening) return;
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) return;
    try {
      final bytes = _pcmBuffer.takeBytes();
      if (bytes.isNotEmpty) {
        stream.acceptWaveform(
          samples: pcm16BytesToFloat32(bytes),
          sampleRate: _sampleRate,
        );
        _onSoundLevel?.call(pcm16SoundLevel(bytes));
      }
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final text = recognizer.getResult(stream).text;
      if (text != _lastPartialText) {
        _lastPartialText = text;
        _onResult?.call(text, false);
      }
    } catch (e) {
      _onError?.call('error_decode: $e');
    }
  }

  /// 结束识别（松开手指）：停止采集，喂入残余音频并 flush，
  /// 回调一次最终结果后再返回。
  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;
    _decodeTimer?.cancel();
    _decodeTimer = null;
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder?.stop();
    } catch (_) {
      // 停止采集失败不阻塞结果交付
    }

    final recognizer = _recognizer;
    final stream = _stream;
    _stream = null;
    if (recognizer != null && stream != null) {
      try {
        final tail = _pcmBuffer.takeBytes();
        if (tail.isNotEmpty) {
          stream.acceptWaveform(
            samples: pcm16BytesToFloat32(tail),
            sampleRate: _sampleRate,
          );
        }
        stream.inputFinished();
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        _onResult?.call(recognizer.getResult(stream).text, true);
      } catch (_) {
        // 最终结果交付失败：部分结果已在上屏流程中
      }
      stream.free();
    }
    _pcmBuffer = BytesBuilder(copy: false);
    _onStatus?.call('notListening');
  }

  /// 取消本次识别，结果作废（不回调任何结果）。
  Future<void> cancelListening() async {
    if (!_listening) return;
    _listening = false;
    _decodeTimer?.cancel();
    _decodeTimer = null;
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder?.cancel();
    } catch (_) {
      // 取消失败无需上报
    }
    _stream?.free();
    _stream = null;
    _pcmBuffer = BytesBuilder(copy: false);
    _onStatus?.call('notListening');
  }

  void dispose() {
    if (_listening) {
      // dispose 不能 async，这里不等待采集停止；流与识别器立即释放，
      // record 插件侧资源由 recorder.dispose() 兜底
      _decodeTimer?.cancel();
      _micSub?.cancel();
      _recorder?.cancel();
    }
    _listening = false;
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    _recorder?.dispose();
    _recorder = null;
    _available = false;
  }
}
