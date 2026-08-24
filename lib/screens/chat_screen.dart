import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/model_list_service.dart';
import '../services/quota_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import '../utils/range_select.dart';
import '../services/update_service.dart';
import 'memory_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';
import 'subscription_center_screen.dart';
import 'agent_create_screen.dart';
import '../providers/agent_provider.dart';
import '../models/agent.dart';
import '../models/sticker.dart';
import '../services/sticker_service.dart';
import '../services/sync_websocket_service.dart';
import '../services/proactive_care_service.dart';
import '../services/vision_message_builder.dart';
import '../services/chat_send_policy.dart';
import '../services/voice_input_service.dart';
import '../main.dart' show proactiveCareNotificationHandler;
import '../widgets/sticker_panel.dart';
import '../widgets/time_divider.dart';
import '../widgets/network_content_intro_card.dart';
import '../widgets/agent_share_dialog.dart';
import '../widgets/animated_chat_bubble.dart';
import '../widgets/bouncing_dots_indicator.dart';
import '../widgets/chat_desktop_sidebar.dart';
import '../widgets/novel_polish_dialog.dart';
import '../widgets/pending_images_bar.dart';
import '../widgets/update_dialog.dart';
import '../widgets/voice_input_bar.dart';
import '../services/network_content_intro_store.dart';
import '../services/network_copy_policy.dart';

/// 在后台 isolate 解码/缩放/JPEG 编码（12MP+ 照片解码是数百 ms 级 CPU 工作，
/// 主 isolate 执行会冻结 UI）。image 包为纯 Dart，可直接跨 isolate 传 bytes。
/// 失败抛异常由调用方捕获处理。
Uint8List _compressImageForChat(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('image decode failed');
  }
  var resized = decoded;
  if (decoded.width >= decoded.height && decoded.width > 1568) {
    resized = img.copyResize(decoded, width: 1568);
  } else if (decoded.height > decoded.width && decoded.height > 1568) {
    resized = img.copyResize(decoded, height: 1568);
  }
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _sendTrigger = 0;
  final FocusNode _inputFocus = FocusNode();
  bool _multiSelectMode = false;
  final Set<int> _selectedIndices = {};
  // 多选模式下当前可见的消息 index（visibility_detector 上报，>50% 可见）
  final Set<int> _visibleIndices = {};
  final ScreenshotController _screenshotController = ScreenshotController();

  String? _lastAgentId;
  bool _networkIntroDismissed = false;
  String? _networkIntroIdentity;

  // 图片暂存区（仿微信）：选图后不立即发送，缩略图挂在输入栏上方，
  // 可继续打字/增删，点发送后图文作为一条消息一起发出。
  // 元素为压缩后的本地文件路径，上限 VisionMessageBuilder.maxAttachedImages 张。
  final List<String> _pendingImages = [];

  // ── 语音输入 ──
  // 语音模式下输入框替换为语音栏：按住说话（识别结果实时上屏），松开后
  // 识别文本按模式包装（动作模式加全角括号）填入普通输入框并切回文字模式，
  // 用户可编辑后点发送；语音栏不再直接发出。
  final VoiceInputService _voiceService = VoiceInputService();
  bool _voiceMode = false;
  VoiceSendMode _voiceSendMode = VoiceSendMode.reply;
  String _voiceText = '';
  bool _voiceListening = false;
  // 识别服务最新状态（listening/done/notListening...），区分"正在启动"
  // 与"正在聆听"，让按住期间语音栏始终有可见反馈
  String _voiceStatus = '';
  // 识别服务回调的音量电平（约 -2~10 dB），驱动语音栏收音指示条
  double _voiceSoundLevel = 0;
  // 一次"按住-松开"会话是否还在接收识别回调；松开后置 false，
  // 忽略 stop 之后才送达的迟到结果，避免重复填入输入框
  bool _acceptingVoiceResults = false;

  bool _subBannerDismissed = false;
  String? _subBannerHideDate;
  static const _keyBannerHide = 'sub_banner_hide_date';

  // ── 多端同步：聊天锁 ──
  bool _syncBlockedByOther = false;
  bool _wasLoading = false;
  LockCallback? _prevLockCallback;

  @override
  void initState() {
    super.initState();
    _loadBannerPrefs();

    _controller.addListener(_onInputOrFocusChanged);
    _inputFocus.addListener(_onInputOrFocusChanged);

    // 滚动到顶部附近时加载更早的历史消息（分页加载，见 chatProvider.loadEarlierMessages）
    _scrollController.addListener(_onScrollLoadEarlier);

    // 注册聊天锁回调（接管全局回调，dispose 时还原）
    _prevLockCallback = SyncWebSocketService.instance.onLockChange;
    SyncWebSocketService.instance.onLockChange = _onSyncLockChange;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.unfocus();
      _jumpToBottomSettling();
      // 注意：planService.onPlanTriggered 由 main.dart 全局注册（调用 deliverPlannedMessage
      // 让 AI 主动发言），此处不再覆盖，避免计划消息退化为系统消息
      final notificationService = ref.read(notificationServiceProvider);
      notificationService.onNotificationTapped = (id) {
        ref.read(planServiceProvider).deliverFromNotification(id);
      };
      UpdateService.addListener(_onUpdateStateChanged);
      notificationService.onAiMessageTapped = (payload) {
        // 主动关心通知：交给 main.dart 的全局处理器（切换智能体并跳转聊天页）
        if (payload != null && payload.startsWith('proactive:')) {
          proactiveCareNotificationHandler?.call(payload);
          return;
        }
        if (payload != null && payload.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                payload.length > 100
                    ? '${payload.substring(0, 100)}...'
                    : payload,
              ),
            ),
          );
        }
      };
      // 进入聊天页时补一次主动关心检查
      unawaited(ProactiveCareService.instance.checkAndTrigger());
    });
  }

  void _onSyncLockChange(
    bool lockedByOther,
    String? deviceName,
    String? status,
  ) {
    if (!mounted) return;
    _syncBlockedByOther = lockedByOther;
    if (lockedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('syncChatConflict')),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }

  void _onInputOrFocusChanged() {
    if (mounted) setState(() {});
  }

  // 滚动接近顶部时触发向上翻页；加载中为防重入由 provider 侧状态守卫
  void _onScrollLoadEarlier() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= 120) return;
    final chatState = ref.read(chatProvider);
    if (!chatState.hasMoreMessages || chatState.isLoading) return;
    ref.read(chatProvider.notifier).loadEarlierMessages();
  }

  @override
  void dispose() {
    // 还原全局回调
    SyncWebSocketService.instance.onLockChange = _prevLockCallback;
    // 清理其他全局回调，避免销毁后被调用访问失效 ref
    // 注意：planService.onPlanTriggered 由 main.dart 全局管理，不在 chat_screen 清理
    final notificationService = ref.read(notificationServiceProvider);
    if (notificationService.onNotificationTapped != null) {
      notificationService.onNotificationTapped = null;
    }
    // 恢复 main.dart 注册的主动关心通知处理（而不是置空丢失）
    notificationService.onAiMessageTapped = (payload) {
      if (payload != null) proactiveCareNotificationHandler?.call(payload);
    };
    UpdateService.removeListener(_onUpdateStateChanged);
    // 退出时释放当前会话锁
    final agentId = ref.read(agentProvider).currentAgent?.id;
    if (agentId != null) {
      SyncWebSocketService.instance.releaseLock(agentId: agentId.toString());
    }
    _controller.removeListener(_onInputOrFocusChanged);
    _inputFocus.removeListener(_onInputOrFocusChanged);
    // 离开聊天页清空暂存区（压缩临时文件可留，下次进入为空）
    _pendingImages.clear();
    _voiceService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// AI 正在回复（chatProvider.isLoading，含流式与发送后的等待期）时拦截提交。
  /// UI 按钮禁用只是体验层，这里是兜底（回车/Ctrl+Enter/贴纸回调等路径
  /// 仍可能触发）；拦截时保留输入框文字。
  bool _isAiReplying() {
    if (!ref.read(chatProvider).isLoading) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).get('peerReplying')),
        duration: const Duration(seconds: 2),
      ),
    );
    return true;
  }

  Future<void> _sendMessage() async {
    // 同步冲突拦截
    if (_syncBlockedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('syncChatConflict')),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }
    // AI 回复中禁止再发（输入保留）
    if (_isAiReplying()) return;
    // 语音草稿在松开时已填入输入框，这里统一取输入框文本
    final inputText = _controller.text;
    final text = inputText.trim();
    // 暂存图片随文字一起作为一条消息发出
    final pending = List<String>.from(_pendingImages);
    if (text.isEmpty && pending.isEmpty) return;

    // 获取服务端聊天锁确认后才真正发送，避免冲突通知尚未到达时双端并发。
    final agentId = ref.read(agentProvider).currentAgent?.id;
    if (agentId != null) {
      final acquired = await SyncWebSocketService.instance.acquireLock(
        agentId: agentId,
        status: 'waiting',
      );
      if (!mounted) {
        if (acquired) {
          await SyncWebSocketService.instance.releaseLock(agentId: agentId);
        }
        return;
      }
      if (!acquired) {
        if (!_syncBlockedByOther) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).get('syncChatConflict'),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        }
        return;
      }
      if (ref.read(agentProvider).currentAgent?.id != agentId) {
        await SyncWebSocketService.instance.releaseLock(agentId: agentId);
        return;
      }
    }

    if (_controller.text == inputText) {
      _controller.clear();
    }
    if (pending.isNotEmpty) {
      setState(() {
        _pendingImages.removeWhere(pending.contains);
      });
    }
    _sendTrigger++;
    final sent = await ref
        .read(chatProvider.notifier)
        .sendMessage(text, imagePaths: pending.isEmpty ? null : pending);
    // 发送失败（退配额/识别失败/网络错误等）：恢复暂存区
    // （暂存的压缩文件未删除，可直接复用；用户气泡已留在历史中）
    if (!sent && pending.isNotEmpty && mounted && _pendingImages.isEmpty) {
      setState(() => _pendingImages.addAll(pending));
    }
    _inputFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // ═══ 语音输入 ═══

  void _toggleInputMode() {
    HapticFeedback.selectionClick();
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) _inputFocus.unfocus();
  }

  /// 按住说话：初始化（含权限申请、首次拷贝/加载语音模型）后开始识别，
  /// 结果实时显示在语音栏上。初始化/识别失败显示具体原因（errorMsg 映射）。
  Future<void> _startVoiceInput() async {
    if (_voiceListening) return;
    // 立即进入"启动中"视觉状态：首次初始化要拷贝/加载模型，可能耗时明显；
    // 每次新的长按开始，发送模式重置为语言（reply）
    setState(() {
      _voiceListening = true;
      _voiceText = '';
      _voiceStatus = '';
      _voiceSoundLevel = 0;
      _voiceSendMode = VoiceSendMode.reply;
    });
    // 初始化阶段的错误（含模型缺失）经 onError 回调送到这里
    String? initError;
    final ok = await _voiceService.initialize(
      onError: (msg) {
        initError = msg;
        if (!mounted) return;
        // 识别中途出错（会话已建立）：结束本次会话并提示具体原因；
        // 初始化期间的错误不在此提示（统一走下方 !ok 分支，避免重复提示）
        if (_acceptingVoiceResults) {
          _voiceService.cancelListening();
          setState(() {
            _voiceListening = false;
            _voiceStatus = '';
            _acceptingVoiceResults = false;
          });
          _showVoiceError(msg);
        }
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          // 仅更新麦克风视觉状态；结果提交统一在松开时进行
          setState(() {
            _voiceListening = false;
            _voiceStatus = status;
          });
        } else {
          // listening 等状态：驱动"正在聆听"状态文本
          setState(() => _voiceStatus = status);
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _voiceListening = false);
      _showVoiceError(initError);
      return;
    }
    if (!_voiceListening) {
      // 初始化期间用户已松手：不启动识别
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _acceptingVoiceResults = true);
    await _voiceService.startListening(
      onResult: (text, isFinal) {
        // 每次回调（含部分结果）都驱动 setState 实时上屏
        if (!mounted || !_acceptingVoiceResults) return;
        setState(() => _voiceText = text);
      },
      onSoundLevelChange: (level) {
        if (!mounted || !_acceptingVoiceResults) return;
        setState(() => _voiceSoundLevel = level);
      },
    );
  }

  /// 识别失败提示：按 errorMsg 映射具体原因，未知错误附原始信息便于真机定位
  void _showVoiceError(String? errorMsg) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final String text;
    if (errorMsg == null || errorMsg.isEmpty) {
      // initialize 返回 false 但无 errorMsg：绝大多数是模型缺失/权限被拒
      text = l10n.get('voiceErrorModelMissing');
    } else {
      final kind = voiceErrorKindFor(errorMsg);
      text = kind == VoiceErrorKind.unknown
          ? '${l10n.get('voiceErrorGeneric')}（$errorMsg）'
          : l10n.get(voiceErrorL10nKey(kind));
    }
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// 松开/被打断（滑动接管手势）都按"结束识别"处理：
  /// 停止识别后把已识别文本提交到普通输入框（可编辑后再发送）。
  Future<void> _stopVoiceInput() async {
    if (!_voiceListening && !_acceptingVoiceResults) return;
    if (!_acceptingVoiceResults) {
      // 初始化期间就松手：取消本次启动（_startVoiceInput 初始化返回后不会启动识别）
      setState(() => _voiceListening = false);
      return;
    }
    // stopListening 返回前会回调一次最终结果（含尾部音频），此时仍接受结果
    await _voiceService.stopListening();
    if (!mounted) return;
    setState(() {
      _voiceListening = false;
      _acceptingVoiceResults = false;
      _voiceSoundLevel = 0;
    });
    _commitVoiceDraft();
  }

  /// 把语音草稿按当前模式包装后填入文字输入框并切回文字模式，
  /// 光标置于末尾；空文本保持语音模式不变并提示"未识别到内容"。
  void _commitVoiceDraft() {
    final text = wrapVoiceRecognizedText(_voiceText, _voiceSendMode);
    if (text.isEmpty) {
      setState(() => _voiceText = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('voiceNoContent')),
        ),
      );
      return;
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _voiceText = '';
      _voiceMode = false;
    });
    _inputFocus.requestFocus();
  }

  /// 按住说话期间手指在语音栏左右半侧间滑动切换模式：
  /// 以栏宽中线为界按实时位置判定（左半 语言 / 右半（动作）），
  /// 来回滑动来回切换；切换时给震动反馈，分段胶囊实时高亮。
  void _onVoiceSlide(double dx, double width) {
    if (!_voiceListening) return;
    final next = voiceModeForPosition(dx, width);
    if (next == _voiceSendMode) return;
    HapticFeedback.selectionClick();
    setState(() => _voiceSendMode = next);
  }

  Future<void> _showStickerPanel() async {
    final stickers = await StickerService.listActive();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => StickerPanel(
        stickers: stickers,
        onSelected: (sticker) {
          Navigator.of(context).pop();
          _sendSticker(sticker);
        },
        onChanged: () async {},
      ),
    );
  }

  Future<void> _sendSticker(Sticker sticker) async {
    if (_syncBlockedByOther) return;
    // AI 回复中禁止再发
    if (_isAiReplying()) return;
    final inputText = _controller.text;
    final text = inputText.trim();
    final agentId = ref.read(agentProvider).currentAgent?.id;
    if (agentId != null) {
      final acquired = await SyncWebSocketService.instance.acquireLock(
        agentId: agentId,
        status: 'waiting',
      );
      if (!mounted) {
        if (acquired) {
          await SyncWebSocketService.instance.releaseLock(agentId: agentId);
        }
        return;
      }
      if (!acquired) {
        if (!_syncBlockedByOther) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).get('syncChatConflict'),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        }
        return;
      }
      if (ref.read(agentProvider).currentAgent?.id != agentId) {
        await SyncWebSocketService.instance.releaseLock(agentId: agentId);
        return;
      }
    }
    if (_controller.text == inputText) {
      _controller.clear();
    }
    _sendTrigger++;
    await ref.read(chatProvider.notifier).sendMessage(text, sticker: sticker);
    _inputFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// 选图 → 压缩 → 落盘 chat_images/ → 加入输入栏上方的暂存区（不立即发送）。
  /// 点发送后暂存图随文字一起作为一条消息发出（见 _sendMessage）。
  /// 所选模型既非原生视觉也未绑定视觉模型时不打开选图，直接提示。
  Future<void> _pickAndStageImage() async {
    if (_syncBlockedByOther) return;
    // AI 回复中禁止添加暂存图
    if (_isAiReplying()) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    // 暂存区上限（与上下文挂图上限一致）：达到后提示，不再打开选图
    if (_pendingImages.length >= VisionMessageBuilder.maxAttachedImages) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('imageLimitReached')),
          backgroundColor: scheme.errorContainer,
        ),
      );
      return;
    }

    final selectedModel = ref.read(settingsProvider).selectedModel;
    final modelId = selectedModel.isEmpty
        ? ModelListService.defaultModel
        : selectedModel;
    var modelInfo = ModelListService.findById(
      ref.read(modelListProvider).models,
      modelId,
    );
    if (modelInfo == null) {
      // 缓存列表里查不到（启动早期列表未拉到）：先刷新一次再查。
      // 刷新失败或仍查不到 → 能力未知，fail-open 放行让服务器裁决，
      // 不再误报"不支持视觉"；只有明确查到 canSeeImages==false 才拦截。
      await ref.read(modelListProvider.notifier).refresh();
      if (!mounted) return;
      modelInfo = ModelListService.findById(
        ref.read(modelListProvider).models,
        modelId,
      );
    }
    if (!ModelListService.canSendImages(modelInfo)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('imageModelNotSupported')),
          backgroundColor: scheme.errorContainer,
        ),
      );
      return;
    }

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    // 压缩：最长边 ≤1568，JPEG quality 85。在后台 isolate 执行，避免冻结 UI
    final bytes = await picked.readAsBytes();
    final Uint8List jpg;
    try {
      jpg = await compute(_compressImageForChat, bytes);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('imagePickFailed')),
          backgroundColor: scheme.errorContainer,
        ),
      );
      return;
    }

    final dir = await pp.getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/chat_images');
    await imagesDir.create(recursive: true);
    final file = File('${imagesDir.path}/${const Uuid().v4()}.jpg');
    await file.writeAsBytes(jpg);
    if (!mounted) return;
    // 选图/压缩期间 AI 开始回复或暂存区已满（连续快速点图）：
    // 放弃暂存并清理刚写出的压缩文件，避免临时文件泄漏
    if (_pendingImages.length >= VisionMessageBuilder.maxAttachedImages) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('imageLimitReached')),
          backgroundColor: scheme.errorContainer,
        ),
      );
      try {
        await file.delete();
      } catch (_) {}
      return;
    }
    if (_isAiReplying()) {
      try {
        await file.delete();
      } catch (_) {}
      return;
    }
    // 加入暂存区而不是发送：缩略图出现在输入栏上方，可继续打字/增删
    setState(() => _pendingImages.add(file.path));
  }

  /// 移除暂存图（点缩略图右上角 ×）：同时删除压缩临时文件
  Future<void> _removePendingImage(int index) async {
    if (index < 0 || index >= _pendingImages.length) return;
    final path = _pendingImages.removeAt(index);
    setState(() {});
    // 暂存图是压缩产生的临时文件，删除时一并清理（失败可留，不影响功能）
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _loadBannerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyBannerHide);
    if (saved != null && saved == _todayStr()) {
      if (mounted) setState(() => _subBannerHideDate = saved);
    }
  }

  String _todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _dismissBannerToday() async {
    final today = _todayStr();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBannerHide, today);
    if (mounted) {
      setState(() {
        _subBannerHideDate = today;
        _subBannerDismissed = true;
      });
    }
  }

  void _sendMessageOrImage() {
    _sendMessage();
  }

  void _scrollAfterBuild(int ms) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 进入聊天页/切换智能体时的初始定位：直接 jump（无动画），
  /// 并在随后 1 秒内多次重试——ListView.builder 惰性布局初期
  /// maxScrollExtent 被低估，单次滚动会停在半中间。
  void _jumpToBottomSettling() {
    for (final ms in [50, 150, 300, 600, 1000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
  }

  void _onDeleteMessage(int index) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmDelete')),
        content: Text(
          l10n.get('deleteMessageConfirm'),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () {
              ref.read(chatProvider.notifier).deleteMessageFrom(index);
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  /// 重写 AI 消息：预填当前内容，保存后聊天表与短期记忆同步改写
  void _onRewriteMessage(int index) {
    final l10n = AppLocalizations.of(context);
    final msgs = ref.read(chatProvider).messages;
    if (index < 0 || index >= msgs.length) return;
    final msg = msgs[index];
    if (msg.isUser || msg.isStreaming) return;

    final controller = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.edit_note_rounded,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: Text(l10n.get('rewrite')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 3,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: l10n.get('rewriteHint'),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(chatProvider.notifier)
                  .rewriteMessage(index, controller.text);
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    ref.listen<AgentState>(agentProvider, (prev, next) {
      final newId = next.currentAgent?.id;
      if (newId != null && newId != _lastAgentId) {
        // 切换智能体前先释放旧 agent 的同步锁（如有）
        if (_lastAgentId != null) {
          SyncWebSocketService.instance.releaseLock(agentId: _lastAgentId!);
        }
        _lastAgentId = newId;
        _syncBlockedByOther = false;
        _wasLoading = false;
        // 切换智能体时清空暂存区（临时文件可留，避免跨智能体误发）
        _pendingImages.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _jumpToBottomSettling();
          }
        });
      }
    });

    ref.listen<ChatState>(chatProvider, (prev, next) {
      if (next.messages.length > (prev?.messages.length ?? 0) &&
          !next.isLoading) {
        _scrollAfterBuild(100);
      }
      // 余额不足 → 弹出充值弹窗
      if (next.error != null &&
          next.error != prev?.error &&
          next.error!.contains('余额不足')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error!),
              action: SnackBarAction(
                label: AppLocalizations.of(context).get('goToSubscribe'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionCenterScreen(),
                    ),
                  );
                },
              ),
            ),
          );
        });
      }
      // 同步锁：isLoading 从 true → false 表示 AI 回复完成，释放锁
      if (_wasLoading && !next.isLoading) {
        final agentId = ref.read(agentProvider).currentAgent?.id;
        if (agentId != null) {
          SyncWebSocketService.instance.releaseLock(
            agentId: agentId.toString(),
          );
        }
        _syncBlockedByOther = false;
      }
      _wasLoading = next.isLoading;
    });

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  // ═══ Mobile Layout (existing) ═══
  Widget _buildMobileLayout() {
    final chatState = ref.watch(chatProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final agent = ref.watch(agentProvider.select((s) => s.currentAgent));
    final appTitle = agent?.name ?? l10n.get('appTitle');
    // 背景延伸到顶栏区域：extendBodyBehindAppBar + 顶栏半透明高斯模糊
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: scheme.surface.withValues(alpha: 0.55),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: const SizedBox.expand(),
          ),
        ),
        leading: _multiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMultiSelect,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        title: _multiSelectMode
            ? Text(
                l10n.getP('selectedCount', {'n': '${_selectedIndices.length}'}),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Text(
                appTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
        actions: _multiSelectMode
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.storage),
                  tooltip: l10n.get('memoryManagement'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemoryScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.schedule),
                  tooltip: l10n.get('plannedMessages'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanScreen()),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    final agent = ref.read(agentProvider).currentAgent;
                    if (v == 'edit_agent' && agent != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgentCreateScreen(agent: agent),
                        ),
                      );
                    } else if (v == 'share_agent' && agent != null) {
                      _shareCurrentAgent();
                    } else if (v == 'global_settings') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AccountScreen(),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit_agent',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.get('editAgent')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share_agent',
                      child: Row(
                        children: [
                          const Icon(Icons.ios_share, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.get('shareAgent')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'global_settings',
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.get('accountManagement')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: _buildChatBody(chatState, topPadding: topPadding),
    );
  }

  // ═══ Desktop Layout (new) ═══
  Widget _buildDesktopLayout() {
    final chatState = ref.watch(chatProvider);
    final l10n = AppLocalizations.of(context);
    final agentState = ref.watch(agentProvider);
    final appTitle = agentState.currentAgent?.name ?? l10n.get('appTitle');

    return Scaffold(
      appBar: AppBar(
        title: _multiSelectMode
            ? Text(
                l10n.getP('selectedCount', {'n': '${_selectedIndices.length}'}),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Text(
                appTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
        actions: _multiSelectMode
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.storage),
                  tooltip: l10n.get('memoryManagement'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemoryScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.schedule),
                  tooltip: l10n.get('plannedMessages'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: l10n.get('shareAgent'),
                  onPressed: agentState.currentAgent == null
                      ? null
                      : _shareCurrentAgent,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: ResponsiveLayout.sidebarWidth,
            child: ChatDesktopSidebar(onSwitchAgent: _switchAgent),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildChatBody(chatState)),
        ],
      ),
    );
  }

  void _shareCurrentAgent() {
    final agent = ref.read(agentProvider).currentAgent;
    if (agent == null) return;
    final jwt = ref.read(authProvider).jwtToken;
    showDialog(
      context: context,
      builder: (_) => AgentShareDialog(agent: agent, jwt: jwt),
    );
  }

  void _toggleSelect(int index) => setState(() {
    if (_selectedIndices.contains(index)) {
      _selectedIndices.remove(index);
      if (_selectedIndices.isEmpty) _multiSelectMode = false;
    } else {
      _selectedIndices.add(index);
    }
  });

  void _enterMultiSelect(int index) => setState(() {
    _multiSelectMode = true;
    _selectedIndices.add(index);
  });

  /// 微信式"选到这里"：以最早选中的消息为锚点，批量选中到本条
  void _selectRangeTo(int index) => setState(() {
    _selectedIndices.addAll(selectRangeTo(_selectedIndices, index));
  });

  /// 多选大滑动后，锚点（最早选中消息）是否已滚出可视区
  bool get _showSelectToHereButton {
    if (!_multiSelectMode ||
        _selectedIndices.isEmpty ||
        _visibleIndices.isEmpty) {
      return false;
    }
    final anchor = _selectedIndices.reduce((a, b) => a < b ? a : b);
    final first = _visibleIndices.reduce((a, b) => a < b ? a : b);
    final last = _visibleIndices.reduce((a, b) => a > b ? a : b);
    return anchor < first - 1 || anchor > last + 1;
  }

  /// 点击浮动"选到这里"：从锚点批量选中到当前可视区边缘
  void _selectRangeToVisibleEdge() {
    final anchor = _selectedIndices.reduce((a, b) => a < b ? a : b);
    final first = _visibleIndices.reduce((a, b) => a < b ? a : b);
    final last = _visibleIndices.reduce((a, b) => a > b ? a : b);
    final target = anchor < first ? first : last;
    setState(() {
      _selectedIndices.addAll(selectRangeTo(_selectedIndices, target));
    });
  }

  void _exitMultiSelect() => setState(() {
    _multiSelectMode = false;
    _selectedIndices.clear();
    _visibleIndices.clear();
  });

  Future<void> _switchAgent(Agent a, Agent? current) async {
    if (a.id == current?.id) return;
    await ref.read(agentProvider.notifier).setActiveAgent(a.id);
  }

  bool _quotaDialogShowing = false;

  void _checkQuotaExceeded(ChatState chatState) {
    final quota = chatState.quotaExceeded;
    // 防重入：状态清除前的任何 rebuild 不应重复弹窗
    if (quota == null || !mounted || _quotaDialogShowing) return;
    _quotaDialogShowing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _quotaDialogShowing = false;
        return;
      }
      final scheme = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.workspace_premium, color: scheme.primary, size: 32),
          title: Text(
            quota == QuotaType.ocr
                ? l10n.get('chatHistoryRecognition')
                : l10n.get('realReplyConversation'),
          ),
          content: Text(
            quota == QuotaType.ocr
                ? l10n.get('quotaOcrExceededMsg')
                : l10n.get('quotaRealReplyExceededMsg'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(chatProvider.notifier).clearQuotaExceeded();
              },
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(chatProvider.notifier).clearQuotaExceeded();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionCenterScreen(),
                  ),
                );
              },
              child: Text(l10n.get('goToSubscribe')),
            ),
          ],
        ),
      ).then((_) => _quotaDialogShowing = false);
    });
  }

  // ═══ Shared Chat Body ═══
  /// [topPadding] 移动端 extendBodyBehindAppBar 时传入顶栏高度，
  /// 让背景图延伸到顶栏下方（顶栏半透明高斯模糊盖在背景上）
  Widget _buildChatBody(ChatState chatState, {double topPadding = 0}) {
    _checkQuotaExceeded(chatState);
    return Builder(
      builder: (ctx) {
        final agent = ref.watch(agentProvider).currentAgent;
        final agentId = agent?.id;
        final bg = agent?.chatBackground;
        final networkIntroAgent = _shouldShowNetworkIntro(agent) ? agent : null;
        _syncNetworkIntroVisibility(agent);

        if (chatState.messages.isEmpty &&
            !chatState.isLoading &&
            agent == null) {
          final scheme = Theme.of(context).colorScheme;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_add_alt,
                    size: 40,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context).get('noAgentSelected'),
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(AppLocalizations.of(context).get('createAgent')),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AgentCreateScreen(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget body = Column(
          children: [
            _buildSubBanner(),
            _buildSessionBanner(),
            if (networkIntroAgent case final introAgent?)
              NetworkContentIntroCard.agent(
                agent: introAgent,
                onDismiss: () => _dismissNetworkIntro(introAgent),
              ),
            Expanded(
              key: ValueKey('chat_list_$agentId'),
              child: Stack(
                children: [
                  Screenshot(
                    controller: _screenshotController,
                    child: chatState.messages.isEmpty && !chatState.isLoading
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: chatState.messages.length,
                            itemBuilder: (context, index) {
                              final msg = chatState.messages[index];
                              final isSelected = _selectedIndices.contains(
                                index,
                              );
                              final bubble = AnimatedChatBubble(
                                key: ValueKey(
                                  msg.dbId ??
                                      msg.timestamp.millisecondsSinceEpoch,
                                ),
                                message: msg,
                                onDelete: () => _onDeleteMessage(index),
                                onRegenerate: !msg.isUser
                                    ? () {
                                        ref
                                            .read(chatProvider.notifier)
                                            .regenerateMessage(index);
                                      }
                                    : null,
                                onRewrite: !msg.isUser && !msg.isStreaming
                                    ? () => _onRewriteMessage(index)
                                    : null,
                                showCheckbox: _multiSelectMode,
                                isSelected: isSelected,
                                onTap: _multiSelectMode
                                    ? () => _toggleSelect(index)
                                    : null,
                                onMultiSelect: () => _enterMultiSelect(index),
                                onSelectToHere: _multiSelectMode
                                    ? () => _selectRangeTo(index)
                                    : null,
                              );
                              // 微信式时间分割线：首条或间隔超过阈值时显示
                              final prev = index > 0
                                  ? chatState.messages[index - 1]
                                  : null;
                              Widget item = bubble;
                              if (shouldShowTimeDivider(
                                msg.timestamp,
                                prev?.timestamp,
                              )) {
                                item = Column(
                                  children: [
                                    TimeDivider(time: msg.timestamp),
                                    bubble,
                                  ],
                                );
                              }
                              // 多选模式下上报可见性，用于"选到这里"浮动按钮
                              if (_multiSelectMode) {
                                item = VisibilityDetector(
                                  key: ValueKey('vis_$index'),
                                  onVisibilityChanged: (info) {
                                    final visible = info.visibleFraction > 0.5;
                                    if (visible ==
                                        _visibleIndices.contains(index)) {
                                      return;
                                    }
                                    setState(() {
                                      if (visible) {
                                        _visibleIndices.add(index);
                                      } else {
                                        _visibleIndices.remove(index);
                                      }
                                    });
                                  },
                                  child: item,
                                );
                              }
                              return item;
                            },
                          ),
                  ),
                  if (_inputFocus.hasFocus)
                    GestureDetector(
                      onTap: () => _inputFocus.unfocus(),
                      behavior: HitTestBehavior.opaque,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                  // 多选大滑动后浮动"选到这里"按钮
                  if (_showSelectToHereButton)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FilledButton.tonalIcon(
                        onPressed: _selectRangeToVisibleEdge,
                        icon: const Icon(
                          Icons.playlist_add_check_rounded,
                          size: 18,
                        ),
                        label: Text(
                          AppLocalizations.of(context).get('selectToHere'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (chatState.isLoading) const BouncingDotsIndicator(),
            if (chatState.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  chatState.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_multiSelectMode) _buildMultiSelectBar(),
            _buildInputArea(),
          ],
        );
        // 顶部让出 AppBar 区域（extendBodyBehindAppBar），
        // 有自定义背景时背景盖满顶栏下方，内容下移
        if (topPadding > 0) {
          body = Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: body,
          );
        }
        if (bg != null) {
          if (bg.startsWith('#')) {
            body = Container(
              color: Color(int.parse(bg.substring(1), radix: 16) | 0xFF000000),
              child: body,
            );
          } else if (!kIsWeb && File(bg).existsSync()) {
            body = Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(bg)),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.8),
                    BlendMode.dstATop,
                  ),
                ),
              ),
              child: body,
            );
          }
        }
        // Tap blank area to dismiss keyboard
        return GestureDetector(
          onTap: () => _inputFocus.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: body,
        );
      },
    );
  }

  bool _shouldShowNetworkIntro(Agent? agent) =>
      agent?.networkSource == NetworkCopySource.downloaded &&
      agent?.networkId != null &&
      !_networkIntroDismissed;

  void _syncNetworkIntroVisibility(Agent? agent) {
    final identity =
        agent?.networkSource == NetworkCopySource.downloaded &&
            agent?.networkId != null
        ? '${agent!.networkId}:${agent.networkVersion}'
        : null;
    if (identity == _networkIntroIdentity) return;
    _networkIntroIdentity = identity;
    _networkIntroDismissed = identity == null;
    if (agent == null || agent.networkId == null || identity == null) return;
    NetworkContentIntroStore.isDismissed(
      type: 'agent',
      networkId: agent.networkId!,
      version: agent.networkVersion,
    ).then((dismissed) {
      if (mounted && _networkIntroIdentity == identity) {
        setState(() => _networkIntroDismissed = dismissed);
      }
    });
  }

  Future<void> _dismissNetworkIntro(Agent agent) async {
    setState(() => _networkIntroDismissed = true);
    if (agent.networkId == null) return;
    await NetworkContentIntroStore.dismiss(
      type: 'agent',
      networkId: agent.networkId!,
      version: agent.networkVersion,
    );
  }

  Widget _buildSubBanner() {
    final authState = ref.watch(authProvider);
    final days = authState.subRemainingDays;
    final sub = authState.subscription;
    if (days == null || sub == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    String text;
    IconData icon;
    Color bgColor;
    Color iconColor;

    if (days < 0) {
      text = l10n.get('subExpired');
      icon = Icons.error_outline;
      bgColor = scheme.errorContainer;
      iconColor = scheme.error;
    } else if (days == 0) {
      text = l10n.get('subExpireToday');
      icon = Icons.warning_amber_rounded;
      bgColor = scheme.tertiaryContainer;
      iconColor = scheme.tertiary;
    } else if (days <= 3) {
      text = '${l10n.get('subExpireSoon')} $days${l10n.get('days')}';
      icon = Icons.warning_amber_rounded;
      bgColor = scheme.tertiaryContainer;
      iconColor = scheme.tertiary;
    } else if (days <= 7) {
      text = '${l10n.get('subExpireSoon')} $days${l10n.get('days')}';
      icon = Icons.info_outline;
      bgColor = scheme.primaryContainer;
      iconColor = scheme.primary;
    } else {
      return const SizedBox.shrink();
    }

    if (_subBannerDismissed || _subBannerHideDate == _todayStr()) {
      return const SizedBox.shrink();
    }

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, color: iconColor, size: 20),
      backgroundColor: bgColor,
      content: Text(text, style: TextStyle(fontSize: 13, color: iconColor)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SubscriptionCenterScreen(),
              ),
            );
          },
          child: Text(
            l10n.get('subscribe'),
            style: TextStyle(fontSize: 12, color: iconColor),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.close,
            size: 16,
            color: iconColor.withValues(alpha: 0.6),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: l10n.get('close'),
          onPressed: () => setState(() => _subBannerDismissed = true),
        ),
        TextButton(
          onPressed: _dismissBannerToday,
          style: TextButton.styleFrom(
            foregroundColor: iconColor.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Text(
            l10n.get('dontShowToday'),
            style: TextStyle(
              fontSize: 11,
              color: iconColor.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionBanner() {
    final authState = ref.watch(authProvider);
    if (!authState.sessionExpired) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Icon(
        Icons.power_off_rounded,
        color: scheme.onErrorContainer,
        size: 20,
      ),
      backgroundColor: scheme.error,
      content: Text(
        authState.refreshToken == null
            ? l10n.get('sessionExpiredRelogin')
            : l10n.get('loginStateInvalidRelogin'),
        style: TextStyle(fontSize: 13, color: scheme.onError),
      ),
      actions: [
        TextButton(
          onPressed: () => ref.read(authProvider.notifier).logout(),
          child: Text(
            l10n.get('logout'),
            style: TextStyle(fontSize: 12, color: scheme.onError),
          ),
        ),
      ],
    );
  }

  /// UpdateService 状态变化回调
  /// 只处理非强制更新弹窗；强制更新由 _AppShell 全屏拦截，不会进入 chat_screen
  void _onUpdateStateChanged() {
    if (!mounted) return;
    final update = UpdateService.availableUpdate;
    if (update == null) return;
    // 强制更新由 main.dart 的 _AppShell 拦截，不在此弹窗
    if (update.isForce) return;
    _showUpdateDialog();
  }

  /// 显示更新提示弹窗（实现已抽至 widgets/update_dialog.dart）
  void _showUpdateDialog() => showAppUpdateDialog(context);

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer.withValues(alpha: 0.7),
                    scheme.primary.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: AppTheme.primaryShadowSm(scheme),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 44,
                color: scheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.get('startChat'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('startChatSub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectBar() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.primary.withValues(alpha: 0.15)),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _exitMultiSelect,
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            label: Text(
              l10n.getP('selectedMessagesShort', {
                'n': '$_selectedIndicesCount',
              }),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: l10n.get('screenshot'),
            icon: const Icon(Icons.screenshot_monitor, size: 20),
            onPressed: _screenshotSelected,
          ),
          IconButton(
            tooltip: l10n.get('copy'),
            icon: const Icon(Icons.copy, size: 20),
            onPressed: _copySelected,
          ),
          IconButton(
            tooltip: l10n.get('aiPolish'),
            icon: const Icon(Icons.auto_awesome, size: 20),
            onPressed: () => _aiPolishSelected(context),
          ),
          IconButton(
            tooltip: l10n.get('delete'),
            icon: Icon(Icons.delete, size: 20, color: scheme.error),
            onPressed: _deleteSelected,
          ),
        ],
      ),
    );
  }

  int get _selectedIndicesCount => _selectedIndices.length;

  void _copySelected() {
    final chatState = ref.read(chatProvider);
    final buffer = StringBuffer();
    for (final idx in _selectedIndices.toList()..sort()) {
      if (idx < chatState.messages.length) {
        buffer.writeln(chatState.messages[idx].content);
        buffer.writeln();
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _exitMultiSelect();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          ).getP('copiedMessages', {'n': '$_selectedIndicesCount'}),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _screenshotSelected() async {
    try {
      final imageBytes = await _screenshotController.capture();
      if (imageBytes == null || !mounted) return;
      final dir = await pp.getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(imageBytes);
      // 同时写入系统相册（仅移动端；桌面端不支持则跳过）
      var savedToGallery = false;
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          if (await Gal.hasAccess() || await Gal.requestAccess()) {
            await Gal.putImage(path);
            savedToGallery = true;
          }
        } catch (_) {}
      }
      _exitMultiSelect();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedToGallery
                  ? l10n.get('screenshotSavedToGallery')
                  : l10n.getP('screenshotSaved', {'path': path}),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).getP('screenshotFailed', {'error': '$e'}),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _deleteSelected() {
    final sorted = List.from(_selectedIndices)..sort((a, b) => b.compareTo(a));
    _exitMultiSelect();
    for (final idx in sorted) {
      ref.read(chatProvider.notifier).deleteMessageFrom(idx);
    }
  }

  void _aiPolishSelected(BuildContext context) async {
    final chatState = ref.read(chatProvider);
    final buffer = StringBuffer();
    final sorted = _selectedIndices.toList()..sort();
    for (final idx in sorted) {
      if (idx < chatState.messages.length) {
        final msg = chatState.messages[idx];
        buffer.writeln('${msg.isUser ? 'User' : 'AI'}: ${msg.content}');
      }
    }
    final text = buffer.toString();
    if (text.trim().isEmpty) return;
    _exitMultiSelect();

    await showNovelPolishDialog(
      context,
      text: text,
      readApiKey: () => ref.read(authProvider).apiKey ?? '',
    );
  }

  Widget _buildInputArea() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;
    final isFocused = _inputFocus.hasFocus;
    final isSending = ref.watch(chatProvider).isLoading;
    // AI 回复中禁用提交（输入框保持可编辑，提交由 _isAiReplying 兜底拦截）；
    // 有暂存图时无文字也可发送
    final canSend = ChatSendPolicy.canSend(
      hasText: hasText,
      hasPendingImages: _pendingImages.isNotEmpty,
      isSending: isSending,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.65),
          ),
          child: SafeArea(
            // extendBodyBehindAppBar 后 body 的 MediaQuery 保留顶部 inset，
            // 输入区只需底部 inset，否则会在输入条上方多出一段空白
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图片暂存区：缩略图横排，右上角 × 可删除，点发送随文字一起发出
                if (_pendingImages.isNotEmpty)
                  PendingImagesBar(
                    paths: _pendingImages,
                    onRemove: _removePendingImage,
                  ),
                AnimatedContainer(
                  duration: AppTheme.durFast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.72,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isFocused
                          ? scheme.primary.withValues(alpha: 0.35)
                          : scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isFocused
                            ? scheme.primary.withValues(alpha: 0.1)
                            : scheme.shadow.withValues(alpha: 0.06),
                        blurRadius: isFocused ? 14 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    // 图标按钮固定 38px 并置底对齐，多行输入时文本向上生长（仿微信）
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 文字/语音切换（不支持的平台隐藏，优雅降级）
                      if (VoiceInputService.platformSupported)
                        _buildInputIconButton(
                          tooltip: l10n.get(
                            _voiceMode ? 'keyboardInput' : 'voiceInput',
                          ),
                          icon: _voiceMode
                              ? Icons.keyboard_outlined
                              : Icons.mic_none_rounded,
                          onPressed: _toggleInputMode,
                        ),
                      Expanded(
                        child: _voiceMode
                            ? VoiceInputBar(
                                sendMode: _voiceSendMode,
                                listening: _voiceListening,
                                text: _voiceText,
                                status: _voiceStatus,
                                soundLevel: _voiceSoundLevel,
                                onHoldStart: _startVoiceInput,
                                onHoldSlide: _onVoiceSlide,
                                onHoldEnd: _stopVoiceInput,
                              )
                            : CallbackShortcuts(
                                bindings: {
                                  SingleActivator(
                                    LogicalKeyboardKey.enter,
                                    control: true,
                                  ): _sendMessageOrImage,
                                },
                                child: TextField(
                                  focusNode: _inputFocus,
                                  controller: _controller,
                                  decoration: InputDecoration(
                                    hintText: l10n.get('typeMessage'),
                                    hintStyle: TextStyle(
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                    // 显式禁用全部描边：主题 inputDecorationTheme 的
                                    // enabledBorder 会盖过 border: InputBorder.none，
                                    // 造成“框中框”的双重边框观感
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 8,
                                    ),
                                  ),
                                  maxLines: 5,
                                  minLines: 1,
                                  textInputAction: TextInputAction.newline,
                                  onSubmitted: (_) => _sendMessageOrImage(),
                                ),
                              ),
                      ),
                      if (!_voiceMode)
                        _buildInputIconButton(
                          tooltip: l10n.get('stickers'),
                          icon: Icons.emoji_emotions_outlined,
                          onPressed: isSending ? null : _showStickerPanel,
                        ),
                      if (!_voiceMode)
                        _buildInputIconButton(
                          tooltip: l10n.get('sendImage'),
                          icon: Icons.image_outlined,
                          onPressed: (kIsWeb || isSending)
                              ? null
                              : _pickAndStageImage,
                        ),
                      Tooltip(
                        message: 'Send (Ctrl+Enter)',
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(_sendTrigger),
                          tween: Tween(begin: 0.85, end: 1.0),
                          duration: AppTheme.durFast,
                          curve: Curves.easeOutBack,
                          builder: (ctx, value, child) =>
                              Transform.scale(scale: value, child: child),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: canSend
                                  ? scheme.primary
                                  : scheme.surfaceContainerHigh,
                              shape: BoxShape.circle,
                              boxShadow: canSend
                                  ? [
                                      BoxShadow(
                                        color: scheme.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: isSending ? null : _sendMessageOrImage,
                              child: Icon(
                                Icons.send_rounded,
                                color: canSend
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 输入栏图标按钮：38px 触控、21px 图标，禁用时降低透明度
  Widget _buildInputIconButton({
    required String tooltip,
    required IconData icon,
    VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        iconSize: 21,
        icon: Icon(
          icon,
          color: enabled
              ? scheme.onSurfaceVariant
              : scheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
