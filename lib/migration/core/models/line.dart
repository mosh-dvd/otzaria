/// Represents an individual line of a book
class Line {
  /// The unique identifier of the line
  final int id;

  /// The identifier of the book this line belongs to
  final int bookId;

  /// The index of the line within the book
  final int lineIndex;

  /// The original HTML content of the line
  final String content;

  const Line({
    this.id = 0,
    required this.bookId,
    required this.lineIndex,
    required this.content,
  });

  /// Creates a new [Line] instance by copying the current instance and
  /// overriding with the provided values.
  Line copyWith({
    int? id,
    int? bookId,
    int? lineIndex,
    String? content,
  }) {
    return Line(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      lineIndex: lineIndex ?? this.lineIndex,
      content: content ?? this.content,
    );
  }

  /// Creates a [Line] instance from a JSON map.
  factory Line.fromJson(Map<String, dynamic> json) {
    return Line(
      id: json['id'] as int? ?? 0,
      bookId: json['bookId'] as int,
      lineIndex: json['lineIndex'] as int,
      content: json['content'] as String,
    );
  }

  /// Converts the [Line] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'lineIndex': lineIndex,
      'content': content,
    };
  }

  @override
  String toString() {
    return 'Line(id: $id, bookId: $bookId, lineIndex: $lineIndex, content: "$content")';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Line &&
        other.id == id &&
        other.bookId == bookId &&
        other.lineIndex == lineIndex &&
        other.content == content;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      bookId,
      lineIndex,
      content,
    );
  }
}
