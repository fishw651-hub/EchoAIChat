import 'package:uuid/uuid.dart';

class GroupChat {
  final String id;
  final String name;
  final String description;
  final int avatarColor;
  final String? avatarIcon;
  final String? avatarPath; // 本地图片路径（PNG/JPG），非空时优先于 avatarIcon
  final String? groupPersona;
  final String? openingLine;
  /// 普通群聊开场白的发送者；模拟器模式会在创建旁白后写入旁白 ID。
  final String? openingSpeakerAgentId;
  final String speechMode;
  final bool isSimulatorMode;
  final String? worldSetting;
  /// 记忆共用：true 时群聊长期/基础记忆直接写入各成员私聊记忆，
  /// 且群消息镜像写入每个在场成员的私聊短期记忆
  final bool linkedMemory;
  final int? networkId;
  final int? networkUploaderId;
  final String networkSource;
  final int? networkVersion;
  final int createdAt;
  final int updatedAt;

  GroupChat({
    String? id,
    required this.name,
    this.description = '',
    this.avatarColor = 0xFFE8F5E9,
    this.avatarIcon,
    this.avatarPath,
    this.groupPersona,
    this.openingLine,
    this.openingSpeakerAgentId,
    this.speechMode = 'free',
    this.isSimulatorMode = false,
    this.worldSetting,
    this.linkedMemory = false,
    this.networkId,
    this.networkUploaderId,
    this.networkSource = 'none',
    this.networkVersion,
    int? createdAt,
    int? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  GroupChat copyWith({
    String? name,
    String? description,
    int? avatarColor,
    String? avatarIcon,
    bool clearAvatarIcon = false,
    String? avatarPath,
    bool clearAvatarPath = false,
    String? groupPersona,
    String? openingLine,
    bool clearOpeningLine = false,
    String? openingSpeakerAgentId,
    bool clearOpeningSpeakerAgentId = false,
    String? speechMode,
    bool? isSimulatorMode,
    String? worldSetting,
    bool? linkedMemory,
    int? networkId,
    bool clearNetworkId = false,
    int? networkUploaderId,
    bool clearNetworkUploaderId = false,
    String? networkSource,
    int? networkVersion,
    bool clearNetworkVersion = false,
    int? updatedAt,
  }) {
    return GroupChat(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarColor: avatarColor ?? this.avatarColor,
      avatarIcon: clearAvatarIcon ? null : (avatarIcon ?? this.avatarIcon),
      avatarPath: clearAvatarPath ? null : (avatarPath ?? this.avatarPath),
      groupPersona: groupPersona ?? this.groupPersona,
      openingLine:
          clearOpeningLine ? null : (openingLine ?? this.openingLine),
      openingSpeakerAgentId: clearOpeningSpeakerAgentId
          ? null
          : (openingSpeakerAgentId ?? this.openingSpeakerAgentId),
      speechMode: speechMode ?? this.speechMode,
      isSimulatorMode: isSimulatorMode ?? this.isSimulatorMode,
      worldSetting: worldSetting ?? this.worldSetting,
      linkedMemory: linkedMemory ?? this.linkedMemory,
      networkId: clearNetworkId ? null : (networkId ?? this.networkId),
      networkUploaderId: clearNetworkUploaderId
          ? null
          : (networkUploaderId ?? this.networkUploaderId),
      networkSource: networkSource ?? this.networkSource,
      networkVersion:
          clearNetworkVersion ? null : (networkVersion ?? this.networkVersion),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_color': avatarColor,
        'avatar_icon': avatarIcon,
        'avatar_path': avatarPath,
        'group_persona': groupPersona,
        'opening_line': openingLine,
        'opening_speaker_agent_id': openingSpeakerAgentId,
        'speech_mode': speechMode,
        'simulator_mode': isSimulatorMode ? 1 : 0,
        'world_setting': worldSetting,
        'linked_memory': linkedMemory ? 1 : 0,
        'network_id': networkId,
        'network_uploader_id': networkUploaderId,
        'network_source': networkSource,
        'network_version': networkVersion,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GroupChat.fromMap(Map<String, dynamic> map) => GroupChat(
        id: map['id'] as String,
        name: map['name'] as String,
        description: (map['description'] as String?) ?? '',
        avatarColor: (map['avatar_color'] as int?) ?? 0xFFE8F5E9,
        avatarIcon: map['avatar_icon'] as String?,
        avatarPath: map['avatar_path'] as String?,
        groupPersona: map['group_persona'] as String?,
        openingLine: map['opening_line'] as String?,
        openingSpeakerAgentId: map['opening_speaker_agent_id'] as String?,
        speechMode: (map['speech_mode'] as String?) ?? 'free',
        isSimulatorMode: (map['simulator_mode'] as int?) == 1,
        worldSetting: map['world_setting'] as String?,
        linkedMemory: (map['linked_memory'] as int?) == 1,
        networkId: (map['network_id'] as num?)?.toInt(),
        networkUploaderId: (map['network_uploader_id'] as num?)?.toInt(),
        networkSource: map['network_source'] as String? ?? 'none',
        networkVersion: (map['network_version'] as num?)?.toInt(),
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );
}
