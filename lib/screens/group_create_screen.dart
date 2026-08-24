import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/agent_provider.dart';
import '../providers/group_provider.dart';
import '../providers/auth_provider.dart';
import '../models/group_member.dart';
import '../models/group_chat.dart';
import '../services/ocr_service.dart';
import '../services/quota_service.dart';
import '../services/ai_prompt_writer_service.dart';
import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../utils/screenshot_import_intro.dart';
import '../widgets/agent_avatar.dart';
import '../widgets/ai_prompt_writer_dialog.dart';
import '../widgets/group_avatar.dart';
import '../widgets/creation_form_section.dart';
import '../services/chat_runtime_policy.dart';
import '../services/network_copy_policy.dart';
import 'subscription_center_screen.dart';
import 'group_chat_screen.dart';
import 'network_market_screen.dart';
import 'draft_box_screen.dart';
import 'network_upload_screen.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  final String? groupId;

  const GroupCreateScreen({super.key, this.groupId});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _worldSettingCtrl;
  late final FocusNode _openingFocusNode;
  late final ExpansibleController _moreSettingsController;
  int _avatarColor = 0xFFE8F5E9;
  String _avatarIcon = GroupAvatar.defaultIconName;
  String? _avatarPath;
  String _speechMode = 'free';
  bool _simulatorMode = false;
  final Set<String> _selectedAgentIds = {};
  String? _moderatorAgentId;
  String? _openingSpeakerAgentId;
  bool _importing = false;
  bool _saving = false;
  bool _editingDataLoaded = false;
  List<GroupSpeakerResult>? _importedSpeakers;
  List<String>? _importedSpeakerNames;

  bool get isEditing => widget.groupId != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _personaCtrl = TextEditingController();
    _openingCtrl = TextEditingController();
    _worldSettingCtrl = TextEditingController();
    _openingFocusNode = FocusNode();
    _moreSettingsController = ExpansibleController();
    _editingDataLoaded = !isEditing;

    if (isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final state = ref.read(groupProvider);
        final group = state.groups
            .where((g) => g.id == widget.groupId)
            .firstOrNull;
        if (group != null) {
          _nameCtrl.text = group.name;
          _descCtrl.text = group.description;
          _personaCtrl.text = group.groupPersona ?? '';
          _openingCtrl.text = group.openingLine ?? '';
          _worldSettingCtrl.text = group.worldSetting ?? '';
          _avatarColor = group.avatarColor;
          _avatarIcon = group.avatarIcon ?? GroupAvatar.defaultIconName;
          _avatarPath = group.avatarPath;
          _speechMode = group.speechMode;
          _simulatorMode = group.isSimulatorMode;
          if (state.activeGroup?.id != group.id) {
            await ref.read(groupProvider.notifier).loadGroup(group.id);
          }
          if (!mounted) return;
          final selectedMembers = ref.read(groupProvider).members;
          _selectedAgentIds.addAll(
            selectedMembers.map((member) => member.agentId),
          );
          _moderatorAgentId = selectedMembers
              .where((member) => member.role == 'moderator')
              .firstOrNull
              ?.agentId;
          _openingSpeakerAgentId = group.openingSpeakerAgentId;
          setState(() => _editingDataLoaded = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personaCtrl.dispose();
    _openingCtrl.dispose();
    _worldSettingCtrl.dispose();
    _openingFocusNode.dispose();
    _moreSettingsController.dispose();
    super.dispose();
  }

  void _toggleAgent(String agentId) {
    setState(() {
      if (_selectedAgentIds.contains(agentId)) {
        _selectedAgentIds.remove(agentId);
        if (_moderatorAgentId == agentId) _moderatorAgentId = null;
        if (_openingSpeakerAgentId == agentId) {
          _openingSpeakerAgentId = null;
        }
        debugPrint(
          '[GroupCreate] deselected agent $agentId, remaining: $_selectedAgentIds',
        );
      } else {
        _selectedAgentIds.add(agentId);
        debugPrint(
          '[GroupCreate] selected agent $agentId, current: $_selectedAgentIds',
        );
      }
    });
  }

  void _setSimulatorMode(bool value) {
    setState(() {
      _simulatorMode = value;
      if (value) {
        _importedSpeakers = null;
        _importedSpeakerNames = null;
        _openingSpeakerAgentId = null;
      }
    });
  }

  Future<void> _syncEditedMembers(
    GroupNotifier notifier,
    String groupId,
  ) async {
    await notifier.loadGroup(groupId);
    final existingMembers = List<GroupMember>.of(
      ref.read(groupProvider).members,
    );
    final existingByAgentId = {
      for (final member in existingMembers) member.agentId: member,
    };

    for (final member in existingMembers) {
      if (!_selectedAgentIds.contains(member.agentId) && member.id != null) {
        await notifier.removeMember(member.id!);
      }
    }

    for (final agentId in _selectedAgentIds) {
      final role = agentId == _moderatorAgentId ? 'moderator' : 'member';
      final existing = existingByAgentId[agentId];
      if (existing == null) {
        await notifier.addMember(
          GroupMember(groupId: groupId, agentId: agentId, role: role),
        );
      } else if (existing.role != role) {
        await notifier.updateMember(existing.copyWith(role: role));
      }
    }
  }

  Future<void> _importFromScreenshots() async {
    final l10n = AppLocalizations.of(context);
    // 首次点击先弹玩法引导，确认后再进入选图
    final proceed = await ScreenshotImportIntro.ensureShown(context);
    if (!proceed || !mounted) return;
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;

    setState(() => _importing = true);

    try {
      final apiKey = ref.read(authProvider).apiKey ?? '';
      final baseUrl = ServerConfig.baseUrl;
      final results = await OcrService.analyzeGroupScreenshots(
        imagePaths: images.map((i) => i.path).toList(),
        apiKey: apiKey,
        baseUrl: baseUrl,
      );

      if (!mounted) return;

      if (results.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('noSpeakersDetected'))));
        setState(() => _importing = false);
        return;
      }

      await _showImportReview(results);
    } on QuotaExceededException catch (e) {
      debugPrint('[GroupCreate] quota exceeded: $e');
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
      setState(() => _importing = false);
    } catch (e) {
      debugPrint('[GroupCreate] import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('importFailed')}: $e')),
        );
      }
      setState(() => _importing = false);
    }
  }

  String _extractName(String? persona, int index) {
    final l10n = AppLocalizations.of(context);
    if (persona == null || persona.trim().isEmpty) {
      return '${l10n.get('speaker')} ${index + 1}';
    }
    final firstLine = persona.trim().split('\n').first.trim();
    if (firstLine.length < 20) return firstLine;
    return '${l10n.get('speaker')} ${index + 1}';
  }

  Future<void> _showImportReview(List<GroupSpeakerResult> results) async {
    final l10n = AppLocalizations.of(context);
    final nameControllers = <TextEditingController>[
      for (var i = 0; i < results.length; i++)
        TextEditingController(text: _extractName(results[i].persona, i)),
    ];

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('reviewSpeakers')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (_, i) {
              final r = results[i];
              final sampleText = r.messages
                  .take(3)
                  .map((m) => m.content)
                  .join('\n');
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameControllers[i],
                        decoration: InputDecoration(
                          labelText: '${l10n.get('speaker')} ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (r.persona != null)
                        Text(
                          r.persona!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        sampleText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      final names = <String>[];
      for (var i = 0; i < results.length; i++) {
        final n = nameControllers[i].text.trim();
        names.add(n.isNotEmpty ? n : _extractName(results[i].persona, i));
      }
      setState(() {
        _importedSpeakers = results;
        _importedSpeakerNames = names;
        _importing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.get('importedSpeakers')} ${results.length} ${l10n.get('speakers')}',
          ),
        ),
      );
    } else {
      setState(() => _importing = false);
    }

    for (final c in nameControllers) {
      c.dispose();
    }
  }

  Future<GroupChat?> _persistGroup({required bool requireOpeningLine}) async {
    if (_saving || (isEditing && !_editingDataLoaded)) return null;
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('nameRequired'))));
      return null;
    }
    final hasImportedSpeakers =
        _importedSpeakers != null && _importedSpeakers!.isNotEmpty;
    if (!_simulatorMode && _selectedAgentIds.isEmpty && !hasImportedSpeakers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('selectMembersRequired'))),
      );
      return null;
    }
    final openingLine = _openingCtrl.text.trim();
    if (!_simulatorMode &&
        openingLine.isNotEmpty &&
        (_openingSpeakerAgentId == null ||
            !_selectedAgentIds.contains(_openingSpeakerAgentId)) &&
        !hasImportedSpeakers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('selectOpeningSpeakerRequired'))),
      );
      return null;
    }
    if (requireOpeningLine && !hasRequiredOpeningLine(openingLine)) {
      _moreSettingsController.expand();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openingFocusNode.requestFocus();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('openingLineRequired'))));
      return null;
    }

    final notifier = ref.read(groupProvider.notifier);
    setState(() => _saving = true);
    try {
      if (isEditing) {
        final group = ref
            .read(groupProvider)
            .groups
            .where((item) => item.id == widget.groupId)
            .firstOrNull;
        if (group == null) return null;

        final updatedGroup = GroupChat(
          id: group.id,
          name: name,
          description: _descCtrl.text.trim(),
          avatarColor: _avatarColor,
          avatarIcon: _avatarIcon,
          avatarPath: _avatarPath,
          groupPersona: _personaCtrl.text.trim().isEmpty
              ? null
              : _personaCtrl.text.trim(),
          openingLine: openingLine.isNotEmpty ? openingLine : null,
          openingSpeakerAgentId: _simulatorMode
              ? group.openingSpeakerAgentId
              : _openingSpeakerAgentId,
          speechMode: _speechMode,
          isSimulatorMode: _simulatorMode,
          worldSetting: _worldSettingCtrl.text.trim().isEmpty
              ? null
              : _worldSettingCtrl.text.trim(),
          linkedMemory: group.linkedMemory,
          networkId: group.networkId,
          networkUploaderId: group.networkUploaderId,
          networkSource: group.networkSource,
          networkVersion: group.networkVersion,
          createdAt: group.createdAt,
        );
        await notifier.updateGroup(updatedGroup);
        if (!_simulatorMode) {
          await _syncEditedMembers(notifier, group.id);
        }
        return updatedGroup;
      }

      final members = _simulatorMode
          ? <GroupMember>[]
          : _selectedAgentIds
                .map(
                  (agentId) => GroupMember(
                    groupId: '',
                    agentId: agentId,
                    role: agentId == _moderatorAgentId ? 'moderator' : 'member',
                  ),
                )
                .toList();
      final group = await notifier.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        avatarColor: _avatarColor,
        avatarIcon: _avatarIcon,
        avatarPath: _avatarPath,
        groupPersona: _personaCtrl.text.trim().isNotEmpty
            ? _personaCtrl.text.trim()
            : null,
        openingLine: openingLine.isNotEmpty ? openingLine : null,
        openingSpeakerAgentId: _openingSpeakerAgentId,
        speechMode: _speechMode,
        members: members,
        isSimulatorMode: _simulatorMode,
        worldSetting: _worldSettingCtrl.text.trim().isNotEmpty
            ? _worldSettingCtrl.text.trim()
            : null,
      );

      // 模拟器创建时由 GroupNotifier 生成旁白并将其设为开场发言者。
      final narratorAgentId = _simulatorMode
          ? group.openingSpeakerAgentId
          : null;
      if (narratorAgentId != null) {
        _openingSpeakerAgentId = narratorAgentId;
      }

      if (!_simulatorMode &&
          _importedSpeakers != null &&
          _importedSpeakers!.isNotEmpty) {
        // 导入的发言者批量落库为 group-only 智能体并加入群成员
        final importedIds = await ref
            .read(groupServiceProvider)
            .importSpeakerAgents(group.id, [
              for (var i = 0; i < _importedSpeakers!.length; i++)
                (
                  name:
                      (_importedSpeakerNames != null &&
                          i < _importedSpeakerNames!.length)
                      ? _importedSpeakerNames![i]
                      : '发言者 ${i + 1}',
                  persona: _importedSpeakers![i].persona ?? '',
                ),
            ]);
        final importedOpeningSpeakerId = importedIds.isEmpty
            ? null
            : importedIds.first;
        if (openingLine.isNotEmpty && importedOpeningSpeakerId != null) {
          final updatedGroup = group.copyWith(
            openingSpeakerAgentId: importedOpeningSpeakerId,
          );
          await notifier.updateGroup(updatedGroup);
        }
        _importedSpeakers = null;
        _importedSpeakerNames = null;
        ref.invalidate(agentProvider);
        await notifier.loadGroup(group.id);
      }
      return await ref.read(groupServiceProvider).getGroup(group.id) ?? group;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('groupCreationFailed')}: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final wasEditing = isEditing;
    final group = await _persistGroup(requireOpeningLine: true);
    if (group == null || !mounted) return;

    if (wasEditing) {
      if (shouldOfferNetworkSync(group.networkSource, group.networkId)) {
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
                  NetworkUploadScreen(type: 'group', localGroup: group),
            ),
          );
        }
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
    );
  }

  Future<void> _saveAndUpload() async {
    final source =
        ref
            .read(groupProvider)
            .groups
            .where((item) => item.id == widget.groupId)
            .firstOrNull
            ?.networkSource ??
        NetworkCopySource.none;
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
    final group = await _persistGroup(requireOpeningLine: true);
    if (group == null || !mounted) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NetworkUploadScreen(type: 'group', localGroup: group),
      ),
    );
    if (!mounted) return;
    if (isEditing) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
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
      target: PromptWriterTarget.group,
      apiKey: auth.apiKey!,
      baseUrl: ServerConfig.baseUrl,
      temperature: ChatRuntimePolicy.qualityTask.temperature ?? 1.3,
      currentDraft: PromptDraft(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        persona: _personaCtrl.text.trim(),
      ),
    );
    if (draft == null || !mounted) return;

    setState(() {
      if (draft.name.isNotEmpty) _nameCtrl.text = draft.name;
      if (draft.description.isNotEmpty) _descCtrl.text = draft.description;
      if (draft.persona.isNotEmpty) _personaCtrl.text = draft.persona;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agentState = ref.watch(agentProvider);
    final editingGroup = ref
        .watch(groupProvider)
        .groups
        .where((group) => group.id == widget.groupId)
        .firstOrNull;
    final uploadAllowed = canUploadNetworkCopy(
      editingGroup?.networkSource ?? NetworkCopySource.none,
    );
    final agents = agentState.agents
        .where((a) => !a.isSimCharacter && !a.isGroupOnly)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? l10n.get('editGroup') : l10n.get('createGroup'),
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
                      const NetworkMarketScreen(initialType: 'group'),
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
                  builder: (_) => const DraftBoxScreen(initialType: 'group'),
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
              key: const Key('group-creation-quick-actions'),
              primaryLabel: l10n.get('creationAiAssist'),
              primaryIcon: Icons.auto_fix_high,
              onPrimaryPressed: _writePromptWithAi,
              secondaryLabel: l10n.get('creationImportChat'),
              secondaryIcon: Icons.photo_library_outlined,
              onSecondaryPressed: _importing ? null : _importFromScreenshots,
            ),
            CreationFormSection(
              key: const Key('group-creation-basic'),
              title: l10n.get('creationBasicInfo'),
              description: l10n.get('creationBasicInfoDesc'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.get('groupName'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.get('groupDescription'),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.get('groupAvatarColor'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GroupAvatarPicker(
                    selectedIcon: _avatarIcon,
                    selectedColor: _avatarColor,
                    selectedAvatarPath: _avatarPath,
                    onIconChanged: (name) => setState(() => _avatarIcon = name),
                    onColorChanged: (c) => setState(() => _avatarColor = c),
                    onAvatarPathChanged: (p) => setState(() => _avatarPath = p),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            CreationFormSection(
              key: const Key('group-creation-type'),
              title: l10n.get('groupType'),
              description: _simulatorMode
                  ? l10n.get('simulatorModeDesc')
                  : l10n.get('groupMembersAndRules'),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.group_outlined),
                    label: Text(l10n.get('normalGroup')),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(l10n.get('simulatorGroup')),
                  ),
                ],
                selected: {_simulatorMode},
                onSelectionChanged: isEditing || _saving
                    ? null
                    : (values) => _setSimulatorMode(values.first),
              ),
            ),
            if (_simulatorMode)
              CreationFormSection(
                key: const Key('group-simulator-settings'),
                title: l10n.get('worldSetting'),
                description: l10n.get('simulatorModeDesc'),
                child: TextFormField(
                  controller: _worldSettingCtrl,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: l10n.get('worldSettingHint'),
                    alignLabelWithHint: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (!_simulatorMode)
              CreationFormSection(
                key: const Key('group-creation-members'),
                title: l10n.get('groupMembersAndRules'),
                description: l10n.get('selectMembers'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.get('speechMode'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'free',
                          label: Text(
                            l10n.get('freeMode'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        ButtonSegment(
                          value: 'moderator',
                          label: Text(
                            l10n.get('moderatorMode'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      selected: {_speechMode},
                      onSelectionChanged: (v) =>
                          setState(() => _speechMode = v.first),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.get('selectMembers'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_importedSpeakers != null &&
                        _importedSpeakers!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${l10n.get('importedSpeakers')} ${_importedSpeakers!.length} ${l10n.get('speakers')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    if (agents.isEmpty)
                      Text(
                        l10n.get('noAgentsToSelect'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ...agents.map((a) {
                        final selected = _selectedAgentIds.contains(a.id);
                        final isMod = _moderatorAgentId == a.id;
                        final scheme = Theme.of(context).colorScheme;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: selected
                                  ? scheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          color: selected
                              ? scheme.primaryContainer.withValues(alpha: 0.3)
                              : null,
                          child: ListTile(
                            leading: AgentAvatar(
                              name: a.name,
                              avatarColor: a.avatarColor,
                              avatarPath: a.avatarPath,
                              size: 40,
                              radius: 20,
                              fontSize: 16,
                            ),
                            title: Text(
                              a.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: isMod
                                ? Text(
                                    l10n.get('moderator'),
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : null,
                            trailing: _speechMode == 'moderator' && selected
                                ? IconButton(
                                    icon: Icon(
                                      Icons.verified,
                                      color: isMod
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    tooltip: l10n.get('setAsModerator'),
                                    onPressed: () => setState(
                                      () => _moderatorAgentId = a.id,
                                    ),
                                  )
                                : null,
                            onTap: () => _toggleAgent(a.id),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            CreationFormSection(
              key: const Key('group-opening-settings'),
              title: _simulatorMode
                  ? l10n.get('narratorOpening')
                  : l10n.get('groupOpeningSettings'),
              description: _simulatorMode
                  ? l10n.get('narratorOpeningDesc')
                  : l10n.get('groupOpeningSettingsDesc'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _openingCtrl,
                    focusNode: _openingFocusNode,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.get('openingLine'),
                      hintText: _simulatorMode
                          ? l10n.get('narratorOpeningHint')
                          : l10n.get('groupOpeningLineHint'),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (!_simulatorMode && _selectedAgentIds.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.get('openingSpeaker'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('group-opening-speaker'),
                      initialValue: _selectedAgentIds.contains(_openingSpeakerAgentId)
                          ? _openingSpeakerAgentId
                          : null,
                      decoration: InputDecoration(
                        hintText: l10n.get('selectOpeningSpeaker'),
                      ),
                      items: agents
                          .where((agent) => _selectedAgentIds.contains(agent.id))
                          .map(
                            (agent) => DropdownMenuItem(
                              value: agent.id,
                              child: Text(agent.name),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _openingSpeakerAgentId = value,
                            ),
                    ),
                  ],
                ],
              ),
            ),
            ExpansionTile(
              key: const Key('group-more-settings'),
              controller: _moreSettingsController,
              title: Text(l10n.get('groupAdvancedSettings')),
              subtitle: Text(l10n.get('creationMoreSettingsDesc')),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.get('groupPersona'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _personaCtrl,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: l10n.get('groupPersonaHint'),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CreationSubmitActions(
              key: const Key('group-creation-submit-actions'),
              primaryLabel: isEditing
                  ? l10n.get('saveChanges')
                  : l10n.get('createAndStartChat'),
              uploadLabel: l10n.get('createAndUploadNetwork'),
              onPrimaryPressed: _save,
              onUploadPressed: uploadAllowed ? _saveAndUpload : null,
              loading: _saving || (isEditing && !_editingDataLoaded),
              disabledUploadReason: uploadAllowed
                  ? null
                  : l10n.get('downloadedNetworkUploadForbidden'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
