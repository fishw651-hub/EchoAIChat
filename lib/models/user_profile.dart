class UserProfile {
  final int id;
  final String uuid;
  final String username;
  final String email;
  final String nickname;
  final String avatar;
  final String role;
  final double balance;
  final double totalSpent;
  final double totalRecharged;
  final double frozenBalance;
  final double dailyQuotaUsed;
  final double dailyQuotaLeft;
  final double subscriptionQuotaLeft;

  UserProfile({
    required this.id,
    required this.uuid,
    required this.username,
    required this.email,
    this.nickname = '',
    this.avatar = '',
    this.role = 'user',
    this.balance = 0,
    this.totalSpent = 0,
    this.totalRecharged = 0,
    this.frozenBalance = 0,
    this.dailyQuotaUsed = 0,
    this.dailyQuotaLeft = 0,
    this.subscriptionQuotaLeft = 0,
  });

  String get displayName => nickname.isNotEmpty ? nickname : username;

  double get totalAvailable => quotaLeftCombined;

  String get formatDailyUsed => dailyQuotaUsed.toStringAsFixed(2);
  String get formatDailyLeft => dailyQuotaLeft.toStringAsFixed(2);

  double get quotaLeftCombined => dailyQuotaLeft + subscriptionQuotaLeft;

  UserProfile withBalanceSnapshot(Map<String, dynamic> snapshot) => copyWith(
    balance: (snapshot['balance'] as num?)?.toDouble() ?? balance,
    dailyQuotaUsed:
        (snapshot['daily_quota_used'] as num?)?.toDouble() ?? dailyQuotaUsed,
    dailyQuotaLeft:
        (snapshot['daily_quota_left'] as num?)?.toDouble() ?? dailyQuotaLeft,
    subscriptionQuotaLeft:
        (snapshot['subscription_quota_left'] as num?)?.toDouble() ??
        subscriptionQuotaLeft,
  );

  UserProfile copyWith({
    int? id,
    String? uuid,
    String? username,
    String? email,
    String? nickname,
    String? avatar,
    String? role,
    double? balance,
    double? totalSpent,
    double? totalRecharged,
    double? frozenBalance,
    double? dailyQuotaUsed,
    double? dailyQuotaLeft,
    double? subscriptionQuotaLeft,
  }) => UserProfile(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    username: username ?? this.username,
    email: email ?? this.email,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
    role: role ?? this.role,
    balance: balance ?? this.balance,
    totalSpent: totalSpent ?? this.totalSpent,
    totalRecharged: totalRecharged ?? this.totalRecharged,
    frozenBalance: frozenBalance ?? this.frozenBalance,
    dailyQuotaUsed: dailyQuotaUsed ?? this.dailyQuotaUsed,
    dailyQuotaLeft: dailyQuotaLeft ?? this.dailyQuotaLeft,
    subscriptionQuotaLeft: subscriptionQuotaLeft ?? this.subscriptionQuotaLeft,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: (json['id'] as num?)?.toInt() ?? 0,
    uuid: (json['uuid'] as String?) ?? '',
    username: (json['username'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    nickname: (json['nickname'] as String?) ?? '',
    avatar:
        (json['avatar_url'] as String?) ?? (json['avatar'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'user',
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
    totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
    totalRecharged: (json['total_recharged'] as num?)?.toDouble() ?? 0,
    frozenBalance: (json['frozen_balance'] as num?)?.toDouble() ?? 0,
    dailyQuotaUsed: (json['daily_quota_used'] as num?)?.toDouble() ?? 0,
    dailyQuotaLeft: (json['daily_quota_left'] as num?)?.toDouble() ?? 0,
    subscriptionQuotaLeft:
        (json['subscription_quota_left'] as num?)?.toDouble() ?? 0,
  );
}
