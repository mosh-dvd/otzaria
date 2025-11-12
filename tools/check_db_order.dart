/// Quick script to check orderIndex values in the database
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('🔍 Checking database orderIndex values...\n');

  // Initialize SQLite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Find the database
  final dbPath = await _findDatabase();
  if (dbPath == null) {
    print('❌ Database not found!');
    exit(1);
  }

  print('📂 Database: $dbPath\n');

  // Open database
  final db = await openDatabase(dbPath, readOnly: true);

  try {
    // Check schema
    print('📋 Category table schema:');
    print('=' * 60);
    final categorySchema = await db.rawQuery('PRAGMA table_info(category)');
    for (final col in categorySchema) {
      print('${col['name']?.toString().padRight(20)} | ${col['type']}');
    }

    print('\n📋 Book table schema:');
    print('=' * 60);
    final bookSchema = await db.rawQuery('PRAGMA table_info(book)');
    for (final col in bookSchema) {
      print('${col['name']?.toString().padRight(20)} | ${col['type']}');
    }

    print('\n📊 Top-level categories (level 0):');
    print('=' * 60);
    final categories = await db.query(
      'category',
      where: 'parentId IS NULL',
      orderBy: 'title ASC',
    );

    for (final cat in categories) {
      print('${cat['title']}');
    }

    print('\n✅ Check complete!');
  } finally {
    await db.close();
  }
}

Future<String?> _findDatabase() async {
  // Try common locations
  final locations = [
    'C:\\אוצריא\\seforim.db',
    'seforim.db',
    '.dart_tool\\sqflite_common_ffi\\databases\\seforim.db',
  ];

  for (final path in locations) {
    if (await File(path).exists()) {
      return path;
    }
  }

  return null;
}
