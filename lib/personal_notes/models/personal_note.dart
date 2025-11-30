import 'package:equatable/equatable.dart';

/// Indicates whether a personal note currently has a valid location in the book.
enum PersonalNoteStatus {
  /// The note is anchored to a specific line in the book.
  located,

  /// The note lost its anchor and awaits manual reposition.
  missing,
}

/// Metadata that links the note content in the TXT file with its location.
class PersonalNotePointer extends Equatable {
  /// First line (1-based) within the TXT file where the note header is stored.
  final int textStartLine;

  /// Total amount of lines (including header/footer) that belong to the note.
  final int textLineCount;

  const PersonalNotePointer({
    required this.textStartLine,
    required this.textLineCount,
  });

  PersonalNotePointer copyWith({
    int? textStartLine,
    int? textLineCount,
  }) {
    return PersonalNotePointer(
      textStartLine: textStartLine ?? this.textStartLine,
      textLineCount: textLineCount ?? this.textLineCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'text_start_line': textStartLine,
        'text_line_count': textLineCount,
      };

  factory PersonalNotePointer.fromJson(Map<String, dynamic> json) {
    return PersonalNotePointer(
      textStartLine: json['text_start_line'] as int,
      textLineCount: json['text_line_count'] as int,
    );
  }

  @override
  List<Object?> get props => [textStartLine, textLineCount];
}

/// Represents a stored personal note.
///
/// The actual note body is persisted inside the TXT file while this object
/// keeps the metadata that lives inside the JSON file. Both parts are linked
/// via the [pointer] information.
class PersonalNote extends Equatable {
  /// Unique note identifier (UUID).
  final String id;

  /// Title of the book the note belongs to.
  final String bookId;

  /// Line number in the book (1-based). `null` when [status] is [PersonalNoteStatus.missing].
  final int? lineNumber;

  /// First 10 words that were captured from the line when the note was created.
  final List<String> referenceWords;

  /// Display title for the note - either the text selected by the user,
  /// or the original text from the beginning of the line (without normalization).
  /// This is shown to the user instead of "Line X".
  final String? displayTitle;

  /// If the note lost its anchor, we keep the previous line number for UI hints.
  final int? lastKnownLineNumber;

  /// Current status of the note.
  final PersonalNoteStatus status;

  /// Pointer to the note content inside the TXT file.
  final PersonalNotePointer pointer;

  /// Full user supplied note content (trimmed, can span multiple lines).
  final String content;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last update timestamp.
  final DateTime updatedAt;

  const PersonalNote({
    required this.id,
    required this.bookId,
    required this.lineNumber,
    required this.referenceWords,
    this.displayTitle,
    required this.lastKnownLineNumber,
    required this.status,
    required this.pointer,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation => status == PersonalNoteStatus.located && lineNumber != null;

  /// First 10 reference words as a single string separated by spaces.
  String get referenceSignature => referenceWords.join(' ');

  /// Get the title to display - either the stored displayTitle or fallback to reference words.
  String get title {
    if (displayTitle?.isNotEmpty == true) {
      return displayTitle!;
    }
    // Fallback to reference words (for old notes)
    return referenceWords.take(5).join(' ');
  }

  PersonalNote copyWith({
    int? lineNumber,
    List<String>? referenceWords,
    String? displayTitle,
    bool clearDisplayTitle = false,
    int? lastKnownLineNumber,
    PersonalNoteStatus? status,
    PersonalNotePointer? pointer,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonalNote(
      id: id,
      bookId: bookId,
      lineNumber: lineNumber ?? this.lineNumber,
      referenceWords: referenceWords ?? this.referenceWords,
      displayTitle: clearDisplayTitle ? null : (displayTitle ?? this.displayTitle),
      lastKnownLineNumber: lastKnownLineNumber ?? this.lastKnownLineNumber,
      status: status ?? this.status,
      pointer: pointer ?? this.pointer,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'book_id': bookId,
        'line': lineNumber,
        'reference_words': referenceWords,
        'display_title': displayTitle,
        'last_known_line': lastKnownLineNumber,
        'status': status.name,
        'pointer': pointer.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PersonalNote.fromJson({
    required Map<String, dynamic> json,
    required String content,
  }) {
    final rawWords = json['reference_words'] as List<dynamic>? ?? const [];
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      lineNumber: json['line'] as int?,
      referenceWords: rawWords.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
      displayTitle: json['display_title'] as String?,
      lastKnownLineNumber: json['last_known_line'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
      pointer: PersonalNotePointer.fromJson(json['pointer'] as Map<String, dynamic>),
      content: content,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        bookId,
        lineNumber,
        referenceWords,
        displayTitle,
        lastKnownLineNumber,
        status,
        pointer,
        content,
        createdAt,
        updatedAt,
      ];
}
