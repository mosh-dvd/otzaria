import 'package:sqflite/sqflite.dart';
import '../../core/models/author.dart';
import 'database.dart';

class AuthorDao {
  final MyDatabase _db;

  AuthorDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<Author>> getAllAuthors() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM author ORDER BY name');
    return result.map((row) => Author.fromMap(row)).toList();
  }

  Future<Author?> getAuthorById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM author WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<Author?> getAuthorByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM author WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) return null;
    return Author.fromMap(result.first);
  }

  Future<List<Author>> getAuthorsByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT a.* FROM author a
      JOIN book_author ba ON a.id = ba.authorId
      WHERE ba.bookId = ?
      ORDER BY a.name
    ''', [bookId]);
    return result.map((row) => Author.fromMap(row)).toList();
  }

  Future<int> insertAuthor(String name) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO author (name) VALUES (?) ON CONFLICT (name) DO NOTHING', [name]);
  }

  Future<int> insertAuthorAndGetId(String name) async {
    final db = await database;
    await db.rawInsert('INSERT OR IGNORE INTO author (name) VALUES (?)', [name]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int?> getAuthorIdByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT id FROM author WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  Future<int> deleteAuthor(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM author WHERE id = ?', [id]);
  }

  Future<int> countAllAuthors() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM author');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Junction table operations
  Future<int> linkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book_author (bookId, authorId)
      VALUES (?, ?)
      ON CONFLICT (bookId, authorId) DO NOTHING
    ''', [bookId, authorId]);
  }

  Future<int> unlinkBookAuthor(int bookId, int authorId) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book_author WHERE bookId = ? AND authorId = ?', [bookId, authorId]);
  }

  Future<int> deleteAllBookAuthors(int bookId) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book_author WHERE bookId = ?', [bookId]);
  }

  Future<int> countBookAuthors(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_author WHERE bookId = ?', [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
