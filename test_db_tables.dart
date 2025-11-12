import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open database with absolute path
  final dbPath = 'C:\\Users\\userbot\\Documents\\otzaria\\seforim.db';
  debugPrint('📂 Opening: $dbPath\n');

  final db = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  debugPrint('🔍 Checking tables in seforim.db...\n');

  // Get all tables
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");

  debugPrint('📊 Found ${tables.length} tables:\n');
  for (final table in tables) {
    final tableName = table['name'] as String;
    debugPrint('  ✅ $tableName');

    // Count rows in each table
    try {
      final count =
          await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      final rowCount = count.first['count'];
      debugPrint('     └─ $rowCount rows');
    } catch (e) {
      debugPrint('     └─ Error counting: $e');
    }
  }

  debugPrint('\n🔍 Checking specific tables...\n');

  // Check tocEntry
  try {
    final tocCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    debugPrint('✅ tocEntry exists: ${tocCount.first['count']} entries');
  } catch (e) {
    debugPrint('❌ tocEntry: $e');
  }

  // Check link
  try {
    final linkCount = await db.rawQuery('SELECT COUNT(*) as count FROM link');
    debugPrint('✅ link exists: ${linkCount.first['count']} links');
  } catch (e) {
    debugPrint('❌ link: $e');
  }

  // Check book
  try {
    final bookCount = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    debugPrint('✅ book exists: ${bookCount.first['count']} books');
  } catch (e) {
    debugPrint('❌ book: $e');
  }

  // Check line
  try {
    final lineCount = await db.rawQuery('SELECT COUNT(*) as count FROM line');
    debugPrint('✅ line exists: ${lineCount.first['count']} lines');
  } catch (e) {
    debugPrint('❌ line: $e');
  }

  await db.close();
  debugPrint('\n✅ Done!');
}
