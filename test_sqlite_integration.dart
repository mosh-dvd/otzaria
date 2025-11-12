/// Test script for SQLite integration
///
/// Run this script to verify that the SQLite integration is working correctly.
///
/// Usage:
///   dart run test_sqlite_integration.dart
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  debugPrint('🔍 Testing SQLite Integration...\n');

  // Initialize FFI for desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Step 1: Check if database file exists
  debugPrint('Step 1: Checking for database file...');
  final dbFile = File('seforim.db');
  if (!await dbFile.exists()) {
    debugPrint('❌ ERROR: seforim.db not found in project root!');
    debugPrint('   Please copy seforim.db to the project root directory.');
    exit(1);
  }
  debugPrint('✅ Database file found: ${dbFile.path}');
  debugPrint(
      '   Size: ${(await dbFile.length() / 1024 / 1024).toStringAsFixed(2)} MB\n');

  // Step 2: Try to open the database
  debugPrint('Step 2: Opening database...');
  Database? db;
  try {
    // Use absolute path for FFI
    final absolutePath = dbFile.absolute.path;
    db = await openDatabase(
      absolutePath,
      readOnly: true,
      singleInstance: false,
    );
    debugPrint('✅ Database opened successfully');
    debugPrint('   Path: $absolutePath\n');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to open database: $e');
    exit(1);
  }

  // Step 3: Check tables
  debugPrint('Step 3: Checking database structure...');
  try {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    debugPrint('✅ Found ${tables.length} tables:');
    for (final table in tables) {
      debugPrint('   - ${table['name']}');
    }
    debugPrint('');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to read tables: $e');
    await db.close();
    exit(1);
  }

  // Step 4: Count books
  debugPrint('Step 4: Counting books...');
  try {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    final count = result.first['count'] as int;
    debugPrint('✅ Found $count books in database\n');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to count books: $e');
    await db.close();
    exit(1);
  }

  // Step 5: List first 10 books
  debugPrint('Step 5: Listing first 10 books...');
  try {
    final books = await db.query(
      'book',
      columns: ['id', 'title', 'totalLines'],
      orderBy: 'orderIndex ASC, title ASC',
      limit: 10,
    );
    debugPrint('✅ First 10 books:');
    for (final book in books) {
      debugPrint(
          '   ${book['id']}. ${book['title']} (${book['totalLines']} lines)');
    }
    debugPrint('');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to list books: $e');
    await db.close();
    exit(1);
  }

  // Step 6: Test reading a book's lines
  debugPrint('Step 6: Testing book content reading...');
  try {
    // Get first book
    final books = await db.query('book', limit: 1);
    if (books.isEmpty) {
      debugPrint('⚠️  WARNING: No books found in database');
    } else {
      final bookId = books.first['id'] as int;
      final bookTitle = books.first['title'] as String;

      // Get lines
      final lines = await db.query(
        'line',
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'lineIndex ASC',
        limit: 5,
      );

      debugPrint(
          '✅ Successfully read ${lines.length} lines from "$bookTitle":');
      for (int i = 0; i < lines.length && i < 3; i++) {
        final content = lines[i]['content'] as String;
        final preview =
            content.length > 60 ? '${content.substring(0, 60)}...' : content;
        debugPrint('   Line ${i + 1}: $preview');
      }
      debugPrint('');
    }
  } catch (e) {
    debugPrint('❌ ERROR: Failed to read book content: $e');
    await db.close();
    exit(1);
  }

  // Step 7: Test TOC
  debugPrint('Step 7: Testing table of contents...');
  try {
    final tocCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    final count = tocCount.first['count'] as int;
    debugPrint('✅ Found $count TOC entries in database\n');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to read TOC: $e');
    await db.close();
    exit(1);
  }

  // Step 8: Test links
  debugPrint('Step 8: Testing links (commentaries)...');
  try {
    final linksCount = await db.rawQuery('SELECT COUNT(*) as count FROM link');
    final count = linksCount.first['count'] as int;
    debugPrint('✅ Found $count links in database\n');
  } catch (e) {
    debugPrint('❌ ERROR: Failed to read links: $e');
    await db.close();
    exit(1);
  }

  // Close database
  await db.close();

  // Final summary
  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('🎉 All tests passed successfully!');
  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('');
  debugPrint('Next steps:');
  debugPrint('1. Run the app: flutter run');
  debugPrint('2. Open a book and check the logs');
  debugPrint('3. You should see: "Loaded book from SQLite"');
  debugPrint('');
  debugPrint('The integration is ready to use! 🚀');
}
