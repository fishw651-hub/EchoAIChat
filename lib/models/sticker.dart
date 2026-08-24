class Sticker {
  final String id;
  final String description;
  final String imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Sticker({
    required this.id,
    required this.description,
    required this.imagePath,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory Sticker.fromMap(Map<String, dynamic> map) => Sticker(
        id: map['id'] as String,
        description: map['description'] as String,
        imagePath: map['image_path'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        deletedAt: (map['deleted_at'] as int?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
      );
}
