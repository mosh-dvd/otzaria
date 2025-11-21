import 'package:sqflite/sqflite.dart';
import 'database.dart';

// Simple model for connection type table entries
class ConnectionTypeEntry {
  final int id;
  final String name;

  const ConnectionTypeEntry({
    required this.id,
    required this.name,
  });

  factory ConnectionTypeEntry.fromMap(Map<String, dynamic> map) {
    return ConnectionTypeEntry(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class ConnectionTypeDao {
  final MyDatabase _db;

  ConnectionTypeDao(this._db);

  Future<Database> get database => _db.database;

  Future<List<ConnectionTypeEntry>> getAllConnectionTypes() async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM connection_type ORDER BY name');
    return result.map((row) => ConnectionTypeEntry.fromMap(row)).toList();
  }

  Future<ConnectionTypeEntry?> getConnectionTypeById(int id) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM connection_type WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return ConnectionTypeEntry.fromMap(result.first);
  }

  Future<ConnectionTypeEntry?> getConnectionTypeByName(String name) async {
    final db = await database;
    final result = await db.rawQuery('SELECT * FROM connection_type WHERE name = ?', [name]);
    if (result.isEmpty) return null;
    return ConnectionTypeEntry.fromMap(result.first);
  }

  Future<int> insertConnectionType(String name) async {
    final db = await database;
    return await db.rawInsert('INSERT INTO connection_type (name) VALUES (?)', [name]);
  }

  Future<int> insertConnectionTypeAndGetId(String name) async {
    final db = await database;
    await db.rawInsert('INSERT INTO connection_type (name) VALUES (?)', [name]);
    final result = await db.rawQuery('SELECT last_insert_rowid()');
    return result.first.values.first as int;
  }

  Future<int> updateConnectionType(int id, String name) async {
    final db = await database;
    return await db.rawUpdate('UPDATE connection_type SET name = ? WHERE id = ?', [name, id]);
  }

  Future<int> deleteConnectionType(int id) async {
    final db = await database;
    return await db.rawDelete('DELETE FROM connection_type WHERE id = ?', [id]);
  }
}
