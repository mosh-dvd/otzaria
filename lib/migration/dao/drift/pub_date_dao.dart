import 'package:sqflite/sqflite.dart';
import '../../core/models/pub_date.dart';
import 'database.dart';

class PubDateDao {
  final MyDatabase _db;

  PubDateDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<PubDate>> getAllPubDates() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_date ORDER BY date');
    return result.map((row) => PubDate.fromJson(row)).toList();
  }

  Future<PubDate?> getPubDateById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_date WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<PubDate?> getPubDateByDate(String date) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_date WHERE date = ? LIMIT 1', [date]);
    if (result.isEmpty) return null;
    return PubDate.fromJson(result.first);
  }

  Future<List<PubDate>> getPubDatesByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.* FROM pub_date p
      JOIN book_pub_date bp ON p.id = bp.pubDateId
      WHERE bp.bookId = ?
    ''', [bookId]);
    return result.map((row) => PubDate.fromJson(row)).toList();
  }

  Future<int> insertPubDate(String date) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO pub_date (date) VALUES (?) ON CONFLICT (date) DO NOTHING', [date]);
  }

  Future<int> insertPubDateAndGetId(String date) async {
    final db = await database;
    await db.rawInsert('INSERT INTO pub_date (date) VALUES (?) ON CONFLICT (date) DO NOTHING', [date]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int> linkBookPubDate(int bookId, int pubDateId) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book_pub_date (bookId, pubDateId)
      VALUES (?, ?)
      ON CONFLICT (bookId, pubDateId) DO NOTHING
    ''', [bookId, pubDateId]);
  }

  Future<int> deletePubDate(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM pub_date WHERE id = ?', [id]);
  }

  Future<int> countAllPubDates() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM pub_date');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
