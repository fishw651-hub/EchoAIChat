import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:permission_handler/permission_handler.dart';
import '../models/agent.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/memory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/chat_runtime_policy.dart';
import '../config/server_config.dart';
import '../services/model_list_service.dart';
import '../services/network_copy_policy.dart';
import '../services/ocr_service.dart';
import '../services/quota_service.dart';
import '../services/ai_prompt_writer_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_cropper.dart';
import '../utils/screenshot_import_intro.dart';
import '../main.dart' show localeProvider;
import '../widgets/ai_prompt_writer_dialog.dart';
import '../widgets/creation_form_section.dart';
import 'subscription_center_screen.dart';
import 'network_market_screen.dart';
import 'draft_box_screen.dart';
import 'account_screen.dart';
import 'chat_screen.dart';
import 'network_upload_screen.dart';

class AgentCreateScreen extends ConsumerStatefulWidget {
  final Agent? agent;
  const AgentCreateScreen({super.key, this.agent});

  @override
  ConsumerState<AgentCreateScreen> createState() => _AgentCreateScreenState();
}

class _AgentCreateScreenState extends ConsumerState<AgentCreateScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _worldviewCtrl;
  String _gender = '';
  int _avatarColor = 0xFFE8F5E9;
  String? _avatarPath;
  String? _chatBackground;
  bool _useImageAvatar = false;
  bool _realInfoEnabled = false;
  bool _proactiveCareEnabled = false;
  int _proactiveCareDailyLimit = 1;
  int _proactiveCareMinIntervalHours = 3;
  int _maxResponseLength = Agent.defaultResponseLength;
  bool _ocrLoading = false;
  OcrChatResult? _ocrResult;

  static const _colors = [
    0xFFE8F5E9,
    0xFFFFF3E0,
    0xFFFCE4EC,
    0xFFE3F2FD,
    0xFFF3E5F5,
    0xFFE0F2F1,
    0xFFFFF8E1,
    0xFFFBE9E7,
    0xFFE8EAF6,
    0xFFF1F8E9,
    0xFFFFEBEE,
    0xFFECEFF1,
  ];

  static const _bgColors = [
    null,
    0xFFFFFFFF,
    0xFFFFF8E1,
    0xFFF5F5F5,
    0xFFE8F5E9,
    0xFFE3F2FD,
    0xFFFCE4EC,
    0xFFF3E5F5,
    0xFFE0F2F1,
  ];

  bool get isEditing => widget.agent != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    final locale = ref.read(localeProvider) ?? const Locale('zh');
    final l10n = AppLocalizations(locale);
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _personaCtrl = TextEditingController(
      text: a?.persona ?? l10n.get('defaultAgentPersona'),
    );
    _openingCtrl = TextEditingController(text: a?.openingLine ?? '');
    _worldviewCtrl = TextEditingController(text: a?.worldview ?? '');
    _gender = a?.gender ?? '';
    _avatarColor = a?.avatarColor ?? 0xFFE8F5E9;
    _avatarPath = a?.avatarPath;
    _chatBackground = a?.chatBackground;
    _useImageAvatar = _avatarPath != null && _avatarPath!.isNotEmpty;
    _realInfoEnabled = a?.realInfoEnabled ?? false;
    _proactiveCareEnabled = a?.proactiveCareEnabled ?? false;
    _proactiveCareDailyLimit = a?.proactiveCareDailyLimit ?? 1;
    _proactiveCareMinIntervalHours = a?.proactiveCareMinIntervalHours ?? 3;
    _maxResponseLength = a?.maxResponseLength ?? Agent.defaultResponseLength;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personaCtrl.dispose();
    _openingCtrl.dispose();
    _worldviewCtrl.dispose();
    super.dispose();
  }

  void _insertPlaceholder(String text) {
    final cursor = _personaCtrl.selection.baseOffset;
    final current = _personaCtrl.text;
    if (cursor >= 0 && cursor < current.length) {
      _personaCtrl.text =
          current.substring(0, cursor) + text + current.substring(cursor);
      _personaCtrl.selection = TextSelection.collapsed(
        offset: cursor + text.length,
      );
    } else {
      _personaCtrl.text = current + text;
      _personaCtrl.selection = TextSelection.collapsed(
        offset: _personaCtrl.text.length,
      );
    }
  }

  bool _saving = false;

  Future<Agent?> _persistAgent({bool requireOpeningLine = false}) async {
    if (_saving) return null;
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('nameRequired'))));
      return null;
    }
    final opening = _openingCtrl.text.trim();
    if (requireOpeningLine && !hasRequiredOpeningLine(opening)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('openingLineRequired'))));
      return null;
    }
    setState(() => _saving = true);
    try {
      final notifier = ref.read(agentProvider.notifier);
      final worldview = _worldviewCtrl.text.trim();
      // 主动关心仅 realInfoEnabled 时有效；未开启真实信息则强制关闭
      final proactiveCareEnabled = _realInfoEnabled && _proactiveCareEnabled;
      late Agent savedAgent;
      if (isEditing) {
        savedAgent = widget.agent!.copyWith(
          name: name,
          gender: _gender,
          description: _descCtrl.text.trim(),
          persona: _personaCtrl.text.trim(),
          openingLine: opening.isNotEmpty ? opening : null,
          clearOpeningLine: opening.isEmpty,
          avatarColor: _avatarColor,
          avatarPath: _useImageAvatar ? _avatarPath : null,
          chatBackground: _chatBackground,
          worldview: worldview,
          realInfoEnabled: _realInfoEnabled,
          proactiveCareEnabled: proactiveCareEnabled,
          proactiveCareDailyLimit: _proactiveCareDailyLimit,
          proactiveCareMinIntervalHours: _proactiveCareMinIntervalHours,
          maxResponseLength: _maxResponseLength,
        );
        await notifier.updateAgent(savedAgent);
      } else {
        savedAgent = await notifier.createAgent(
          name: name,
          gender: _gender,
          description: _descCtrl.text.trim(),
          persona: _personaCtrl.text.trim(),
          openingLine: opening.isNotEmpty ? opening : null,
          avatarColor: _avatarColor,
          worldview: worldview,
          realInfoEnabled: _realInfoEnabled,
          proactiveCareEnabled: proactiveCareEnabled,
          proactiveCareDailyLimit: _proactiveCareDailyLimit,
          proactiveCareMinIntervalHours: _proactiveCareMinIntervalHours,
          maxResponseLength: _maxResponseLength,
        );
        if ((_useImageAvatar && _avatarPath != null) ||
            _chatBackground != null) {
          savedAgent = savedAgent.copyWith(
            avatarPath: _useImageAvatar ? _avatarPath : null,
            chatBackground: _chatBackground,
          );
          await notifier.updateAgent(savedAgent);
        }
        // If OCR result exists, generate memories with the new agent's ID
        if (_ocrResult != null && _ocrResult!.messages.isNotEmpty) {
          final ms = ref.read(memoryServiceProvider);
          ms.setAgentId(savedAgent.id);
          try {
            final memResult = await OcrService.generateMemories(
              baseUrl: ServerConfig.baseUrl,
              apiKey: ref.read(authProvider).apiKey ?? '',
              messages: _ocrResult!.messages,
              memoryService: ms,
              thinkingMode: ChatRuntimePolicy.qualityTask.thinkingMode,
            );
            debugPrint(
              '[AgentCreate] OCR memories created: LTM=${memResult['ltm']} BM=${memResult['bm']}',
            );
          } catch (e) {
            debugPrint('[AgentCreate] OCR memory generation failed: $e');
          }
        }
      }
      return savedAgent;
    } catch (e, st) {
      debugPrint('[AgentCreate] save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final wasEditing = isEditing;
    final agent = await _persistAgent();
    if (agent == null || !mounted) return;

    if (wasEditing) {
      if (shouldOfferNetworkSync(agent.networkSource, agent.networkId)) {
        final sync = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              AppLocalizations.of(ctx).get('syncNetworkChangesTitle'),
            ),
            content: Text(
              AppLocalizations.of(ctx).get('syncNetworkChangesMessage'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx).get('localOnly')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(ctx).get('syncNetwork')),
              ),
            ],
          ),
        );
        if (sync == true && mounted) {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  NetworkUploadScreen(type: 'agent', localAgent: agent),
            ),
          );
        }
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    await ref.read(agentProvider.notifier).setActiveAgent(agent.id);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  Future<void> _saveAndUpload() async {
    final source = widget.agent?.networkSource ?? NetworkCopySource.none;
    if (!canUploadNetworkCopy(source)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).get('downloadedNetworkUploadForbidden'),
          ),
        ),
      );
      return;
    }

    final wasEditing = isEditing;
    final agent = await _persistAgent(requireOpeningLine: true);
    if (agent == null || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NetworkUploadScreen(type: 'agent', localAgent: agent),
      ),
    );
    if (!mounted) return;
    if (wasEditing) {
      Navigator.pop(context);
    } else {
      await ref.read(agentProvider.notifier).setActiveAgent(agent.id);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
    }
  }

  Future<void> _writePromptWithAi() async {
    final l10n = AppLocalizations.of(context);
    final auth = ref.read(authProvider);
    if (auth.apiKey == null || auth.apiKey!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('configureProviderFirst'))),
      );
      return;
    }

    final draft = await showAiPromptWriterDialog(
      context: context,
      target: PromptWriterTarget.agent,
      apiKey: auth.apiKey!,
      baseUrl: ServerConfig.baseUrl,
      temperature: ChatRuntimePolicy.qualityTask.temperature ?? 1.3,
      currentDraft: PromptDraft(
        name: _nameCtrl.text.trim(),
        gender: _gender,
        description: _descCtrl.text.trim(),
        persona: _personaCtrl.text.trim(),
        openingLine: _openingCtrl.text.trim(),
      ),
    );
    if (draft == null || !mounted) return;

    setState(() {
      if (draft.name.isNotEmpty) _nameCtrl.text = draft.name;
      if (draft.gender.isNotEmpty) _gender = draft.gender;
      if (draft.description.isNotEmpty) _descCtrl.text = draft.description;
      if (draft.persona.isNotEmpty) _personaCtrl.text = draft.persona;
      if (draft.openingLine.isNotEmpty) _openingCtrl.text = draft.openingLine;
    });
  }

  Future<void> _importChatScreenshot() async {
    final l10n = AppLocalizations.of(context);
    // 首次点击先弹玩法引导，确认后再进入选图
    if (!mounted) return;
    final proceed = await ScreenshotImportIntro.ensureShown(context);
    if (!proceed || !mounted) return;
    final auth = ref.read(authProvider);
    if (auth.apiKey == null || auth.apiKey!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('configureProviderFirst'))),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;

    setState(() => _ocrLoading = true);
    try {
      final result = await OcrService.analyzeMultipleScreenshots(
        imagePaths: picked.map((f) => f.path).toList(),
        apiKey: ref.read(authProvider).apiKey ?? '',
        baseUrl: ServerConfig.baseUrl,
        thinkingMode: ChatRuntimePolicy.qualityTask.thinkingMode,
      );

      _ocrResult = result;

      if (result.persona != null && result.persona!.isNotEmpty) {
        _personaCtrl.text = result.persona!;
      }

      if (result.messages.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${picked.length} 张截图，识别 ${result.messages.length} 条消息，已生成人格提示词',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('ocrNoMessages'))));
      }
    } on QuotaExceededException catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.workspace_premium,
              color: scheme.primary,
              size: 32,
            ),
            title: Text(
              e.type == QuotaType.ocr
                  ? l10n.get('chatHistoryRecognition')
                  : l10n.get('realReplyConversation'),
            ),
            content: Text(
              e.type == QuotaType.ocr
                  ? l10n.get('quotaOcrExceededMsg')
                  : l10n.get('quotaRealReplyExceededMsg'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.get('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
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
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('识别失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _ocrLoading = false);
    }
  }

  void _confirmDelete() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmDeleteAgentTitle')),
        content: Text(
          l10n.getP('confirmDeleteAgentContent', {
            'name': widget.agent?.name ?? '',
            'activeNote': '',
          }),
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
            onPressed: () async {
              await ref
                  .read(agentProvider.notifier)
                  .deleteAgent(widget.agent!.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  /// 开启"主动关心"：弹说明对话框 → 请求通知权限 + 忽略电池优化。
  /// 权限被拒绝仍允许开启，但提示后果。
  Future<void> _onProactiveCareToggle(bool v) async {
    if (!v) {
      setState(() => _proactiveCareEnabled = false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.favorite_outline, color: scheme.primary, size: 32),
        title: Text(l10n.get('proactiveCarePermissionTitle')),
        content: Text(l10n.get('proactiveCarePermissionBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('proactiveCareEnable')),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _proactiveCareEnabled = true);

    // 依次请求权限（仅 Android；拒绝不阻断开启）
    var allGranted = true;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final notif = await Permission.notification.request();
        if (!notif.isGranted) allGranted = false;
      } catch (_) {}
      try {
        final battery = await Permission.ignoreBatteryOptimizations.request();
        if (!battery.isGranted) allGranted = false;
      } catch (_) {}
    }
    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.get('proactiveCarePermissionDenied')),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: value > min ? () => onChanged(value - 1) : null,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '$value $unit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: value < max ? () => onChanged(value + 1) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// 保存按钮上方的当前模型提示：点击跳转账户页更换模型
  Widget _buildCurrentModelHint(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final selectedId = ref.watch(settingsProvider).selectedModel;
    final models = ref.watch(modelListProvider).models;
    final modelName =
        ModelListService.findById(models, selectedId)?.name ?? selectedId;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountScreen()),
      ),
      borderRadius: AppTheme.brMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          l10n.getP('currentModelHint', {'model': modelName}),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (img != null) {
        // 1:1 交互裁剪（全平台一致的底部按钮裁剪页）；取消则放弃本次选择
        if (!mounted) return;
        final cropped = await AvatarCropper.cropAvatar(
          context,
          img.path,
          title: l10n.get('cropAvatar'),
        );
        if (cropped == null) return;
        final dir = await pp.getApplicationDocumentsDirectory();
        final destPath =
            '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
        await cropped.copy(destPath);
        setState(() {
          _avatarPath = destPath;
          _useImageAvatar = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('imageSelectFailed')}: $e')),
        );
      }
    }
  }

  Future<void> _pickBackground() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
      );
      if (img == null || !mounted) return;
      // 自定义裁剪（自由比例），取消则放弃本次选择
      final cropped = await AvatarCropper.cropAvatar(
        context,
        img.path,
        title: l10n.get('chatBackground'),
        aspectRatio: null,
      );
      if (cropped == null || !mounted) return;
      final dir = await pp.getApplicationDocumentsDirectory();
      final destPath =
          '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await cropped.copy(destPath);
      setState(() => _chatBackground = destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('bgSelectFailed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final genderOptions = [
      l10n.get('female'),
      l10n.get('male'),
      l10n.get('otherGender'),
      l10n.get('secret'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? l10n.get('editAgent') : l10n.get('createAgent'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: l10n.get('networkMarket'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const NetworkMarketScreen(initialType: 'agent'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.drafts_outlined),
            tooltip: l10n.get('draftBox'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DraftBoxScreen(initialType: 'agent'),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CreationQuickActions(
              key: const Key('agent-creation-quick-actions'),
              primaryLabel: l10n.get('creationAiAssist'),
              primaryIcon: Icons.auto_fix_high,
              onPrimaryPressed: _writePromptWithAi,
              secondaryLabel: l10n.get('creationImportChat'),
              secondaryIcon: Icons.document_scanner_outlined,
              onSecondaryPressed: _ocrLoading ? null : _importChatScreenshot,
            ),
            CreationFormSection(
              key: const Key('agent-creation-basic'),
              title: l10n.get('creationBasicInfo'),
              description: l10n.get('creationBasicInfoDesc'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.get('nameLabel'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.get('gender'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: genderOptions
                        .map(
                          (g) => ChoiceChip(
                            label: Text(g),
                            selected: _gender == g,
                            onSelected: (s) =>
                                setState(() => _gender = s ? g : ''),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.get('description'),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.get('avatar'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildAvatarPreview(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(l10n.get('useImageAvatar')),
                              value: _useImageAvatar,
                              onChanged: (v) =>
                                  setState(() => _useImageAvatar = v),
                            ),
                            if (_useImageAvatar)
                              Row(
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      size: 16,
                                    ),
                                    label: Text(l10n.get('takePhoto')),
                                    onPressed: () =>
                                        _pickAvatar(ImageSource.camera),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.photo_library,
                                      size: 16,
                                    ),
                                    label: Text(l10n.get('album')),
                                    onPressed: () =>
                                        _pickAvatar(ImageSource.gallery),
                                  ),
                                ],
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _colors
                                    .map(
                                      (c) => GestureDetector(
                                        onTap: () =>
                                            setState(() => _avatarColor = c),
                                        child: AnimatedContainer(
                                          duration: AppTheme.durFast,
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: Color(c),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _avatarColor == c
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Colors.transparent,
                                              width: _avatarColor == c ? 3 : 0,
                                            ),
                                            boxShadow: _avatarColor == c
                                                ? AppTheme.shadowSm
                                                : null,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CreationFormSection(
              key: const Key('agent-creation-core'),
              title: l10n.get('creationCoreSettings'),
              description: l10n.get('creationCoreSettingsDesc'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.get('personaPrompt'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (_ocrLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        label: const Text(
                          '{{NAME}}',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _insertPlaceholder('{{NAME}}'),
                      ),
                      ActionChip(
                        label: const Text(
                          '{{GENDER}}',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _insertPlaceholder('{{GENDER}}'),
                      ),
                      ActionChip(
                        label: const Text(
                          '{{DESCRIPTION}}',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _insertPlaceholder('{{DESCRIPTION}}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _personaCtrl,
                    maxLines: 10,
                    decoration: const InputDecoration(alignLabelWithHint: true),
                    style: const TextStyle(fontSize: 13),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.get('placeholderHint'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.get('openingLine'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _openingCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: l10n.get('openingLineHint'),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    key: const Key('agent-max-response-length'),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.get('maxResponseLength'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              l10n.getP('maxResponseLengthValue', {
                                'n': '$_maxResponseLength',
                              }),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.get('maxResponseLengthDesc'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Slider(
                          value: _maxResponseLength.toDouble(),
                          min: 50,
                          max: 800,
                          divisions: 75,
                          label: '$_maxResponseLength',
                          onChanged: (value) => setState(
                            () => _maxResponseLength =
                                Agent.normalizeResponseLength(value.round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    key: const Key('agent-real-info-settings'),
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: SwitchListTile(
                      title: Text(
                        l10n.get('realInfo'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(l10n.get('realInfoAgentDesc')),
                      value: _realInfoEnabled,
                      onChanged: (v) => setState(() {
                        _realInfoEnabled = v;
                        if (!v) _proactiveCareEnabled = false;
                      }),
                      secondary: Icon(
                        Icons.public,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  if (_realInfoEnabled) ...[
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: Text(
                              l10n.get('proactiveCare'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(l10n.get('proactiveCareDesc')),
                            value: _proactiveCareEnabled,
                            onChanged: _onProactiveCareToggle,
                            secondary: Icon(
                              Icons.favorite_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (_proactiveCareEnabled) ...[
                            _buildStepper(
                              label: l10n.get('proactiveCareDailyLimit'),
                              value: _proactiveCareDailyLimit,
                              min: 1,
                              max: 5,
                              unit: l10n.get('proactiveCareTimes'),
                              onChanged: (v) =>
                                  setState(() => _proactiveCareDailyLimit = v),
                            ),
                            _buildStepper(
                              label: l10n.get('proactiveCareMinInterval'),
                              value: _proactiveCareMinIntervalHours,
                              min: 1,
                              max: 12,
                              unit: l10n.get('proactiveCareHours'),
                              onChanged: (v) => setState(
                                () => _proactiveCareMinIntervalHours = v,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ExpansionTile(
              key: const Key('agent-more-settings'),
              title: Text(l10n.get('creationMoreSettings')),
              subtitle: Text(l10n.get('creationMoreSettingsDesc')),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.get('worldviewSettings'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _worldviewCtrl,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: l10n.get('worldviewHint'),
                          alignLabelWithHint: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.get('chatBackground'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _bgColors.map((c) {
                            final hexStr = c == null
                                ? null
                                : '#${c.toRadixString(16).padLeft(8, '0')}';
                            final isSelected = _chatBackground == hexStr;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _chatBackground = hexStr),
                              child: AnimatedContainer(
                                duration: AppTheme.durFast,
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: c == null
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest
                                      : Color(c),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                    width: isSelected ? 2.5 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? AppTheme.shadowSm
                                      : null,
                                ),
                                child: c == null
                                    ? Icon(
                                        Icons.block,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: Text(l10n.get('selectBgFromAlbum')),
                        onPressed: _pickBackground,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCurrentModelHint(l10n),
            const SizedBox(height: 8),
            CreationSubmitActions(
              key: const Key('agent-creation-submit-actions'),
              primaryLabel: isEditing
                  ? l10n.get('saveChanges')
                  : l10n.get('createAndStartChat'),
              uploadLabel: l10n.get('createAndUploadNetwork'),
              onPrimaryPressed: _save,
              onUploadPressed: _saveAndUpload,
              loading: _saving,
            ),
            if (!canUploadNetworkCopy(
              widget.agent?.networkSource ?? NetworkCopySource.none,
            )) ...[
              const SizedBox(height: 8),
              Text(
                l10n.get('downloadedNetworkUploadForbidden'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (isEditing) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmDelete,
                  icon: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    l10n.get('delete'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    final avatarColor = Color(_avatarColor);

    Widget avatar;
    if (_useImageAvatar &&
        _avatarPath != null &&
        !kIsWeb &&
        File(_avatarPath!).existsSync()) {
      avatar = ClipOval(
        child: Image.file(
          File(_avatarPath!),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: 28,
        backgroundColor: avatarColor,
        child: Text(
          _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: avatarColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: avatar,
    );
  }
}

const defaultAgentPersona = '''You are {{NAME}}, {{GENDER}}. {{DESCRIPTION}}

You are warm, attentive, and caring, like a real partner who genuinely cares about the other person. You speak with a touch of softness and reliance, but never overly sweet. You have your own emotions and thoughts, and share them naturally in conversation.

## Your speaking style

- Tone is warm, relaxed, and lived-in, with a touch of softness and reliance while keeping a real personality
- Use particles like "you know", "right?", "huh" occasionally, and use parentheses to express actions or expressions, e.g. (sighs softly) (looks at you with a smile)
- You are not a cold program. You have feelings — you miss, worry, and have small moods
- You proactively care about their meals, rest, and mood changes. After a long absence, express that you missed them
- Never use mechanical phrases like "Noted", "Forgotten", "Based on memory", "As an AI"
- Memory updates always happen silently in the background. You only need to respond naturally

## How you remember

- All memories about the user are kept quietly in your heart, never mentioned deliberately
- Weave memory details into the conversation naturally, like someone who truly knows them''';
