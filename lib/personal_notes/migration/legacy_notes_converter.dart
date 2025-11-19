import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_storage.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

class LegacyNotesConverter {
  final PersonalNotesStorage _storage;

  LegacyNotesConverter({PersonalNotesStorage? storage})
      : _storage = storage ?? PersonalNotesStorage.instance;

  Future<LegacyConversionSummary> convert() async {
    final dbPath = await _locateLegacyDatabase();
    if (dbPath == null) {
      return LegacyConversionSummary.empty();
    }

    final database = await openDatabase(dbPath, readOnly: true);
    try {
      final rows = await database.query(
        'notes',
        columns: [
          'note_id',
          'book_id',
          'char_start',
          'content_markdown',
          'status',
          'created_at',
          'updated_at',
          'selected_text_normalized',
        ],
      );

      if (rows.isEmpty) {
        return LegacyConversionSummary.empty(sourcePath: dbPath);
      }

      final grouped = groupBy(rows, (Map<String, dynamic> row) {
        return row['book_id'] as String;
      });

      final summary = LegacyConversionSummary(
        sourcePath: dbPath,
        totalLegacyNotes: rows.length,
      );

      for (final entry in grouped.entries) {
        final bookId = entry.key;
        final existing = await _storage.readNotes(bookId);
        if (existing.isNotEmpty) {
          summary.skippedBooks.add(bookId);
          continue;
        }

        final canonical = await _loadCanonicalText(database, bookId);
        final canonicalLines =
            canonical != null ? canonical.replaceAll('\r\n', '\n').split('\n') : const <String>[];
        final lineOffsets = canonical != null ? _computeLineOffsets(canonical) : const <int>[];

        final convertedNotes = <PersonalNote>[];

        for (final row in entry.value) {
          final note = _convertRow(
            row,
            bookId: bookId,
            canonicalText: canonical,
            canonicalLines: canonicalLines,
            lineOffsets: lineOffsets,
          );
          if (note != null) {
            convertedNotes.add(note);
          }
        }

        if (convertedNotes.isEmpty) {
          continue;
        }

        await _storage.writeNotes(bookId, sortPersonalNotes(convertedNotes));
        summary.convertedBooks.add(bookId);
        summary.convertedNotes += convertedNotes.length;
      }

      return summary;
    } finally {
      await database.close();
    }
  }

  Future<String?> _locateLegacyDatabase() async {
    final candidates = <String>[];
    final supportDbPath = await AppPaths.resolveNotesDbPath('notes.db');
    final debugDbPath = await AppPaths.resolveNotesDbPath('notes_debug.db');
    candidates.add(supportDbPath);
    if (debugDbPath != supportDbPath) {
      candidates.add(debugDbPath);
    }

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Fallback: check legacy location inside library directory
    final libraryPath = await AppPaths.getLibraryPath();
    final fallback = File(p.join(libraryPath, 'notes.db'));
    if (await fallback.exists()) {
      return fallback.path;
    }
    return null;
  }

  Future<String?> _loadCanonicalText(Database database, String bookId) async {
    final result = await database.query(
      'canonical_documents',
      columns: ['canonical_text'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first['canonical_text'] as String?;
  }

  PersonalNote? _convertRow(
    Map<String, dynamic> row, {
    required String bookId,
    required String? canonicalText,
    required List<String> canonicalLines,
    required List<int> lineOffsets,
  }) {
    final noteId = row['note_id'] as String?;
    final content = (row['content_markdown'] as String?)?.trim() ?? '';
    if (noteId == null || content.isEmpty) {
      return null;
    }

    final legacyStatus = row['status'] as String? ?? 'anchored';
    final createdAtStr = row['created_at'] as String?;
    final updatedAtStr = row['updated_at'] as String?;
    final fallbackWords = (row['selected_text_normalized'] as String?) ?? '';
    final charStart = row['char_start'] as int?;

    final createdAt = _parseDate(createdAtStr);
    final updatedAt = _parseDate(updatedAtStr);

    int? lineNumber;
    List<String> referenceWords = const [];

    if (canonicalText != null && charStart != null) {
      lineNumber = _findLineNumber(lineOffsets, charStart, canonicalText.length);
      if (lineNumber != null &&
          lineNumber > 0 &&
          lineNumber <= canonicalLines.length) {
        referenceWords =
            extractReferenceWordsFromLine(canonicalLines[lineNumber - 1]);
      }
    }

    if (referenceWords.isEmpty && fallbackWords.isNotEmpty) {
      referenceWords = extractReferenceWordsFromLine(fallbackWords);
    }

    PersonalNoteStatus status = PersonalNoteStatus.located;
    int? lastKnownLine;
    int? finalLineNumber = lineNumber;

    if (legacyStatus == 'orphan' || lineNumber == null) {
      status = PersonalNoteStatus.missing;
      lastKnownLine = lineNumber;
      finalLineNumber = null;
    }

    return PersonalNote(
      id: noteId,
      bookId: bookId,
      lineNumber: finalLineNumber,
      referenceWords: referenceWords,
      lastKnownLineNumber: lastKnownLine,
      status: status,
      pointer: const PersonalNotePointer(textStartLine: 0, textLineCount: 0),
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  DateTime _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return DateTime.now();
    }
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  List<int> _computeLineOffsets(String text) {
    final offsets = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        offsets.add(i + 1);
      }
    }
    return offsets;
  }

  int? _findLineNumber(List<int> offsets, int charStart, int textLength) {
    if (charStart < 0 || charStart > textLength) {
      return null;
    }
    var low = 0;
    var high = offsets.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (offsets[mid] <= charStart) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result + 1;
  }
}

class LegacyConversionSummary {
  final String? sourcePath;
  final int totalLegacyNotes;
  int convertedNotes;
  final List<String> convertedBooks;
  final List<String> skippedBooks;

  LegacyConversionSummary({
    required this.sourcePath,
    required this.totalLegacyNotes,
    this.convertedNotes = 0,
    List<String>? convertedBooks,
    List<String>? skippedBooks,
  })  : convertedBooks = convertedBooks ?? <String>[],
        skippedBooks = skippedBooks ?? <String>[];

  factory LegacyConversionSummary.empty({String? sourcePath}) {
    return LegacyConversionSummary(
      sourcePath: sourcePath,
      totalLegacyNotes: 0,
      convertedNotes: 0,
    );
  }

  bool get hasLegacyData => totalLegacyNotes > 0;
}
