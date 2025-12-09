import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';

class TextBookRepository {
  final FileSystemData _fileSystem;
  final SqliteDataProvider _sqliteProvider;

  TextBookRepository({
    required FileSystemData fileSystem,
    SqliteDataProvider? sqliteProvider,
  })  : _fileSystem = fileSystem,
        _sqliteProvider = sqliteProvider ?? SqliteDataProvider.instance;

  Future<String> getBookContent(TextBook book) async {
    return await book.text;
  }

  Future<List<Link>> getBookLinks(TextBook book) async {
    return await book.links;
  }

  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return await book.tableOfContents;
  }

  /// מחזיר רשימת פרשנים זמינים לספר מה-DB
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    final repository = _sqliteProvider.repository;
    if (repository == null) {
      return [];
    }

    // מקבל את ה-book מה-DB לפי שם
    final dbBook = await repository.getBookByTitle(book.title);
    if (dbBook == null) {
      return [];
    }

    // שולף את הפרשנים ישירות מה-DB
    final commentatorsData =
        await repository.database.linkDao.selectCommentatorsByBook(dbBook.id);

    // ממפה לרשימת שמות ייחודיים
    final commentatorTitles = commentatorsData
        .map((row) => row['targetBookTitle'] as String)
        .toSet()
        .toList();

    commentatorTitles.sort((a, b) => a.compareTo(b));
    return commentatorTitles;
  }

  Future<bool> bookExists(String title) async {
    return await _fileSystem.bookExists(title);
  }

  Future<void> saveBookContent(TextBook book, String content) async {
    await _fileSystem.saveBookText(book.title, content);
  }
}
