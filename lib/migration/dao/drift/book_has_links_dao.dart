import 'package:sqflite/sqflite.dart';
import '../../core/models/book.dart';
import 'database.dart';

// Simple model for book_has_links table entries
class BookHasLinksEntry {
  final int bookId;
  final bool hasSourceLinks;
  final bool hasTargetLinks;

  const BookHasLinksEntry({
    required this.bookId,
    required this.hasSourceLinks,
    required this.hasTargetLinks,
  });

  factory BookHasLinksEntry.fromMap(Map<String, dynamic> map) {
    return BookHasLinksEntry(
      bookId: map['bookId'] as int,
      hasSourceLinks: (map['hasSourceLinks'] as int) == 1,
      hasTargetLinks: (map['hasTargetLinks'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'hasSourceLinks': hasSourceLinks ? 1 : 0,
      'hasTargetLinks': hasTargetLinks ? 1 : 0,
    };
  }
}

class BookHasLinksDao {
  final MyDatabase _db;

  BookHasLinksDao(this._db);

  Future<Database> get database => _db.database;

  Future<BookHasLinksEntry?> getBookHasLinksByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT bookId, hasSourceLinks, hasTargetLinks FROM book_has_links WHERE bookId = ?', [bookId]);
    if (result.isEmpty) return null;
    return BookHasLinksEntry.fromMap(result.first);
  }

  Future<List<Book>> getBooksWithSourceLinks() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.*
      FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1
    ''');
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<List<Book>> getBooksWithTargetLinks() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.*
      FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasTargetLinks = 1
    ''');
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<List<Book>> getBooksWithAnyLinks() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT b.*
      FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1 OR bhl.hasTargetLinks = 1
    ''');
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<int> countBooksWithSourceLinks() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countBooksWithTargetLinks() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasTargetLinks = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countBooksWithAnyLinks() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1 OR hasTargetLinks = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> upsertBookHasLinks(int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      VALUES (?, ?, ?)
    ''', [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  Future<int> updateSourceLinks(int bookId, bool hasSourceLinks) async {
    final db = await database;
    return await db.rawUpdate('UPDATE book_has_links SET hasSourceLinks = ? WHERE bookId = ?', [hasSourceLinks ? 1 : 0, bookId]);
  }

  Future<int> updateTargetLinks(int bookId, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawUpdate('UPDATE book_has_links SET hasTargetLinks = ? WHERE bookId = ?', [hasTargetLinks ? 1 : 0, bookId]);
  }

  Future<int> updateBothLinkTypes(int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawUpdate('''
      UPDATE book_has_links
      SET hasSourceLinks = ?, hasTargetLinks = ?
      WHERE bookId = ?
    ''', [hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0, bookId]);
  }

  Future<int> insertBookHasLinks(int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks) VALUES (?, ?, ?)', [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  Future<int> deleteBookHasLinks(int bookId) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book_has_links WHERE bookId = ?', [bookId]);
  }
}
