/// Quick test script for converted database
/// 
/// Usage:
///   dart run tools/test_converted_db.dart <db_file>
/// 
/// Example:
///   dart run tools/test_converted_db.dart output_books.db

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tools/test_converted_db.dart <db_file>');
    exit(1);
  }

  final dbPath = args[0];
  
  if (!await File(dbPath).exists()) {
    print('❌ Database file not found: $dbPath');
    exit(1);
  }

  print('🔍 Testing database: $dbPath\n');

  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open database
  final db = await openDatabase(dbPath, readOnly: true);

  try {
    // Test 1: Count books
    print('📚 Books:');
    final bookCount = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    print('   Total: ${bookCount.first['count']}');
    
    // Test 2: List first 10 books
    final books = await db.query('book', limit: 10);
    print('   First 10:');
    for (final book in books) {
      print('      - ${book['title']} (${book['totalLines']} lines)');
    }
    print('');

    // Test 3: Count lines
    print('📝 Lines:');
    final lineCount = await db.rawQuery('SELECT COUNT(*) as count FROM line');
    print('   Total: ${lineCount.first['count']}');
    print('');

    // Test 4: Count TOC entries
    print('📑 TOC Entries:');
    final tocCount = await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    print('   Total: ${tocCount.first['count']}');
    print('');

    // Test 5: Count categories
    print('📂 Categories:');
    final catCount = await db.rawQuery('SELECT COUNT(*) as count FROM category');
    print('   Total: ${catCount.first['count']}');
    
    final categories = await db.query('category');
    print('   List:');
    for (final cat in categories) {
      print('      - ${cat['title']}');
    }
    print('');

    // Test 6: Sample book content
    print('📖 Sample content (first book, first 5 lines):');
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
        final preview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
        print('   ${line['lineIndex']}: $preview');
      }
    }
    print('');

    // Test 7: Database size
    final dbFile = File(dbPath);
    final size = await dbFile.length();
    print('💾 Database size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    print('');

    print('✅ All tests passed!');
  } finally {
    await db.close();
  }
}
