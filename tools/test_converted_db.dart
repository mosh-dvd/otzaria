/// Quick test script for converted database
///
/// Usage:
///   dart run tools/test_converted_db.dart `<db_file>`
///
/// Example:
///   dart run tools/test_converted_db.dart output_books.db
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    debugPrint('Usage: dart run tools/test_converted_db.dart <db_file>');
    exit(1);
  }

  final dbPath = args[0];

  if (!await File(dbPath).exists()) {
    debugPrint('❌ Database file not found: $dbPath');
    exit(1);
  }

  debugPrint('🔍 Testing database: $dbPath\n');

  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open database
  final db = await openDatabase(dbPath, readOnly: true);

  try {
    // Test 1: Count books
    debugPrint('📚 Books:');
    final bookCount = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    debugPrint('   Total: ${bookCount.first['count']}');

    // Test 2: List first 10 books
    final books = await db.query('book', limit: 10);
    debugPrint('   First 10:');
    for (final book in books) {
      debugPrint('      - ${book['title']} (${book['totalLines']} lines)');
    }
    debugPrint('');

    // Test 3: Count lines
    debugPrint('📝 Lines:');
    final lineCount = await db.rawQuery('SELECT COUNT(*) as count FROM line');
    debugPrint('   Total: ${lineCount.first['count']}');
    debugPrint('');

    // Test 4: Count TOC entries
    debugPrint('📑 TOC Entries:');
    final tocCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    debugPrint('   Total: ${tocCount.first['count']}');
    debugPrint('');

    // Test 5: Count categories
    debugPrint('📂 Categories:');
    final catCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM category');
    debugPrint('   Total: ${catCount.first['count']}');

    final categories = await db.query('category');
    debugPrint('   List:');
    for (final cat in categories) {
      debugPrint('      - ${cat['title']}');
    }
    debugPrint('');

    // Test 6: Sample book content
    debugPrint('📖 Sample content (first book, first 5 lines):');
    final firstBook = await db.query('book', limit: 1);
    if (firstBook.isNotEmpty) {
      final bookId = firstBook.first['id'];
      final lines = await db.query(
        'line',
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'lineIndex',
        limit: 5,
      );

      for (final line in lines) {
        final content = line['content'] as String;
        final preview =
            content.length > 60 ? '${content.substring(0, 60)}...' : content;
        debugPrint('   ${line['lineIndex']}: $preview');
      }
    }
    debugPrint('');

    // Test 7: Database size
    final dbFile = File(dbPath);
    final size = await dbFile.length();
    debugPrint(
        '💾 Database size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    debugPrint('');

    debugPrint('✅ All tests passed!');
  } finally {
    await db.close();
  }
}
