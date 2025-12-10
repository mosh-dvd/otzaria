import 'package:sqflite/sqflite.dart';
import '../../core/models/topic.dart';
import 'database.dart';

class TopicDao {
  final MyDatabase _db;

  TopicDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<Topic>> getAllTopics() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM topic ORDER BY name');
    return result.map((row) => Topic.fromJson(row)).toList();
  }

  Future<Topic?> getTopicById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM topic WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Topic.fromJson(result.first);
  }

  Future<Topic?> getTopicByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM topic WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) return null;
    return Topic.fromJson(result.first);
  }

  Future<List<Topic>> getTopicsByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT t.* FROM topic t
      JOIN book_topic bt ON t.id = bt.topicId
      WHERE bt.bookId = ?
      ORDER BY t.name
    ''', [bookId]);
    return result.map((row) => Topic.fromJson(row)).toList();
  }

  Future<int> insertTopic(String name) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO topic (name) VALUES (?) ON CONFLICT (name) DO NOTHING', [name]);
  }

  Future<int> insertTopicAndGetId(String name) async {
    final db = await database;
    await db.rawInsert('INSERT OR IGNORE INTO topic (name) VALUES (?)', [name]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int?> getTopicIdByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT id FROM topic WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) return null;
    return result.first['id'] as int;
  }

  Future<int> deleteTopic(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM topic WHERE id = ?', [id]);
  }

  Future<int> countAllTopics() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM topic');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Junction table operations
  Future<int> linkBookTopic(int bookId, int topicId) async {
    final db = await database;
    return await db.rawInsert('''
      INSERT INTO book_topic (bookId, topicId)
      VALUES (?, ?)
      ON CONFLICT (bookId, topicId) DO NOTHING
    ''', [bookId, topicId]);
  }

  Future<int> unlinkBookTopic(int bookId, int topicId) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book_topic WHERE bookId = ? AND topicId = ?', [bookId, topicId]);
  }

  Future<int> deleteAllBookTopics(int bookId) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM book_topic WHERE bookId = ?', [bookId]);
  }

  Future<int> countBookTopics(int bookId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_topic WHERE bookId = ?', [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
