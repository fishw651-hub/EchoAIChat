import 'package:uuid/uuid.dart';

class Agent {
  static const int minAllowedResponseLength = 50;
  static const int maxAllowedResponseLength = 800;
  static const int defaultResponseLength = 300;

  static int normalizeResponseLength(int value) {
    return value
        .clamp(minAllowedResponseLength, maxAllowedResponseLength)
        .toInt();
  }

  final String id;
  final String name;
  final String gender;
  final String description;
  final String persona;
  final String? openingLine;
  final int avatarColor;
  final String? avatarPath;
  final String? chatBackground;
  final String worldview;
  final bool isActive;
  final String? sourceGroupId;
  final bool isSimCharacter;
  final bool
  isGroupOnly; // hidden from main agent list, only usable in sourceGroupId
  final bool realInfoEnabled; // 是否启用真实信息+用户画像（每智能体独立）
  final bool proactiveCareEnabled; // 是否启用主动关心（仅 realInfoEnabled 时有效）
  final int proactiveCareDailyLimit; // 每日主动关心上限（1–5）
  final int proactiveCareMinIntervalHours; // 距上次聊天的最小间隔小时数（1–12）
  /// 单次 AI 回复的目标字数上限（50–800）。
  final int maxResponseLength;
  final int? networkId;
  final int? networkUploaderId;
  final String networkSource;
  final int? networkVersion;
  final int createdAt;
  final int updatedAt;

  Agent({
    String? id,
    required this.name,
    this.gender = '',
    this.description = '',
    required this.persona,
    this.openingLine,
    this.avatarColor = 0xFFE8F5E9,
    this.avatarPath,
    this.chatBackground,
    this.worldview = '',
    this.isActive = false,
    this.sourceGroupId,
    this.isSimCharacter = false,
    this.isGroupOnly = false,
    this.realInfoEnabled = false,
    this.proactiveCareEnabled = false,
    this.proactiveCareDailyLimit = 1,
    this.proactiveCareMinIntervalHours = 3,
    int maxResponseLength = defaultResponseLength,
    this.networkId,
    this.networkUploaderId,
    this.networkSource = 'none',
    this.networkVersion,
    int? createdAt,
    int? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       maxResponseLength = Agent.normalizeResponseLength(maxResponseLength),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Agent copyWith({
    String? id,
    String? name,
    String? gender,
    String? description,
    String? persona,
    String? openingLine,
    bool clearOpeningLine = false,
    int? avatarColor,
    String? avatarPath,
    String? chatBackground,
    String? worldview,
    bool? isActive,
    String? sourceGroupId,
    bool? isSimCharacter,
    bool? isGroupOnly,
    bool? realInfoEnabled,
    bool? proactiveCareEnabled,
    int? proactiveCareDailyLimit,
    int? proactiveCareMinIntervalHours,
    int? maxResponseLength,
    int? networkId,
    bool clearNetworkId = false,
    int? networkUploaderId,
    bool clearNetworkUploaderId = false,
    String? networkSource,
    int? networkVersion,
    bool clearNetworkVersion = false,
    int? createdAt,
    int? updatedAt,
  }) {
    return Agent(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      description: description ?? this.description,
      persona: persona ?? this.persona,
      openingLine: clearOpeningLine ? null : (openingLine ?? this.openingLine),
      avatarColor: avatarColor ?? this.avatarColor,
      avatarPath: avatarPath ?? this.avatarPath,
      chatBackground: chatBackground ?? this.chatBackground,
      worldview: worldview ?? this.worldview,
      isActive: isActive ?? this.isActive,
      sourceGroupId: sourceGroupId ?? this.sourceGroupId,
      isSimCharacter: isSimCharacter ?? this.isSimCharacter,
      isGroupOnly: isGroupOnly ?? this.isGroupOnly,
      realInfoEnabled: realInfoEnabled ?? this.realInfoEnabled,
      proactiveCareEnabled: proactiveCareEnabled ?? this.proactiveCareEnabled,
      proactiveCareDailyLimit:
          proactiveCareDailyLimit ?? this.proactiveCareDailyLimit,
      proactiveCareMinIntervalHours:
          proactiveCareMinIntervalHours ?? this.proactiveCareMinIntervalHours,
      maxResponseLength: maxResponseLength ?? this.maxResponseLength,
      networkId: clearNetworkId ? null : (networkId ?? this.networkId),
      networkUploaderId: clearNetworkUploaderId
          ? null
          : (networkUploaderId ?? this.networkUploaderId),
      networkSource: networkSource ?? this.networkSource,
      networkVersion: clearNetworkVersion
          ? null
          : (networkVersion ?? this.networkVersion),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'gender': gender,
    'description': description,
    'persona': persona,
    'opening_line': openingLine,
    'avatar_color': avatarColor,
    'avatar_path': avatarPath,
    'chat_background': chatBackground,
    'worldview': worldview,
    'is_active': isActive ? 1 : 0,
    'source_group_id': sourceGroupId,
    'is_sim_character': isSimCharacter ? 1 : 0,
    'is_group_only': isGroupOnly ? 1 : 0,
    'real_info_enabled': realInfoEnabled ? 1 : 0,
    'proactive_care_enabled': proactiveCareEnabled ? 1 : 0,
    'proactive_care_daily_limit': proactiveCareDailyLimit,
    'proactive_care_min_interval_hours': proactiveCareMinIntervalHours,
    'max_response_length': maxResponseLength,
    'network_id': networkId,
    'network_uploader_id': networkUploaderId,
    'network_source': networkSource,
    'network_version': networkVersion,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory Agent.fromMap(Map<String, dynamic> map) => Agent(
    id: map['id'] as String,
    name: map['name'] as String,
    gender: map['gender'] as String? ?? '',
    description: map['description'] as String? ?? '',
    persona: map['persona'] as String,
    openingLine: map['opening_line'] as String?,
    avatarColor: map['avatar_color'] as int? ?? 0xFFE8F5E9,
    avatarPath: map['avatar_path'] as String?,
    chatBackground: map['chat_background'] as String?,
    worldview: map['worldview'] as String? ?? '',
    isActive: (map['is_active'] as int?) == 1,
    sourceGroupId: map['source_group_id'] as String?,
    isSimCharacter: (map['is_sim_character'] as int?) == 1,
    isGroupOnly: (map['is_group_only'] as int?) == 1,
    realInfoEnabled: (map['real_info_enabled'] as int?) == 1,
    proactiveCareEnabled: (map['proactive_care_enabled'] as int?) == 1,
    proactiveCareDailyLimit: (map['proactive_care_daily_limit'] as int?) ?? 1,
    proactiveCareMinIntervalHours:
        (map['proactive_care_min_interval_hours'] as int?) ?? 3,
    maxResponseLength:
        (map['max_response_length'] as num?)?.toInt() ??
        Agent.defaultResponseLength,
    networkId: (map['network_id'] as num?)?.toInt(),
    networkUploaderId: (map['network_uploader_id'] as num?)?.toInt(),
    networkSource: map['network_source'] as String? ?? 'none',
    networkVersion: (map['network_version'] as num?)?.toInt(),
    createdAt: map['created_at'] as int,
    updatedAt: map['updated_at'] as int,
  );
}
