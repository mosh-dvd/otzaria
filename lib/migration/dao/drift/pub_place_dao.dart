import 'package:sqflite/sqflite.dart';
import '../../core/models/pub_place.dart';
import 'database.dart';

class PubPlaceDao {
  final MyDatabase _db;

  PubPlaceDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<PubPlace>> getAllPubPlaces() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_place ORDER BY name');
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  Future<PubPlace?> getPubPlaceById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_place WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<PubPlace?> getPubPlaceByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM pub_place WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) return null;
    return PubPlace.fromJson(result.first);
  }

  Future<List<PubPlace>> getPubPlacesByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.* FROM pub_place p
      JOIN book_pub_place bp ON p.id = bp.pubPlaceId
      WHERE bp.bookId = ?
    ''', [bookId]);
    return result.map((row) => PubPlace.fromJson(row)).toList();
  }

  Future<int> insertPubPlace(String name) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO pub_place (name) VALUES (?) ON CONFLICT (name) DO NOTHING', [name]);
  }

  Future<int> insertPubPlaceAndGetId(String name) async {
    final db = await database;
    await db.rawInsert('INSERT INTO pub_place (name) VALUES (?) ON CONFLICT (name) DO NOTHING', [name]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int> linkBookPubPlace(int bookId, int pubPlaceId) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book_pub_place (bookId, pubPlaceId)
      VALUES (?, ?)
      ON CONFLICT (bookId, pubPlaceId) DO NOTHING
    ''', [bookId, pubPlaceId]);
  }

  Future<int> deletePubPlace(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM pub_place WHERE id = ?', [id]);
  }

  Future<int> countAllPubPlaces() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM pub_place');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
