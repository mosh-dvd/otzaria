import 'package:sqflite/sqflite.dart';
import '../../core/models/book.dart';
import 'database.dart';

class BookDao {
  final MyDatabase _db;

  BookDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM book ORDER BY orderIndex, title');
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM book WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Book.fromJson(result.first);
  }

  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM book WHERE categoryId = ? ORDER BY orderIndex, title', [categoryId]);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<Book?> getBookByTitle(String title) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM book WHERE title = ? LIMIT 1', [title]);
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

  Future<int> insertBook(int categoryId, int sourceId, String title, String? heShortDesc, double orderIndex, int totalLines,bool isBaseBook,String? notesContent) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book (categoryId, sourceId, title, heShortDesc, orderIndex, totalLines, isBaseBook,notesContent)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [categoryId, sourceId, title, heShortDesc, orderIndex, totalLines,(isBaseBook ? 1 : 0),notesContent]);
  }

  Future<int> insertBookWithId(int id, int categoryId, int sourceId, String title, String? heShortDesc, double orderIndex, int totalLines,bool isBaseBook,String? notesContent) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book (id, categoryId, sourceId, title, heShortDesc, orderIndex, totalLines, isBaseBook,notesContent)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [id, categoryId, sourceId, title, heShortDesc, orderIndex, totalLines,(isBaseBook ? 1 : 0),notesContent]);
  }

  Future<int> updateBookTotalLines(int id, int totalLines) async {
    final db = await database;
    return await db.rawUpdate('UPDATE book SET totalLines = ? WHERE id = ?', [totalLines, id]);
  }

  Future<int> updateBookCategoryId(int id, int categoryId) async {
    final db = await database;
    return await db.rawUpdate('UPDATE book SET categoryId = ? WHERE id = ?', [categoryId, id]);
  }

  Future<int> updateBookConnectionFlags(int id, bool hasTargum, bool hasReference, bool hasCommentary, bool hasOther) async {
    final db = await database;
    return await db.rawUpdate('''
      UPDATE book SET
          hasTargumConnection = ?,
          hasReferenceConnection = ?,
          hasCommentaryConnection = ?,
          hasOtherConnection = ?
      WHERE id = ?
    ''', [hasTargum ? 1 : 0, hasReference ? 1 : 0, hasCommentary ? 1 : 0, hasOther ? 1 : 0, id]);
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book WHERE id = ?', [id]);
  }

  Future<int> countBooksByCategory(int categoryId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book WHERE categoryId = ?', [categoryId]);
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
