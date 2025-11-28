import 'dart:math';

import 'package:collection/collection.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_storage.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

class PersonalNotesService {
  final PersonalNotesStorage _storage;
  final Random _random;

  PersonalNotesService({
    PersonalNotesStorage? storage,
    Random? random,
  })  : _storage = storage ?? PersonalNotesStorage.instance,
        _random = random ?? Random();

  Future<List<PersonalNote>> loadNotes({
    required String bookId,
    required String bookContent,
  }) async {
    final notes = await _storage.readNotes(bookId);
    final lines = splitBookContentIntoLines(bookContent);

    bool changesDetected = false;
    final reconciled = <PersonalNote>[];

    for (final note in notes) {
      final updated = _reconcileLocation(note, lines, bookId);
      if (updated != note) {
        changesDetected = true;
      }
      reconciled.add(updated);
    }

    if (changesDetected) {
      return await _storage.writeNotes(
        bookId,
        sortPersonalNotes(reconciled),
      );
    }

    return sortPersonalNotes(reconciled);
  }

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required String bookContent,
    required int lineNumber,
    required String content,
    String? selectedText,
  }) async {
    final notes = await _storage.readNotes(bookId);
    final lines = splitBookContentIntoLines(bookContent);
    final normalizedLineNumber = lineNumber.clamp(1, lines.length);

    final referenceWords =
        extractReferenceWordsFromLines(lines, normalizedLineNumber, excludeBookTitle: bookId);
    
    // Use selectedText if provided, otherwise extract display text from the line
    // Always remove nikud and te'amim from the display title
    final displayTitle = selectedText?.trim().isNotEmpty == true
        ? removeHebrewDiacritics(selectedText!.trim())
        : extractDisplayTextFromLines(lines, normalizedLineNumber, excludeBookTitle: bookId);

    final now = DateTime.now();
    final newNote = PersonalNote(
      id: _generateId(),
      bookId: bookId,
      lineNumber: normalizedLineNumber,
      referenceWords: referenceWords,
      displayTitle: displayTitle,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      pointer: const PersonalNotePointer(textStartLine: 0, textLineCount: 0),
      content: content.trimRight(),
      createdAt: now,
      updatedAt: now,
    );

    final updatedList = [...notes, newNote];

    return await _storage.writeNotes(
      bookId,
      sortPersonalNotes(updatedList),
    );
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    String? content,
  }) async {
    final notes = await _storage.readNotes(bookId);
    final index = notes.indexWhere((n) => n.id == noteId);
    if (index == -1) {
      return notes;
    }

    final now = DateTime.now();
    final updatedNote = notes[index].copyWith(
      content: content?.trimRight() ?? notes[index].content,
      updatedAt: now,
    );

    final updatedList = [...notes]..[index] = updatedNote;

    final reconciled = await _reconcileAndPersist(
      bookId: bookId,
      bookContent: bookContent,
      notes: updatedList,
    );

    return reconciled;
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String bookContent,
    required String noteId,
  }) async {
    final notes = await _storage.readNotes(bookId);
    final filtered = notes.where((n) => n.id != noteId).toList();
    if (filtered.length == notes.length) {
      return notes;
    }

    return await _storage.writeNotes(
      bookId,
      sortPersonalNotes(filtered),
    );
  }

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    required int lineNumber,
  }) async {
    final notes = await _storage.readNotes(bookId);
    final index = notes.indexWhere((n) => n.id == noteId);
    if (index == -1) {
      return notes;
    }

    final lines = splitBookContentIntoLines(bookContent);
    final normalizedLineNumber = lineNumber.clamp(1, lines.length);
    final newReference =
        extractReferenceWordsFromLines(lines, normalizedLineNumber, excludeBookTitle: bookId);
    final newDisplayTitle =
        extractDisplayTextFromLines(lines, normalizedLineNumber, excludeBookTitle: bookId);
    final now = DateTime.now();

    final updatedNote = notes[index].copyWith(
      lineNumber: normalizedLineNumber,
      referenceWords: newReference,
      displayTitle: newDisplayTitle,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      updatedAt: now,
    );

    final updatedList = [...notes]..[index] = updatedNote;

    return await _storage.writeNotes(
      bookId,
      sortPersonalNotes(updatedList),
    );
  }

  Future<List<PersonalNote>> _reconcileAndPersist({
    required String bookId,
    required String bookContent,
    required List<PersonalNote> notes,
  }) async {
    final lines = splitBookContentIntoLines(bookContent);
    final reconciled = <PersonalNote>[];

    for (final note in notes) {
      final updated = _reconcileLocation(note, lines, bookId);
      reconciled.add(updated);
    }

    return await _storage.writeNotes(bookId, sortPersonalNotes(reconciled));
  }

  PersonalNote _reconcileLocation(PersonalNote note, List<String> lines, String bookId) {
    if (note.status == PersonalNoteStatus.missing || note.lineNumber == null) {
      return note;
    }

    final lineIndex = note.lineNumber! - 1;
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return note.copyWith(
        status: PersonalNoteStatus.missing,
        lastKnownLineNumber: note.lineNumber,
        lineNumber: null,
        updatedAt: DateTime.now(),
      );
    }

    final actualWords =
        extractReferenceWordsFromLines(lines, note.lineNumber!, excludeBookTitle: bookId);

    if (_wordsMatch(note.referenceWords, actualWords)) {
      // no change required, but keep reference words up to date
      // IMPORTANT: We keep the existing displayTitle - don't overwrite it!
      if (const ListEquality<String>().equals(note.referenceWords, actualWords)) {
        return note;
      }
      return note.copyWith(
        referenceWords: actualWords,
        updatedAt: DateTime.now(),
      );
    }

    final match = _searchNearby(lines, note.lineNumber!, note.referenceWords, bookId);
    if (match != null) {
      // When we find the note in a new location, keep the existing displayTitle
      return note.copyWith(
        lineNumber: match.line,
        referenceWords: match.words,
        lastKnownLineNumber: note.lineNumber,
        status: PersonalNoteStatus.located,
        updatedAt: DateTime.now(),
      );
    }

    return note.copyWith(
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: note.lineNumber,
      lineNumber: null,
      updatedAt: DateTime.now(),
    );
  }

  _LineMatch? _searchNearby(
    List<String> lines,
    int centerLine,
    List<String> reference,
    String bookId,
  ) {
    for (int offset = -5; offset <= 5; offset++) {
      if (offset == 0) continue;
      final candidateLine = centerLine + offset;
      if (candidateLine < 1 || candidateLine > lines.length) {
        continue;
      }

      final words = extractReferenceWordsFromLines(lines, candidateLine, excludeBookTitle: bookId);
      if (_wordsMatch(reference, words)) {
        return _LineMatch(line: candidateLine, words: words);
      }
    }
    return null;
  }

  bool _wordsMatch(List<String> stored, List<String> actual) {
    final ratio = computeWordOverlapRatio(stored, actual);
    return ratio >= 0.8;
  }

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'pn_$timestamp$randomPart';
  }

}

class _LineMatch {
  final int line;
  final List<String> words;

  _LineMatch({
    required this.line,
    required this.words,
  });
}
