import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as pp;
import '../config/server_config.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import 'database_service.dart';
import 'network_copy_policy.dart';

/// 群聊序列化/反序列化服务
/// 用于网络市场的群聊上传和下载
class GroupExportService {
  static final GroupExportService _instance = GroupExportService._internal();
  factory GroupExportService() => _instance;
  GroupExportService._internal();

  /// 序列化群聊为上传格式（仅元数据 + 成员设定）
  /// 不含历史消息、记忆
  Future<Map<String, dynamic>> serializeForUpload(String groupId) async {
    // 1. 查 GroupChat
    final group = await DatabaseService.getGroupChat(groupId);
    if (group == null) {
      throw StateError('群聊不存在: $groupId');
    }

    // 2. 查 GroupMember 列表
    final members = await DatabaseService.getGroupMembers(groupId);

    // 3. 对每个 member 查其 Agent（persona/avatar 等）
    final memberPayloads = <Map<String, dynamic>>[];
    var openingSpeakerIndex = -1;
    for (final m in members) {
      final agent = await DatabaseService.getAgent(m.agentId);
      if (agent == null) continue;

      // 4. 组装成员数组（avatar 读取本地文件转 base64）
      final memberData = <String, dynamic>{
        'name': agent.name,
        'gender': agent.gender,
        'description': agent.description,
        'persona': agent.persona,
        'max_response_length': agent.maxResponseLength,
        'avatar_color': agent.avatarColor,
        'avatar': await _encodeAvatarBase64(agent.avatarPath),
        'role': m.role,
        'is_sim_character': agent.isSimCharacter,
      };
      if (agent.openingLine != null && agent.openingLine!.isNotEmpty) {
        memberData['opening_line'] = agent.openingLine;
      }
      if (agent.worldview.isNotEmpty) {
        memberData['worldview'] = agent.worldview;
      }
      memberPayloads.add(memberData);
      if (m.agentId == group.openingSpeakerAgentId) {
        openingSpeakerIndex = memberPayloads.length - 1;
      }
    }

    // 5. 返回完整上传包
    return <String, dynamic>{
      'name': group.name,
      'description': group.description,
      'group_persona': group.groupPersona ?? '',
      'opening_line': group.openingLine ?? '',
      'opening_speaker_index': openingSpeakerIndex,
      'world_setting': group.worldSetting ?? '',
      'speech_mode': group.speechMode,
      'is_simulator_mode': group.isSimulatorMode,
      'avatar_color': group.avatarColor,
      'tags': <String>[], // 由调用方填充
      'members': memberPayloads,
    };
  }

  /// 反序列化下载的群聊数据，并原子写入群聊、成员智能体和成员映射。
  Future<GroupChat> importDownloadedGroup(Map<String, dynamic> data) async {
    // data 格式：{type: 'group', version: N, group: {...}, members: [...]}
    final groupData = data['group'] as Map<String, dynamic>? ?? data;
    final membersData = data['members'] as List? ?? [];
    final networkId = (groupData['id'] as num?)?.toInt();
    final networkUploaderId = (groupData['uploader_id'] as num?)?.toInt();
    final networkVersion =
        (data['version'] as num?)?.toInt() ??
        (groupData['version'] as num?)?.toInt();
    final openingSpeakerIndex =
        (groupData['opening_speaker_index'] as num?)?.toInt() ?? -1;

    // 1. 创建 GroupChat（生成新 UUID）
    final now = DateTime.now().millisecondsSinceEpoch;
    final group = GroupChat(
      name: groupData['name'] as String? ?? '导入的群聊',
      description: groupData['description'] as String? ?? '',
      avatarColor: groupData['avatar_color'] as int? ?? 0xFFE8F5E9,
      groupPersona: (groupData['group_persona'] as String?)?.isNotEmpty == true
          ? groupData['group_persona'] as String
          : null,
      openingLine: (groupData['opening_line'] as String?)?.isNotEmpty == true
          ? groupData['opening_line'] as String
          : null,
      speechMode: groupData['speech_mode'] as String? ?? 'free',
      isSimulatorMode: (groupData['is_simulator_mode'] as bool?) ?? false,
      worldSetting: (groupData['world_setting'] as String?)?.isNotEmpty == true
          ? groupData['world_setting'] as String
          : null,
      networkId: networkId,
      networkUploaderId: networkUploaderId,
      networkSource: NetworkCopySource.downloaded,
      networkVersion: networkVersion,
      createdAt: now,
      updatedAt: now,
    );

    final importedAgents = <Agent>[];
    final importedMembers = <GroupMember>[];
    for (final rawMember in membersData) {
      final m = rawMember as Map<String, dynamic>;
      final avatarSource = m['avatar'] as String?;
      final localAvatar = await _downloadAvatar(avatarSource);

      final agent = Agent(
        name: m['name'] as String? ?? '成员',
        gender: m['gender'] as String? ?? '',
        description: m['description'] as String? ?? '',
        persona: m['persona'] as String? ?? '',
        openingLine: (m['opening_line'] as String?)?.isNotEmpty == true
            ? m['opening_line'] as String
            : null,
        avatarColor: m['avatar_color'] as int? ?? 0xFFE8F5E9,
        avatarPath: localAvatar,
        worldview: m['worldview'] as String? ?? '',
        maxResponseLength:
            (m['max_response_length'] as num?)?.toInt() ??
            Agent.defaultResponseLength,
        isSimCharacter: m['is_sim_character'] as bool? ?? false,
        isGroupOnly: true,
        sourceGroupId: group.id,
        realInfoEnabled: false,
        proactiveCareEnabled: false,
      );
      importedAgents.add(agent);
      importedMembers.add(
        GroupMember(
          groupId: group.id,
          agentId: agent.id,
          role: m['role'] as String? ?? 'member',
          isPresent: true,
        ),
      );
    }

    final narrator = importedAgents.cast<Agent?>().firstWhere(
      (agent) => agent?.isSimCharacter == true,
      orElse: () => null,
    );
    final moderatorIndex = importedMembers.indexWhere(
      (member) => member.role == 'moderator',
    );
    final openingSpeakerAgentId =
        openingSpeakerIndex >= 0 && openingSpeakerIndex < importedAgents.length
        ? importedAgents[openingSpeakerIndex].id
        : (group.isSimulatorMode
              ? (narrator?.id ??
                    (moderatorIndex >= 0
                        ? importedAgents[moderatorIndex].id
                        : null))
              : null);
    final importedGroup = group.copyWith(
      openingSpeakerAgentId: openingSpeakerAgentId,
    );

    final db = await DatabaseService.database;
    await db.transaction((txn) async {
      await txn.insert('group_chats', importedGroup.toMap());
      for (var i = 0; i < importedAgents.length; i++) {
        await txn.insert('agents', importedAgents[i].toMap());
        await txn.insert('group_members', importedMembers[i].toMap());
      }
    });

    return importedGroup;
  }

  /// 兼容旧调用方，仅返回新建群聊 ID。
  Future<String> deserializeDownloaded(Map<String, dynamic> data) async {
    return (await importDownloadedGroup(data)).id;
  }

  /// 下载头像图片到本地
  /// 支持网络 URL 和 data:image/...;base64,... 两种格式
  /// 返回本地文件路径，或 null
  Future<String?> _downloadAvatar(String? avatarSource) async {
    if (avatarSource == null || avatarSource.isEmpty) return null;

    final dir = await pp.getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // data:image/...;base64,...
    if (avatarSource.startsWith('data:image/')) {
      final parts = avatarSource.split(';base64,');
      if (parts.length == 2) {
        final mime = parts[0].replaceFirst('data:', '');
        final ext = mime.contains('png') ? 'png' : 'jpg';
        try {
          final bytes = base64Decode(parts[1]);
          final path = '${dir.path}/group_avatar_$ts.$ext';
          await File(path).writeAsBytes(bytes);
          return path;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    // 网络 URL（http/https）
    if (avatarSource.startsWith('http://') ||
        avatarSource.startsWith('https://')) {
      try {
        final resp = await http
            .get(Uri.parse(avatarSource))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final contentType = resp.headers['content-type'] ?? '';
          final ext = contentType.contains('png') ? 'png' : 'jpg';
          final path = '${dir.path}/group_avatar_$ts.$ext';
          await File(path).writeAsBytes(resp.bodyBytes);
          return path;
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    // 相对路径（基于 baseUrl/uploads/...）
    if (!avatarSource.startsWith('/')) {
      try {
        final url = '${ServerConfig.baseUrl}/$avatarSource';
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final contentType = resp.headers['content-type'] ?? '';
          final ext = contentType.contains('png') ? 'png' : 'jpg';
          final path = '${dir.path}/group_avatar_$ts.$ext';
          await File(path).writeAsBytes(resp.bodyBytes);
          return path;
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// 读取本地头像文件转 base64 data URI
  /// 返回 base64 data URI，或 null
  Future<String?> _encodeAvatarBase64(String? avatarPath) async {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    final file = File(avatarPath);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = avatarPath.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }
}
