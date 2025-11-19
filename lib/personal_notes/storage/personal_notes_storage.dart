import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesStorage {
  static const _schemaVersion = 1;
  static const _notesFolderName = 'הערות';
  static const _txtPrefix = 'הערות אישיות על ';
  static const _txtExtension = '.txt';
  static const _jsonSuffix = '_annotations.json';
  static const _noteHeaderPrefix = '### NOTE ';
  static const _noteFooter = '### END NOTE';

  PersonalNotesStorage._();

  static final PersonalNotesStorage instance = PersonalNotesStorage._();

  static String safeFileName(String bookId) {
    final sanitized =
        bookId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'ספר_ללא_שם' : sanitized;
  }

  Future<String> notesDirectoryPath() async {
    final libraryPath = await AppPaths.getLibraryPath();
    final notesDir = Directory(
      p.join(libraryPath, 'אוצריא', _notesFolderName),
    );

    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }

    return notesDir.path;
  }

  Future<String> _ensureNotesDirectory() async {
    return notesDirectoryPath();
  }

  String _sanitizeBookId(String bookId) {
    return PersonalNotesStorage.safeFileName(bookId);
  }

  Future<File> _getTxtFile(String bookId) async {
    final dir = await _ensureNotesDirectory();
    final safeBookId = _sanitizeBookId(bookId);
    final txtPath = p.join(dir, '$_txtPrefix$safeBookId$_txtExtension');
    final file = File(txtPath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<File> _getJsonFile(String bookId) async {
    final dir = await _ensureNotesDirectory();
    final safeBookId = _sanitizeBookId(bookId);
    final jsonPath = p.join(dir, '$safeBookId$_jsonSuffix');
    final file = File(jsonPath);
    if (!await file.exists()) {
      await file
          .writeAsString(jsonEncode(_emptyBookPayload(bookId)), encoding: utf8);
    }
    return file;
  }

  Map<String, dynamic> _emptyBookPayload(String bookId) => {
        'schema_version': _schemaVersion,
        'book_id': bookId,
        'updated_at': DateTime.now().toIso8601String(),
        'notes': <Map<String, dynamic>>[],
      };

  Future<List<PersonalNote>> readNotes(String bookId) async {
    final jsonFile = await _getJsonFile(bookId);
    final txtFile = await _getTxtFile(bookId);

    final metadata = await _readMetadata(jsonFile, bookId);
    final contents = await _readTxtNotes(txtFile);
    final notes = <PersonalNote>[];

    for (final entry in metadata) {
      final content = contents[entry.id];
      if (content == null) {
        // If note is missing from TXT, skip it silently but keep data for debugging.
        continue;
      }

      final pointer = PersonalNotePointer(
        textStartLine: content.startLine,
        textLineCount: content.totalLines,
      );

      notes.add(entry.copyWith(
        pointer: pointer,
        content: content.body,
      ));
    }

    return notes;
  }

  Future<List<_MetadataOnlyNote>> _readMetadata(File jsonFile, String bookId) async {
    try {
      final data = await jsonFile.readAsString(encoding: utf8);
      if (data.trim().isEmpty) {
        return [];
      }

      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final notes = decoded['notes'] as List<dynamic>? ?? const [];

      return notes.map((item) {
        final map = item as Map<String, dynamic>;
        return _MetadataOnlyNote.fromJson(map, bookId);
      }).toList();
    } catch (e) {
      // If the JSON is corrupted we fall back to empty set but keep the file untouched.
      return [];
    }
  }

  Future<Map<String, _ParsedTxtNote>> _readTxtNotes(File txtFile) async {
    final parsed = <String, _ParsedTxtNote>{};

    if (!await txtFile.exists()) {
      return parsed;
    }

    final lines = await txtFile.readAsLines(encoding: utf8);
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.startsWith(_noteHeaderPrefix)) {
        final id = line.substring(_noteHeaderPrefix.length).trim();
        final startLine = index + 1; // convert to 1-based
        index++;
        final buffer = StringBuffer();
        final contentStartIndex = index;
        while (index < lines.length && lines[index] != _noteFooter) {
          buffer.writeln(lines[index]);
          index++;
        }

        final content = buffer.toString();
        if (index >= lines.length || lines[index] != _noteFooter) {
          // Footer missing - treat as malformed and stop parsing to avoid infinite loop.
          break;
        }

        index++; // Skip footer

        // Optional blank separator line
        if (index < lines.length && lines[index].trim().isEmpty) {
          index++;
        }

        final totalLines = index - (startLine - 1);
        parsed[id] = _ParsedTxtNote(
          id: id,
          body: content.trimRight(),
          startLine: startLine,
          totalLines: totalLines,
          contentLineCount: index - contentStartIndex,
        );
      } else {
        index++;
      }
    }

    return parsed;
  }

  /// Persist notes to disk and returns the notes with updated [PersonalNotePointer] values.
  Future<List<PersonalNote>> writeNotes(String bookId, List<PersonalNote> notes) async {
    final txtFile = await _getTxtFile(bookId);
    final jsonFile = await _getJsonFile(bookId);

    final buffer = StringBuffer();

    final updatedNotes = <PersonalNote>[];
    var currentLine = 1;

    for (final note in notes) {
      final header = '$_noteHeaderPrefix${note.id}\n';
      buffer.write(header);

      final normalizedContent = note.content.replaceAll('\r\n', '\n');
      final contentLines = normalizedContent.isEmpty
          ? <String>['']
          : normalizedContent.split('\n');
      if (contentLines.length > 1 && contentLines.last.isEmpty) {
        contentLines.removeLast();
      }
      for (final line in contentLines) {
        buffer.write(line);
        buffer.write('\n');
      }

      buffer.write('$_noteFooter\n\n');

      final contentLineCount = contentLines.length;
      final totalLines = 2 + contentLineCount + 1; // header + footer + blank separator

      updatedNotes.add(
        note.copyWith(
          pointer: PersonalNotePointer(
            textStartLine: currentLine,
            textLineCount: totalLines,
          ),
        ),
      );

      currentLine += totalLines;
    }

    await txtFile.writeAsString(buffer.toString(), encoding: utf8);

    final jsonPayload = {
      'schema_version': _schemaVersion,
      'book_id': bookId,
      'updated_at': DateTime.now().toIso8601String(),
      'notes': updatedNotes.map((n) => n.toJson()).toList(),
    };

    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonPayload),
      encoding: utf8,
    );

    return updatedNotes;
  }

  Future<List<StoredBookNotes>> listStoredBooks() async {
    final dirPath = await _ensureNotesDirectory();
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return [];
    }

    final result = <StoredBookNotes>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(_jsonSuffix)) continue;

      try {
        final contents = await entity.readAsString(encoding: utf8);
        if (contents.trim().isEmpty) continue;

        final decoded = jsonDecode(contents) as Map<String, dynamic>;
        final bookId = decoded['book_id'] as String? ?? '';
        if (bookId.isEmpty) continue;

        final safeName =
            p.basename(entity.path).replaceAll(_jsonSuffix, '');
        final stat = await entity.stat();

        result.add(
          StoredBookNotes(
            bookId: bookId,
            safeName: safeName,
            updatedAt: stat.modified,
          ),
        );
      } catch (_) {
        // Ignore malformed files during indexing
      }
    }

    result.sort(
      (a, b) => a.bookId.toLowerCase().compareTo(b.bookId.toLowerCase()),
    );
    return result;
  }
}

class _MetadataOnlyNote {
  final String id;
  final String bookId;
  final int? lineNumber;
  final List<String> referenceWords;
  final int? lastKnownLine;
  final PersonalNoteStatus status;
  final PersonalNotePointer pointer;
  final DateTime createdAt;
  final DateTime updatedAt;

  _MetadataOnlyNote({
    required this.id,
    required this.bookId,
    required this.lineNumber,
    required this.referenceWords,
    required this.lastKnownLine,
    required this.status,
    required this.pointer,
    required this.createdAt,
    required this.updatedAt,
  });

  PersonalNote copyWith({
    required PersonalNotePointer pointer,
    required String content,
  }) {
    return PersonalNote(
      id: id,
      bookId: bookId,
      lineNumber: lineNumber,
      referenceWords: referenceWords,
      lastKnownLineNumber: lastKnownLine,
      status: status,
      pointer: pointer,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory _MetadataOnlyNote.fromJson(
    Map<String, dynamic> json,
    String defaultBookId,
  ) {
    final pointerJson = json['pointer'];
    return _MetadataOnlyNote(
      id: json['id'] as String,
      bookId: json['book_id'] as String? ?? defaultBookId,
      lineNumber: json['line'] as int?,
      referenceWords: (json['reference_words'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((element) => element.isNotEmpty)
          .toList(),
      lastKnownLine: json['last_known_line'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
      pointer: pointerJson is Map<String, dynamic>
          ? PersonalNotePointer.fromJson(pointerJson)
          : const PersonalNotePointer(textStartLine: 0, textLineCount: 0),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class _ParsedTxtNote {
  final String id;
  final String body;
  final int startLine;
  final int totalLines;
  final int contentLineCount;

  _ParsedTxtNote({
    required this.id,
    required this.body,
    required this.startLine,
    required this.totalLines,
    required this.contentLineCount,
  });
}

class StoredBookNotes {
  final String bookId;
  final String safeName;
  final DateTime updatedAt;

  StoredBookNotes({
    required this.bookId,
    required this.safeName,
    required this.updatedAt,
  });
}
