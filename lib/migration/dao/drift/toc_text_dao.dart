import 'package:sqflite/sqflite.dart';
import '../../core/models/toc_text.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

class TocTextDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  TocTextDao(this._db) {
    _queries = QueryLoader.loadQueries('TocTextQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<List<TocText>> selectAll() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectAll']!);
    return result.map((row) => TocText.fromMap(row)).toList();
  }

  Future<TocText?> selectById(int id) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectById']!, [id]);
    if (result.isEmpty) return null;
    return TocText.fromMap(result.first);
  }

  Future<TocText?> selectByText(String text) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByText']!, [text]);
    if (result.isEmpty) return null;
    return TocText.fromMap(result.first);
  }

  Future<int> insert(TocText tocText) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!, [tocText.text]);
  }

  Future<int> insertAndGetId(TocText tocText) async {
    final db = await database;
    await db.rawInsert(_queries['insertAndGetId']!, [tocText.text]);
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }

  Future<int> selectIdByText(String text) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectIdByText']!, [text]);
    if (result.isEmpty) return 0;
    return result.first['id'] as int;
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [id]);
  }

  Future<int> countAll() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countAll']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getLastInsertRowId() async {
    final db = await database;
    final result = await db.rawQuery(_queries['lastInsertRowId']!);
    return result.first.values.first as int;
  }
}
