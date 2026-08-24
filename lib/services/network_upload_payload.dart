import '../models/agent.dart';
import '../models/group_chat.dart';
import 'agent_export_service.dart';
import 'network_copy_policy.dart';

Future<Map<String, dynamic>> buildAgentNetworkPayload(
  Agent agent,
  List<String> tags,
) async {
  _validateUploadSource(agent.networkSource);
  _validateOpeningLine(agent.openingLine);

  final payload = await AgentExportService.serializeForUpload(agent);
  payload['tags'] = List<String>.from(tags);
  payload['source_kind'] = agent.networkSource;
  return payload;
}

Map<String, dynamic> buildGroupNetworkPayload(
  GroupChat group,
  List<Map<String, dynamic>> members,
  List<String> tags,
) {
  _validateUploadSource(group.networkSource);
  _validateOpeningLine(group.openingLine);
  final openingSpeakerIndex = group.openingSpeakerAgentId == null
      ? -1
      : members.indexWhere(
          (member) => member['agent_id'] == group.openingSpeakerAgentId,
        );

  return <String, dynamic>{
    'name': group.name,
    'description': group.description,
    'group_persona': group.groupPersona ?? '',
    'opening_line': group.openingLine!.trim(),
    'opening_speaker_index': openingSpeakerIndex,
    'world_setting': group.worldSetting ?? '',
    'speech_mode': group.speechMode,
    'is_simulator_mode': group.isSimulatorMode,
    'avatar_color': group.avatarColor,
    'tags': List<String>.from(tags),
    'members': members.map((member) {
      final payload = Map<String, dynamic>.from(member);
      payload.remove('agent_id');
      return payload;
    }).toList(),
    'source_kind': group.networkSource,
  };
}

Agent bindAgentNetworkOwner(Agent agent, Map<String, dynamic> response) {
  return agent.copyWith(
    networkId: (response['id'] as num?)?.toInt(),
    networkUploaderId: (response['uploader_id'] as num?)?.toInt(),
    networkSource: NetworkCopySource.owner,
    networkVersion: (response['version'] as num?)?.toInt(),
  );
}

GroupChat bindGroupNetworkOwner(
  GroupChat group,
  Map<String, dynamic> response,
) {
  return group.copyWith(
    networkId: (response['id'] as num?)?.toInt(),
    networkUploaderId: (response['uploader_id'] as num?)?.toInt(),
    networkSource: NetworkCopySource.owner,
    networkVersion: (response['version'] as num?)?.toInt(),
  );
}

void _validateUploadSource(String source) {
  if (!canUploadNetworkCopy(source)) {
    throw StateError('下载的网络作品禁止上传或修改网络版本');
  }
}

void _validateOpeningLine(String? openingLine) {
  if (!hasRequiredOpeningLine(openingLine)) {
    throw ArgumentError.value(openingLine, 'openingLine', '开场白是必须书写的');
  }
}
