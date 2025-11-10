import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open database with absolute path
  final dbPath = 'C:\\Users\\userbot\\Documents\\otzaria\\seforim.db';
  print('📂 Opening: $dbPath\n');
  
  final db = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  print('🔍 Checking tables in seforim.db...\n');

  // Get all tables
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
  );

  print('📊 Found ${tables.length} tables:\n');
  for (final table in tables) {
    final tableName = table['name'] as String;
    print('  ✅ $tableName');
    
    // Count rows in each table
    try {
      final count = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      final rowCount = count.first['count'];
      print('     └─ $rowCount rows');
    } catch (e) {
      print('     └─ Error counting: $e');
    }
  }

  print('\n🔍 Checking specific tables...\n');

  // Check tocEntry
  try {
    final tocCount = await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    print('✅ tocEntry exists: ${tocCount.first['count']} entries');
  } catch (e) {
    print('❌ tocEntry: $e');
  }

  // Check link
  try {
    final linkCount = await db.rawQuery('SELECT COUNT(*) as count FROM link');
    print('✅ link exists: ${linkCount.first['count']} links');
  } catch (e) {
    print('❌ link: $e');
  }

  // Check book
  try {
    final bookCount = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    print('✅ book exists: ${bookCount.first['count']} books');
  } catch (e) {
    print('❌ book: $e');
  }

  // Check line
  try {
    final lineCount = await db.rawQuery('SELECT COUNT(*) as count FROM line');
    print('✅ line exists: ${lineCount.first['count']} lines');
  } catch (e) {
    print('❌ line: $e');
  }

  await db.close();
  print('\n✅ Done!');
}
