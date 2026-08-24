class ProviderConfig {
  final int? id;
  final String name;
  final String apiBaseUrl;
  final String apiKey;
  final String selectedModel;
  final int createdAt;

  ProviderConfig({
    this.id,
    required this.name,
    required this.apiBaseUrl,
    required this.apiKey,
    this.selectedModel = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  ProviderConfig copyWith({
    int? id,
    String? name,
    String? apiBaseUrl,
    String? apiKey,
    String? selectedModel,
  }) {
    return ProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      createdAt: createdAt,
    );
  }

  String get maskedKey {
    if (apiKey.length <= 7) return '****';
    return '${apiKey.substring(0, 3)}****${apiKey.substring(apiKey.length - 4)}';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'api_base_url': apiBaseUrl,
        'api_key': apiKey,
        'selected_model': selectedModel,
        'created_at': createdAt,
      };

  factory ProviderConfig.fromMap(Map<String, dynamic> map) => ProviderConfig(
        id: map['id'] as int?,
        name: map['name'] as String,
        apiBaseUrl: map['api_base_url'] as String,
        apiKey: map['api_key'] as String,
        selectedModel: (map['selected_model'] as String?) ?? '',
        createdAt: map['created_at'] as int?,
      );
}
