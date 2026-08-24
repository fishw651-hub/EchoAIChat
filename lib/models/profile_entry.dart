class ProfileEntry {
  final String id;
  final String category;
  final String key;
  final String value;
  final int confidence;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProfileEntry({
    required this.id,
    required this.category,
    required this.key,
    required this.value,
    this.confidence = 50,
    this.source = 'ai_extracted',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ProfileEntry copyWith({
    String? id, String? category, String? key, String? value,
    int? confidence, String? source, DateTime? createdAt, DateTime? updatedAt,
  }) => ProfileEntry(
    id: id ?? this.id, category: category ?? this.category,
    key: key ?? this.key, value: value ?? this.value,
    confidence: confidence ?? this.confidence, source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'category': category, 'key': key, 'value': value,
    'confidence': confidence, 'source': source,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory ProfileEntry.fromMap(Map<String, dynamic> map) => ProfileEntry(
    id: map['id'] as String,
    category: map['category'] as String,
    key: map['key'] as String,
    value: map['value'] as String,
    confidence: map['confidence'] as int? ?? 50,
    source: map['source'] as String? ?? 'ai_extracted',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );

  static const validCategories = [
    'basic_info', 'interests', 'personality', 'habits',
    'work_study', 'preferences', 'social', 'health',
  ];

  static const categoryLabels = {
    'basic_info': '基本信息',
    'interests': '兴趣爱好',
    'personality': '性格特点',
    'habits': '生活习惯',
    'work_study': '工作学习',
    'preferences': '偏好',
    'social': '社交关系',
    'health': '健康状况',
  };

  static const categoryIcons = {
    'basic_info': '📋',
    'interests': '🎯',
    'personality': '😊',
    'habits': '🌙',
    'work_study': '💼',
    'preferences': '⭐',
    'social': '👥',
    'health': '💪',
  };

  String get categoryLabel => categoryLabels[category] ?? category;
  String get categoryIcon => categoryIcons[category] ?? '📌';
  String get confidenceStars {
    if (confidence >= 90) return '⭐⭐⭐';
    if (confidence >= 60) return '⭐⭐';
    return '⭐';
  }
}
