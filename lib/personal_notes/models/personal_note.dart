import 'package:equatable/equatable.dart';

/// Indicates whether a personal note currently has a valid location in the book.
enum PersonalNoteStatus {
  /// The note is anchored to a specific line in the book.
  located,

  /// The note lost its anchor and awaits manual reposition.
  missing,
}

/// Represents a stored personal note.
class PersonalNote extends Equatable {
  /// Unique note identifier.
  final String id;

  /// Title of the book the note belongs to.
  final String bookId;

  /// Line number in the book (1-based). `null` when [status] is [PersonalNoteStatus.missing].
  final int? lineNumber;

  /// Display title for the note - the text from the beginning of the line.
  /// Used for display and for matching when the book content changes.
  final String? displayTitle;

  /// If the note lost its anchor, we keep the previous line number for UI hints.
  final int? lastKnownLineNumber;

  /// Current status of the note.
  final PersonalNoteStatus status;

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
    this.displayTitle,
    required this.lastKnownLineNumber,
    required this.status,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation =>
      status == PersonalNoteStatus.located && lineNumber != null;


  /// Get the title to display
  String get title => displayTitle ?? '';

  PersonalNote copyWith({
    int? lineNumber,
    String? displayTitle,
    bool clearDisplayTitle = false,
    int? lastKnownLineNumber,
    PersonalNoteStatus? status,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonalNote(
      id: id,
      bookId: bookId,
      lineNumber: lineNumber ?? this.lineNumber,
      displayTitle:
          clearDisplayTitle ? null : (displayTitle ?? this.displayTitle),
      lastKnownLineNumber: lastKnownLineNumber ?? this.lastKnownLineNumber,
      status: status ?? this.status,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        bookId,
        lineNumber,
        displayTitle,
        lastKnownLineNumber,
        status,
        content,
        createdAt,
        updatedAt,
      ];
}
