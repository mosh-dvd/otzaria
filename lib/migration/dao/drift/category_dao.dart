import 'package:sqflite/sqflite.dart';
import '../../core/models/category.dart';
import 'database.dart';

class CategoryDao {
  final MyDatabase _db;

  CategoryDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM category ORDER BY title');
    return result.map((row) => Category.fromJson(row)).toList();
  }

  Future<Category?> getCategoryById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM category WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  Future<List<Category>> getRootCategories() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM category WHERE parentId IS NULL ORDER BY title');
    return result.map((row) => Category.fromJson(row)).toList();
  }

  Future<List<Category>> getCategoriesByParentId(int parentId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM category WHERE parentId = ? ORDER BY title', [parentId]);
    return result.map((row) => Category.fromJson(row)).toList();
  }

  Future<int> insertCategory(int? parentId, String title, int level) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO category (parentId, title, level) VALUES (?, ?, ?)', [parentId, title, level]);
  }

  Future<int> insertCategoryAndGetId(int? parentId, String title, int level) async {
    final db = await database;
    await db.rawInsert('INSERT INTO category (parentId, title, level) VALUES (?, ?, ?)', [parentId, title, level]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int> updateCategory(int id, String title) async {
    final db = await database;
    return await db.rawUpdate('UPDATE category SET title = ? WHERE id = ?', [title, id]);
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM category WHERE id = ?', [id]);
  }

  Future<int> countAllCategories() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM category');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
