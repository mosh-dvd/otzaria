import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/personal_notes/migration/legacy_notes_converter.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_storage.dart';

class PersonalNotesRepository {
  final FileSystemData _fileSystem;
  final PersonalNotesService _service;
  final LegacyNotesConverter _converter;
  final PersonalNotesStorage _storage;

  PersonalNotesRepository({
    FileSystemData? fileSystemData,
    PersonalNotesService? service,
    LegacyNotesConverter? converter,
    PersonalNotesStorage? storage,
  })  : _fileSystem = fileSystemData ?? FileSystemData.instance,
        _service = service ?? PersonalNotesService(),
        _converter = converter ?? LegacyNotesConverter(),
        _storage = storage ?? PersonalNotesStorage.instance;

  Future<List<PersonalNote>> loadNotes(String bookId) async {
    final content = await _loadBookContent(bookId);
    return _service.loadNotes(bookId: bookId, bookContent: content);
  }

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required int lineNumber,
    required String content,
  }) async {
    final bookContent = await _loadBookContent(bookId);
    return _service.addNote(
      bookId: bookId,
      bookContent: bookContent,
      lineNumber: lineNumber,
      content: content,
    );
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String noteId,
    required String content,
  }) async {
    final bookContent = await _loadBookContent(bookId);
    return _service.updateNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      content: content,
    );
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
  }) async {
    final bookContent = await _loadBookContent(bookId);
    return _service.deleteNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
    );
  }

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
  }) async {
    final bookContent = await _loadBookContent(bookId);
    return _service.repositionNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      lineNumber: lineNumber,
    );
  }

  Future<LegacyConversionSummary> convertLegacyNotes() async {
    return _converter.convert();
  }

  Future<List<StoredBookNotes>> listBooksWithNotes() {
    return _storage.listStoredBooks();
  }

  Future<String> _loadBookContent(String bookId) async {
    try {
      return await _fileSystem.getBookText(bookId);
    } catch (_) {
      return '';
    }
  }
}
