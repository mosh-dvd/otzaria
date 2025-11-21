/// Represents a category in the library hierarchy.
class Category {
  /// The unique identifier of the category. Defaults to 0.
  final int id;

  /// The identifier of the parent category, or null if this is a root category.
  final int? parentId;

  /// The title of the category.
  final String title;

  /// The level of the category in the hierarchy (0 for root categories). Defaults to 0.
  final int level;

  /// Creates a new instance of [Category].
  const Category({
    this.id = 0,
    this.parentId,
    required this.title,
    this.level = 0,
  });

  /// Creates a new [Category] instance with updated values.
  Category copyWith({
    int? id,
    int? parentId,
    String? title,
    int? level,
  }) {
    return Category(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      level: level ?? this.level,
    );
  }

  /// Creates a [Category] from a JSON map.
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int? ?? 0,
      parentId: json['parentId'] as int?,
      title: json['title'] as String,
      level: json['level'] as int? ?? 0,
    );
  }

  /// Converts the [Category] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'title': title,
      'level': level,
    };
  }

  @override
  String toString() {
    return 'Category(id: $id, parentId: $parentId, title: $title, level: $level)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Category &&
        other.id == id &&
        other.parentId == parentId &&
        other.title == title &&
        other.level == level;
  }

  @override
  int get hashCode => id.hashCode ^ parentId.hashCode ^ title.hashCode ^ level.hashCode;
}
