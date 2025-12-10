import 'package:sqflite/sqflite.dart';
import '../../core/models/book.dart';
import 'database.dart';

class BookDao {
  final MyDatabase _db;

  BookDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT * FROM book ORDER BY orderIndex, title');
    return result.map((row) => Book.fromJson(row)).toList();
  }

  /// Gets all books with their relations (authors, topics, pubPlaces, pubDates) in a single optimized query.
  /// This is much faster than calling getAllBooks() and then loading relations separately.
  Future<List<Map<String, dynamic>>> getAllBooksWithRelations() async {
    final db = await database;

    // Get all books
    final books =
        await db.rawQuery('SELECT * FROM book ORDER BY orderIndex, title');

    if (books.isEmpty) return [];

    // Get all book IDs
    final bookIds = books.map((b) => b['id'] as int).toList();
    final bookIdsStr = bookIds.join(',');

    // Load all relations in parallel with single queries each
    final results = await Future.wait([
      // Authors
      db.rawQuery('''
        SELECT ba.bookId, a.id, a.name
        FROM book_author ba
        JOIN author a ON ba.authorId = a.id
        WHERE ba.bookId IN ($bookIdsStr)
        ORDER BY ba.bookId
      '''),
      // Topics
      db.rawQuery('''
        SELECT bt.bookId, t.id, t.name
        FROM book_topic bt
        JOIN topic t ON bt.topicId = t.id
        WHERE bt.bookId IN ($bookIdsStr)
        ORDER BY bt.bookId
      '''),
      // Pub Places
      db.rawQuery('''
        SELECT bpp.bookId, pp.id, pp.name
        FROM book_pub_place bpp
        JOIN pub_place pp ON bpp.pubPlaceId = pp.id
        WHERE bpp.bookId IN ($bookIdsStr)
        ORDER BY bpp.bookId
      '''),
      // Pub Dates
      db.rawQuery('''
        SELECT bpd.bookId, pd.id, pd.date
        FROM book_pub_date bpd
        JOIN pub_date pd ON bpd.pubDateId = pd.id
        WHERE bpd.bookId IN ($bookIdsStr)
        ORDER BY bpd.bookId
      '''),
    ]);

    final authorsData = results[0];
    final topicsData = results[1];
    final pubPlacesData = results[2];
    final pubDatesData = results[3];

    // Group relations by bookId
    final authorsByBook = <int, List<Map<String, dynamic>>>{};
    final topicsByBook = <int, List<Map<String, dynamic>>>{};
    final pubPlacesByBook = <int, List<Map<String, dynamic>>>{};
    final pubDatesByBook = <int, List<Map<String, dynamic>>>{};

    for (final row in authorsData) {
      final bookId = row['bookId'] as int;
      authorsByBook.putIfAbsent(bookId, () => []);
      authorsByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
    }

    for (final row in topicsData) {
      final bookId = row['bookId'] as int;
      topicsByBook.putIfAbsent(bookId, () => []);
      topicsByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
    }

    for (final row in pubPlacesData) {
      final bookId = row['bookId'] as int;
      pubPlacesByBook.putIfAbsent(bookId, () => []);
      pubPlacesByBook[bookId]!.add({'id': row['id'], 'name': row['name']});
    }

    for (final row in pubDatesData) {
      final bookId = row['bookId'] as int;
      pubDatesByBook.putIfAbsent(bookId, () => []);
      pubDatesByBook[bookId]!.add({'id': row['id'], 'date': row['date']});
    }

    // Combine books with their relations
    return books.map((book) {
      final bookId = book['id'] as int;
      return {
        ...book,
        'authors': authorsByBook[bookId] ?? [],
        'topics': topicsByBook[bookId] ?? [],
        'pubPlaces': pubPlacesByBook[bookId] ?? [],
        'pubDates': pubDatesByBook[bookId] ?? [],
      };
    }).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM book WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT * FROM book WHERE categoryId = ? ORDER BY orderIndex, title',
        [categoryId]);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<Book?> getBookByTitle(String title) async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT * FROM book WHERE title = ? LIMIT 1', [title]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByAuthor(String authorName) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_author ba ON b.id = ba.bookId
      JOIN author a ON ba.authorId = a.id
      WHERE a.name LIKE ?
      ORDER BY b.orderIndex, b.title
    ''', ['%$authorName%']);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<int> insertBook(
      int categoryId,
      int sourceId,
      String title,
      String? heShortDesc,
      double orderIndex,
      int totalLines,
      bool isBaseBook,
      String? notesContent) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book (categoryId, sourceId, title, heShortDesc, orderIndex, totalLines, isBaseBook,notesContent)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      totalLines,
      (isBaseBook ? 1 : 0),
      notesContent
    ]);
  }

  Future<int> insertBookWithId(
      int id,
      int categoryId,
      int sourceId,
      String title,
      String? heShortDesc,
      double orderIndex,
      int totalLines,
      bool isBaseBook,
      String? notesContent) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book (id, categoryId, sourceId, title, heShortDesc, orderIndex, totalLines, isBaseBook,notesContent)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      categoryId,
      sourceId,
      title,
      heShortDesc,
      orderIndex,
      totalLines,
      (isBaseBook ? 1 : 0),
      notesContent
    ]);
  }

  Future<int> updateBookTotalLines(int id, int totalLines) async {
    final db = await database;
    return await db.rawUpdate(
        'UPDATE book SET totalLines = ? WHERE id = ?', [totalLines, id]);
  }

  Future<int> updateBookCategoryId(int id, int categoryId) async {
    final db = await database;
    return await db.rawUpdate(
        'UPDATE book SET categoryId = ? WHERE id = ?', [categoryId, id]);
  }

  Future<int> updateBookConnectionFlags(int id, bool hasTargum,
      bool hasReference, bool hasCommentary, bool hasOther) async {
    final db = await database;
    return await db.rawUpdate('''
      UPDATE book SET
          hasTargumConnection = ?,
          hasReferenceConnection = ?,
          hasCommentaryConnection = ?,
          hasOtherConnection = ?
      WHERE id = ?
    ''', [
      hasTargum ? 1 : 0,
      hasReference ? 1 : 0,
      hasCommentary ? 1 : 0,
      hasOther ? 1 : 0,
      id
    ]);
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book WHERE id = ?', [id]);
  }

  Future<int> countBooksByCategory(int categoryId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM book WHERE categoryId = ?', [categoryId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countAllBooks() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int?> getMaxBookId() async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(id) FROM book');
    return Sqflite.firstIntValue(result);
  }

  // Search functionality
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT * FROM book
      WHERE title LIKE ? OR heShortDesc LIKE ?
      ORDER BY orderIndex, title
    ''', ['%$query%', '%$query%']);
    return result.map((row) => Book.fromJson(row)).toList();
  }
}
