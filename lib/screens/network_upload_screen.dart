import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../l10n/app_localizations.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/group_provider.dart';
import '../services/draft_service.dart';
import '../services/network_copy_policy.dart';
import '../services/network_service.dart';
import '../services/network_upload_payload.dart';
import '../theme/app_theme.dart';

/// 网络市场上传/编辑页面
///
/// 支持智能体和群聊两种类型。支持三种入口：
/// 1. 全新上传（现写）
/// 2. 从本地现有选择后编辑上传
/// 3. 编辑已上传作品（existingData 含 id）
/// 4. 从草稿继续编辑（draftId）
class NetworkUploadScreen extends ConsumerStatefulWidget {
  final String type; // 'agent' or 'group'
  final Map<String, dynamic>? existingData; // 编辑模式时传入（含 id）
  final String? draftId; // 从草稿箱继续编辑时传入
  final Agent? localAgent;
  final GroupChat? localGroup;

  const NetworkUploadScreen({
    super.key,
    required this.type,
    this.existingData,
    this.draftId,
    this.localAgent,
    this.localGroup,
  });

  @override
  ConsumerState<NetworkUploadScreen> createState() =>
      _NetworkUploadScreenState();
}

class _NetworkUploadScreenState extends ConsumerState<NetworkUploadScreen> {
  bool get isGroup => widget.type == 'group';
  bool get isEditing => _editId != null;

  final DraftService _draftService = DraftService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  late final TextEditingController _openingCtrl; // agent only
  late final TextEditingController _worldviewCtrl; // agent only
  late final TextEditingController _tagInputCtrl;

  String _gender = ''; // agent only
  int _maxResponseLength = Agent.defaultResponseLength; // agent only
  int _avatarColor = 0xFFE8F5E9;
  String? _avatarPath; // 从选择的本地 agent 继承，用于发布时序列化
  String _speechMode = 'free'; // group only
  bool _isSimulatorMode = false; // group only
  final List<Map<String, dynamic>> _members = []; // group only
  String? _openingSpeakerAgentId; // group only, local form state
  int _memberSequence = 0;

  final List<String> _tags = [];
  List<String> _presetTags = [];
  bool _loadingTags = true;

  int _mode = 0; // 0=现写, 1=从我的选择
  String? _selectedLocalId;

  int? _editId;
  bool _publishing = false;
  Agent? _boundAgent;
  GroupChat? _boundGroup;

  static const _colors = [
    0xFFE8F5E9,
    0xFFFFF3E0,
    0xFFFCE4EC,
    0xFFE3F2FD,
    0xFFF3E5F5,
    0xFFE0F2F1,
    0xFFFFF8E1,
    0xFFFBE9E7,
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _personaCtrl = TextEditingController();
    _openingCtrl = TextEditingController();
    _worldviewCtrl = TextEditingController();
    _tagInputCtrl = TextEditingController();

    _loadPresetTags();

    if (widget.localAgent != null) {
      _mode = 1;
      _selectedLocalId = widget.localAgent!.id;
      _boundAgent = widget.localAgent;
      _editId = widget.localAgent!.networkId;
      _prefillFromAgent(widget.localAgent!);
    } else if (widget.localGroup != null) {
      _mode = 1;
      _selectedLocalId = widget.localGroup!.id;
      _boundGroup = widget.localGroup;
      _editId = widget.localGroup!.networkId;
      _prefillFromGroup(widget.localGroup!);
    } else if (widget.draftId != null) {
      _loadDraft();
    } else if (widget.existingData != null) {
      _prefillFromExisting();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personaCtrl.dispose();
    _openingCtrl.dispose();
    _worldviewCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  // ─── 初始化数据加载 ──────────────────────────────────

  Future<void> _loadPresetTags() async {
    try {
      NetworkService().setToken(ref.read(authProvider).jwtToken);
      final tags = await NetworkService().getPresetTags();
      if (mounted) {
        setState(() {
          _presetTags = tags;
          _loadingTags = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTags = false);
    }
  }

  void _prefillFromExisting() {
    final data = widget.existingData!;
    _editId = (data['id'] as num?)?.toInt();
    _nameCtrl.text = (data['name'] as String?) ?? '';
    _descCtrl.text = (data['description'] as String?) ?? '';

    if (isGroup) {
      _personaCtrl.text =
          (data['group_persona'] as String?) ??
          (data['persona'] as String?) ??
          '';
      _openingCtrl.text = (data['opening_line'] as String?) ?? '';
      final openingSpeakerIndex =
          (data['opening_speaker_index'] as num?)?.toInt() ?? -1;
      _speechMode = (data['speech_mode'] as String?) ?? 'free';
      _isSimulatorMode = (data['is_simulator_mode'] as bool?) ?? false;
      _avatarColor = (data['avatar_color'] as num?)?.toInt() ?? 0xFFE8F5E9;
      final members = data['members'] as List? ?? [];
      _members.clear();
      for (final m in members) {
        _members.add(_withMemberId(Map<String, dynamic>.from(m as Map)));
      }
      if (openingSpeakerIndex >= 0 && openingSpeakerIndex < _members.length) {
        _openingSpeakerAgentId =
            _members[openingSpeakerIndex]['agent_id'] as String?;
      }
    } else {
      _personaCtrl.text = (data['persona'] as String?) ?? '';
      _openingCtrl.text = (data['opening_line'] as String?) ?? '';
      _worldviewCtrl.text = (data['worldview'] as String?) ?? '';
      _gender = (data['gender'] as String?) ?? '';
      _maxResponseLength = Agent.normalizeResponseLength(
        (data['max_response_length'] as num?)?.toInt() ??
            Agent.defaultResponseLength,
      );
      _avatarColor = (data['avatar_color'] as num?)?.toInt() ?? 0xFFE8F5E9;
    }

    final tags = data['tags'] as List? ?? [];
    _tags.clear();
    for (final t in tags) {
      _tags.add(t.toString());
    }
    setState(() {});
  }

  Future<void> _loadDraft() async {
    final draft = await _draftService.getDraft(widget.draftId!);
    if (draft == null) return;
    final dataStr = draft['data'] as String?;
    if (dataStr == null) return;
    try {
      final data = jsonDecode(dataStr) as Map<String, dynamic>;
      final form = (data['form'] as Map<String, dynamic>?) ?? {};
      _nameCtrl.text = (form['name'] as String?) ?? '';
      _descCtrl.text = (form['description'] as String?) ?? '';
      _personaCtrl.text =
          (form['persona'] as String?) ??
          (form['group_persona'] as String?) ??
          '';
      if (isGroup) {
        _openingCtrl.text = (form['opening_line'] as String?) ?? '';
        _openingSpeakerAgentId = form['opening_speaker_agent_id'] as String?;
        _speechMode = (form['speech_mode'] as String?) ?? 'free';
        _isSimulatorMode = (form['is_simulator_mode'] as bool?) ?? false;
        _avatarColor =
            (form['avatar_color'] as num?)?.toInt() ??
            (draft['cover_color'] as num?)?.toInt() ??
            0xFFE8F5E9;
        final members = data['members'] as List? ?? [];
        _members.clear();
        for (final m in members) {
          _members.add(_withMemberId(Map<String, dynamic>.from(m as Map)));
        }
      } else {
        _openingCtrl.text = (form['opening_line'] as String?) ?? '';
        _worldviewCtrl.text = (form['worldview'] as String?) ?? '';
        _gender = (form['gender'] as String?) ?? '';
        _maxResponseLength = Agent.normalizeResponseLength(
          (form['max_response_length'] as num?)?.toInt() ??
              Agent.defaultResponseLength,
        );
        _avatarColor =
            (form['avatar_color'] as num?)?.toInt() ??
            (draft['cover_color'] as num?)?.toInt() ??
            0xFFE8F5E9;
      }
      final tags = data['tags'] as List? ?? [];
      _tags.clear();
      for (final t in tags) {
        _tags.add(t.toString());
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[NetworkUpload] load draft failed: $e');
    }
  }

  Map<String, dynamic> _withMemberId(Map<String, dynamic> member) {
    if (member['agent_id'] == null || member['agent_id'].toString().isEmpty) {
      member['agent_id'] = 'network-member-${_memberSequence++}';
    }
    return member;
  }

  // ─── 从本地选择填充 ─────────────────────────────────

  void _prefillFromAgent(Agent a) {
    _boundAgent = a;
    _nameCtrl.text = a.name;
    _descCtrl.text = a.description;
    _personaCtrl.text = a.persona;
    _openingCtrl.text = a.openingLine ?? '';
    _worldviewCtrl.text = a.worldview;
    _gender = a.gender;
    _maxResponseLength = a.maxResponseLength;
    _avatarColor = a.avatarColor;
    _avatarPath = a.avatarPath;
    setState(() {});
  }

  Future<void> _prefillFromGroup(GroupChat g) async {
    _boundGroup = g;
    _nameCtrl.text = g.name;
    _descCtrl.text = g.description;
    _personaCtrl.text = g.groupPersona ?? '';
    _openingCtrl.text = g.openingLine ?? '';
    _avatarColor = g.avatarColor;
    _speechMode = g.speechMode;
    _isSimulatorMode = g.isSimulatorMode;
    _openingSpeakerAgentId = g.openingSpeakerAgentId;
    _members.clear();

    final membersWithAgents = await ref
        .read(groupServiceProvider)
        .getMembersWithAgents(g.id);
    for (final (:member, :agent) in membersWithAgents) {
      _members.add({
        'agent_id': member.agentId,
        'name': agent.name,
        'gender': agent.gender,
        'description': agent.description,
        'persona': agent.persona,
        'avatar_color': agent.avatarColor,
        'opening_line': agent.openingLine ?? '',
        'worldview': agent.worldview,
        'max_response_length': agent.maxResponseLength,
        'role': member.role,
      });
    }
    if (mounted) setState(() {});
  }

  // ─── 草稿 ──────────────────────────────────────────

  Map<String, dynamic> _collectForm() {
    final form = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'avatar_color': _avatarColor,
    };
    if (isGroup) {
      form['group_persona'] = _personaCtrl.text.trim();
      form['opening_line'] = _openingCtrl.text.trim();
      form['opening_speaker_agent_id'] = _openingSpeakerAgentId;
      form['speech_mode'] = _speechMode;
      form['is_simulator_mode'] = _isSimulatorMode;
    } else {
      form['persona'] = _personaCtrl.text.trim();
      form['opening_line'] = _openingCtrl.text.trim();
      form['worldview'] = _worldviewCtrl.text.trim();
      form['gender'] = _gender;
      form['max_response_length'] = _maxResponseLength;
    }
    return form;
  }

  Map<String, dynamic> _collectDraftData() {
    final data = <String, dynamic>{
      'type': widget.type,
      'form': _collectForm(),
      'tags': List<String>.from(_tags),
    };
    if (isGroup) {
      data['members'] = List<Map<String, dynamic>>.from(_members);
    }
    return data;
  }

  Future<void> _saveDraft() async {
    final l10n = AppLocalizations.of(context);
    final data = _collectDraftData();
    final dataStr = jsonEncode(data);
    final name = _nameCtrl.text.trim();
    try {
      await _draftService.saveDraft(
        draftId: widget.draftId,
        type: widget.type,
        data: dataStr,
        name: name.isEmpty ? null : name,
        coverColor: _avatarColor,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('draftSaved'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('saveDraftFailed')}: $e')),
        );
      }
    }
  }

  // ─── 发布 ──────────────────────────────────────────

  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('pleaseFillName'))));
      return;
    }
    final persona = _personaCtrl.text.trim();
    if (persona.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isGroup
                ? l10n.get('pleaseFillGroupPersona')
                : l10n.get('pleaseFillPersonaPrompt'),
          ),
        ),
      );
      return;
    }
    final openingLine = _openingCtrl.text.trim();
    if (!hasRequiredOpeningLine(openingLine)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('openingLineRequired'))));
      return;
    }
    if (isGroup && _members.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('pleaseAddOneMember'))));
      return;
    }
    if (isGroup &&
        !_isSimulatorMode &&
        (_openingSpeakerAgentId == null ||
            !_members.any(
              (member) => member['agent_id'] == _openingSpeakerAgentId,
            ))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('selectOpeningSpeakerRequired'))),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      NetworkService().setToken(ref.read(authProvider).jwtToken);

      if (isGroup) {
        final source = _boundGroup?.networkSource ?? NetworkCopySource.none;
        final group = (_boundGroup ?? GroupChat(name: name)).copyWith(
          name: name,
          description: _descCtrl.text.trim(),
          groupPersona: persona,
          openingLine: openingLine,
          openingSpeakerAgentId: _openingSpeakerAgentId,
          speechMode: _speechMode,
          isSimulatorMode: _isSimulatorMode,
          networkSource: source,
        );
        final payload = buildGroupNetworkPayload(group, _members, _tags);
        late final Map<String, dynamic> response;
        if (isEditing) {
          response = await NetworkService().editGroup(_editId!, payload);
        } else {
          response = await NetworkService().uploadGroup(payload);
        }
        if (_boundGroup != null) {
          final bound = bindGroupNetworkOwner(group, response);
          await ref.read(groupProvider.notifier).updateGroup(bound);
          _boundGroup = bound;
        }
      } else {
        final agent = (_boundAgent ?? Agent(name: name, persona: persona))
            .copyWith(
              name: name,
              gender: _gender,
              description: _descCtrl.text.trim(),
              persona: persona,
              openingLine: openingLine,
              avatarColor: _avatarColor,
              avatarPath: _avatarPath,
              worldview: _worldviewCtrl.text.trim(),
              maxResponseLength: _maxResponseLength,
            );
        final payload = await buildAgentNetworkPayload(agent, _tags);
        late final Map<String, dynamic> response;
        if (isEditing) {
          // 编辑模式：若本地无 avatar/chat_background 文件路径，删除对应 key
          // 让服务端指针为 nil，保留旧值不被覆盖为空
          if (_avatarPath == null || _avatarPath!.isEmpty) {
            payload.remove('avatar_path');
            payload.remove('avatar');
          }
          // chat_background 编辑模式无法重传本地文件（_publish 未构造），
          // 删除 key 避免服务端覆盖旧值为空字符串
          if (agent.chatBackground == null || agent.chatBackground!.isEmpty) {
            payload.remove('chat_background');
          }
          response = await NetworkService().editAgent(_editId!, payload);
        } else {
          response = await NetworkService().uploadAgent(payload);
        }
        if (_boundAgent != null) {
          final bound = bindAgentNetworkOwner(agent, response);
          await ref.read(agentProvider.notifier).updateAgent(bound);
          _boundAgent = bound;
        }
      }

      // 发布成功后删除草稿（如果有）
      if (widget.draftId != null) {
        await _draftService.deleteDraft(widget.draftId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('submittedForReview'))));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('publishFailed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // ─── 群聊成员管理 ──────────────────────────────────

  void _showAddMemberSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.get('selectAddMethod'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_search),
              title: Text(l10n.get('selectExistingAgent')),
              onTap: () {
                Navigator.pop(ctx);
                _pickExistingAgent();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(l10n.get('newAgent')),
              onTap: () {
                Navigator.pop(ctx);
                _createNewAgent();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pickExistingAgent() {
    final l10n = AppLocalizations.of(context);
    final agents = ref
        .read(agentProvider)
        .agents
        .where((a) => !a.isSimCharacter && !a.isGroupOnly)
        .where((a) => !_members.any((m) => m['name'] == a.name))
        .toList();
    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('noAgentsToSelectInline'))),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: agents.length,
            itemBuilder: (_, i) {
              final a = agents[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(a.avatarColor),
                  child: Text(
                    a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                  ),
                ),
                title: Text(a.name),
                subtitle: a.description.isNotEmpty
                    ? Text(
                        a.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _members.add({
                      'agent_id': a.id,
                      'name': a.name,
                      'gender': a.gender,
                      'description': a.description,
                      'persona': a.persona,
                      'avatar_color': a.avatarColor,
                      'opening_line': a.openingLine ?? '',
                      'worldview': a.worldview,
                      'max_response_length': a.maxResponseLength,
                      'role': 'member',
                    });
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  /// 关键需求：群聊上传面板内嵌创建智能体
  /// 弹出全屏页面，包含完整智能体表单，保存后：
  /// 1. 写入本地 agents 表（通过 agentProvider.createAgent）
  /// 2. 加入群成员列表
  void _createNewAgent() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _InlineAgentCreateScreen(
          onSaved: (agent) {
            setState(() {
              _members.add({
                'agent_id': agent.id,
                'name': agent.name,
                'gender': agent.gender,
                'description': agent.description,
                'persona': agent.persona,
                'avatar_color': agent.avatarColor,
                'opening_line': agent.openingLine ?? '',
                'worldview': agent.worldview,
                'max_response_length': agent.maxResponseLength,
                'role': 'member',
              });
            });
          },
        ),
      ),
    );
  }

  void _editMember(int index) {
    final l10n = AppLocalizations.of(context);
    final m = _members[index];
    final nameCtrl = TextEditingController(text: m['name'] as String? ?? '');
    final personaCtrl = TextEditingController(
      text: m['persona'] as String? ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('editMember')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: l10n.get('nameField')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: personaCtrl,
              decoration: InputDecoration(labelText: l10n.get('persona')),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _members[index] = {
                  ...m,
                  'name': nameCtrl.text.trim(),
                  'persona': personaCtrl.text.trim(),
                };
              });
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }

  // ─── 标签 ──────────────────────────────────────────

  void _addCustomTag() {
    final tag = _tagInputCtrl.text.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      _tagInputCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagInputCtrl.clear();
    });
  }

  void _togglePresetTag(String tag) {
    setState(() {
      if (_tags.contains(tag)) {
        _tags.remove(tag);
      } else {
        _tags.add(tag);
      }
    });
  }

  // ─── 构建 UI ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? (isGroup ? l10n.get('editGroup') : l10n.get('editAgent'))
              : (isGroup ? l10n.get('uploadGroup') : l10n.get('uploadAgent')),
        ),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _saveDraft,
            child: Text(l10n.get('saveDraft')),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.get('publish')),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isEditing &&
                widget.localAgent == null &&
                widget.localGroup == null) ...[
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(l10n.get('writeNew'))),
                  ButtonSegment(
                    value: 1,
                    label: Text(l10n.get('selectFromMine')),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: 16),
              if (_mode == 1) _buildLocalPicker(),
            ],
            if (_mode == 0 || _selectedLocalId != null || isEditing) ...[
              if (isGroup) _buildGroupForm(scheme),
              if (!isGroup) _buildAgentForm(scheme),
              const SizedBox(height: 16),
              _buildTagsSection(scheme),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPicker() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    if (isGroup) {
      final groups = ref.watch(groupProvider).groups;
      if (groups.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(
                Icons.group_outlined,
                size: 48,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.get('noLocalGroups'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final g in groups)
            _buildLocalPickCard(
              scheme: scheme,
              selected: _selectedLocalId == g.id,
              avatarColor: g.avatarColor,
              name: g.name,
              description: g.description,
              onTap: () {
                setState(() => _selectedLocalId = g.id);
                _prefillFromGroup(g);
              },
            ),
          const SizedBox(height: 16),
        ],
      );
    } else {
      final agents = ref
          .watch(agentProvider)
          .agents
          .where((a) => !a.isSimCharacter && !a.isGroupOnly)
          .toList();
      if (agents.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(
                Icons.person_outline,
                size: 48,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.get('noLocalAgents'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final a in agents)
            _buildLocalPickCard(
              scheme: scheme,
              selected: _selectedLocalId == a.id,
              avatarColor: a.avatarColor,
              name: a.name,
              description: a.description,
              onTap: () {
                setState(() => _selectedLocalId = a.id);
                _prefillFromAgent(a);
              },
            ),
          const SizedBox(height: 16),
        ],
      );
    }
  }

  /// “从我的选择”列表项卡片：与全局 cardTheme 同构（brLg + 细描边），
  /// 选中态用 primary 描边 + primaryContainer 浅底高亮，深浅色模式均走 colorScheme
  Widget _buildLocalPickCard({
    required ColorScheme scheme,
    required bool selected,
    required int avatarColor,
    required String name,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.space2),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.brLg,
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.45),
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(avatarColor),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
        ),
        title: Text(name),
        subtitle: description.isNotEmpty
            ? Text(description, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary, size: 20)
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildAgentForm(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    final genderOptions = [
      l10n.get('female'),
      l10n.get('male'),
      l10n.get('otherGender'),
      l10n.get('secret'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(labelText: l10n.get('nameField')),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('gender'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: genderOptions.map((g) {
            return ChoiceChip(
              label: Text(g),
              selected: _gender == g,
              onSelected: (s) => setState(() => _gender = s ? g : ''),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descCtrl,
          decoration: InputDecoration(labelText: l10n.get('descriptionText')),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('avatarColor'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: _colors.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _avatarColor = c),
              child: AnimatedContainer(
                duration: AppTheme.durFast,
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _avatarColor == c
                        ? scheme.primary
                        : Colors.transparent,
                    width: _avatarColor == c ? 3 : 0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('personaPrompt'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _personaCtrl,
          maxLines: 10,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('worldviewLabel'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _worldviewCtrl,
          maxLines: 5,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('openingLine'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _openingCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildGroupForm(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(labelText: l10n.get('groupNameField')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descCtrl,
          decoration: InputDecoration(
            labelText: l10n.get('groupDescriptionField'),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('avatarColor'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: _colors.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _avatarColor = c),
              child: AnimatedContainer(
                duration: AppTheme.durFast,
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _avatarColor == c
                        ? scheme.primary
                        : Colors.transparent,
                    width: _avatarColor == c ? 3 : 0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('groupPersonaField'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _personaCtrl,
          maxLines: 4,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('openingLine'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _openingCtrl,
          maxLines: 3,
          decoration: InputDecoration(hintText: l10n.get('openingLineHint')),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('speechMode'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'free', label: Text(l10n.get('freeLabel'))),
            ButtonSegment(
              value: 'moderator',
              label: Text(l10n.get('moderatorLabel')),
            ),
          ],
          selected: {_speechMode},
          onSelectionChanged: (v) => setState(() => _speechMode = v.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              l10n.get('memberManagement'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.get('addMember')),
              onPressed: _showAddMemberSheet,
            ),
          ],
        ),
        if (_members.isNotEmpty && !_isSimulatorMode) ...[
          const SizedBox(height: 16),
          Text(
            l10n.get('openingSpeaker'),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue:
                _members.any(
                  (member) => member['agent_id'] == _openingSpeakerAgentId,
                )
                ? _openingSpeakerAgentId
                : null,
            decoration: InputDecoration(
              hintText: l10n.get('selectOpeningSpeaker'),
            ),
            items: _members
                .map(
                  (member) => DropdownMenuItem<String>(
                    value: member['agent_id'] as String,
                    child: Text(
                      member['name'] as String? ?? l10n.get('member'),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _openingSpeakerAgentId = value),
          ),
        ],
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.get('noMembersPleaseAdd'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          )
        else
          ..._members.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            final name = (m['name'] as String?) ?? l10n.get('member');
            final role = (m['role'] as String?) ?? 'member';
            final color = (m['avatar_color'] as num?)?.toInt() ?? 0xFFE8F5E9;
            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(color),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                ),
                title: Text(name),
                subtitle: role == 'moderator'
                    ? Text(
                        l10n.get('moderator'),
                        style: const TextStyle(fontSize: 12),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_speechMode == 'moderator')
                      IconButton(
                        icon: Icon(
                          Icons.verified,
                          color: role == 'moderator'
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        tooltip: l10n.get('setAsModerator'),
                        onPressed: () {
                          setState(() {
                            for (var j = 0; j < _members.length; j++) {
                              _members[j]['role'] = (j == i)
                                  ? 'moderator'
                                  : 'member';
                            }
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editMember(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => setState(() {
                        final removedId = _members[i]['agent_id'];
                        _members.removeAt(i);
                        if (_openingSpeakerAgentId == removedId) {
                          _openingSpeakerAgentId = null;
                        }
                      }),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTagsSection(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.get('tagsLabel'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (_loadingTags)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_presetTags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _presetTags.map((t) {
              final selected = _tags.contains(t);
              return FilterChip(
                label: Text(t),
                selected: selected,
                onSelected: (_) => _togglePresetTag(t),
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInputCtrl,
                decoration: InputDecoration(
                  hintText: l10n.get('customTagHint'),
                  isDense: true,
                ),
                onSubmitted: (_) => _addCustomTag(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.add), onPressed: _addCustomTag),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.map((t) {
              return Chip(
                label: Text(t),
                onDeleted: () => setState(() => _tags.remove(t)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// 内嵌的智能体创建页面（用于群聊上传面板新建成员）
///
/// 弹出全屏页面，包含完整智能体表单。保存后：
/// 1. 通过 agentProvider.createAgent 写入本地 agents 表
/// 2. 通过 onSaved 回调将新创建的 Agent 传回父页面加入成员列表
class _InlineAgentCreateScreen extends ConsumerStatefulWidget {
  final void Function(Agent) onSaved;
  const _InlineAgentCreateScreen({required this.onSaved});

  @override
  ConsumerState<_InlineAgentCreateScreen> createState() =>
      _InlineAgentCreateScreenState();
}

class _InlineAgentCreateScreenState
    extends ConsumerState<_InlineAgentCreateScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _worldviewCtrl;
  String _gender = '';
  int _avatarColor = 0xFFE8F5E9;

  static const _colors = [
    0xFFE8F5E9,
    0xFFFFF3E0,
    0xFFFCE4EC,
    0xFFE3F2FD,
    0xFFF3E5F5,
    0xFFE0F2F1,
    0xFFFFF8E1,
    0xFFFBE9E7,
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _personaCtrl = TextEditingController();
    _openingCtrl = TextEditingController();
    _worldviewCtrl = TextEditingController();
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

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('pleaseFillName'))));
      return;
    }
    final persona = _personaCtrl.text.trim();
    if (persona.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('pleaseFillPersonaPrompt'))),
      );
      return;
    }

    // 写入本地 agents 表（通过 agentProvider.createAgent）
    await ref
        .read(agentProvider.notifier)
        .createAgent(
          name: name,
          gender: _gender,
          description: _descCtrl.text.trim(),
          persona: persona,
          openingLine: _openingCtrl.text.trim().isNotEmpty
              ? _openingCtrl.text.trim()
              : null,
          avatarColor: _avatarColor,
          worldview: _worldviewCtrl.text.trim(),
        );

    // 取出刚创建的 agent（createAgent 会将其设为 currentAgent）
    final agent = ref.read(agentProvider).currentAgent;
    if (agent != null) {
      widget.onSaved(agent);
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('agentCreatedAdded'))));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final genderOptions = [
      l10n.get('female'),
      l10n.get('male'),
      l10n.get('otherGender'),
      l10n.get('secret'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('newAgent')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _save,
              child: Text(l10n.get('saveAndAdd')),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: l10n.get('nameField')),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('gender'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: genderOptions.map((g) {
                return ChoiceChip(
                  label: Text(g),
                  selected: _gender == g,
                  onSelected: (s) => setState(() => _gender = s ? g : ''),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: l10n.get('descriptionText'),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('avatarColor'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: _colors.map((c) {
                return GestureDetector(
                  onTap: () => setState(() => _avatarColor = c),
                  child: AnimatedContainer(
                    duration: AppTheme.durFast,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _avatarColor == c
                            ? scheme.primary
                            : Colors.transparent,
                        width: _avatarColor == c ? 3 : 0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('personaPrompt'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _personaCtrl,
              maxLines: 10,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('worldviewLabel'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _worldviewCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('openingLine'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _openingCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
