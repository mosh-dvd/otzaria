/// Merge my_books.db into seforim.db with proper ID offsets
/// 
/// Usage:
///   dart run tools/merge_databases.dart

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('🔄 Database Merger');
  print('═══════════════════════════════════════\n');

  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Check files exist
  if (!await File('seforim.db').exists()) {
    print('❌ seforim.db not found!');
    exit(1);
  }

  if (!await File('my_books.db').exists()) {
    print('❌ my_books.db not found!');
    exit(1);
  }

  // Backup seforim.db
  print('💾 Creating backup...');
  await File('seforim.db').copy('seforim.db.backup.${DateTime.now().millisecondsSinceEpoch}');
  print('✅ Backup created\n');

  // Open main database
  print('📂 Opening seforim.db...');
  final db = await openDatabase('seforim.db');

  try {
    // Attach personal database
    print('📎 Attaching my_books.db...');
    await db.execute("ATTACH DATABASE 'my_books.db' AS personal");

    // Get current max IDs
    print('\n📊 Current state:');
    final maxBookId = (await db.rawQuery('SELECT MAX(id) as max FROM book')).first['max'] as int? ?? 0;
    final maxLineId = (await db.rawQuery('SELECT MAX(id) as max FROM line')).first['max'] as int? ?? 0;
    final maxTocEntryId = (await db.rawQuery('SELECT MAX(id) as max FROM tocEntry')).first['max'] as int? ?? 0;
    final maxTocTextId = (await db.rawQuery('SELECT MAX(id) as max FROM tocText')).first['max'] as int? ?? 0;
    final maxCategoryId = (await db.rawQuery('SELECT MAX(id) as max FROM category')).first['max'] as int? ?? 0;

    print('   Max book ID: $maxBookId');
    print('   Max line ID: $maxLineId');
    print('   Max TOC entry ID: $maxTocEntryId');
    print('   Max TOC text ID: $maxTocTextId');
    print('   Max category ID: $maxCategoryId');

    // Count books in personal DB
    final personalBookCount = (await db.rawQuery('SELECT COUNT(*) as count FROM personal.book')).first['count'] as int;
    print('\n📚 Books in my_books.db: $personalBookCount');

    if (personalBookCount == 0) {
      print('⚠️  No books to merge!');
      await db.execute('DETACH DATABASE personal');
      await db.close();
      return;
    }

    // Calculate offsets (use safe large offsets)
    final categoryOffset = 10000;
    final bookOffset = maxBookId + 1000;
    final lineOffset = maxLineId + 10000;
    final tocEntryOffset = maxTocEntryId + 1000;
    final tocTextOffset = maxTocTextId + 1000;

    print('\n🔢 Using offsets:');
    print('   Category: +$categoryOffset');
    print('   Book: +$bookOffset');
    print('   Line: +$lineOffset');
    print('   TOC Entry: +$tocEntryOffset');
    print('   TOC Text: +$tocTextOffset');

    // Start transaction
    print('\n🔄 Starting merge...');
    await db.execute('BEGIN TRANSACTION');

    try {
      // 1. Copy categories
      print('   📂 Copying categories...');
      await db.execute('''
        INSERT OR IGNORE INTO category (id, parentId, title, level)
        SELECT 
          id + $categoryOffset,
          CASE WHEN parentId IS NOT NULL THEN parentId + $categoryOffset ELSE NULL END,
          title,
          level
        FROM personal.category
      ''');

      // 2. Copy books
      print('   📚 Copying books...');
      await db.execute('''
        INSERT INTO book (
          id, categoryId, sourceId, title, heShortDesc, notesContent,
          orderIndex, totalLines, isBaseBook, hasTargumConnection,
          hasReferenceConnection, hasCommentaryConnection, hasOtherConnection
        )
        SELECT 
          id + $bookOffset,
          categoryId + $categoryOffset,
          sourceId,
          title,
          heShortDesc,
          notesContent,
          orderIndex,
          totalLines,
          isBaseBook,
          hasTargumConnection,
          hasReferenceConnection,
          hasCommentaryConnection,
          hasOtherConnection
        FROM personal.book
      ''');

      // 3. Copy TOC texts
      print('   📑 Copying TOC texts...');
      await db.execute('''
        INSERT OR IGNORE INTO tocText (id, text)
        SELECT 
          id + $tocTextOffset,
          text
        FROM personal.tocText
      ''');

      // 4. Copy lines
      print('   📝 Copying lines...');
      await db.execute('''
        INSERT INTO line (id, bookId, lineIndex, content, tocEntryId)
        SELECT 
          id + $lineOffset,
          bookId + $bookOffset,
          lineIndex,
          content,
          CASE WHEN tocEntryId IS NOT NULL THEN tocEntryId + $tocEntryOffset ELSE NULL END
        FROM personal.line
      ''');

      // 5. Copy TOC entries
      print('   📖 Copying TOC entries...');
      await db.execute('''
        INSERT INTO tocEntry (
          id, bookId, parentId, textId, level, lineId,
          isLastChild, hasChildren
        )
        SELECT 
          id + $tocEntryOffset,
          bookId + $bookOffset,
          CASE WHEN parentId IS NOT NULL THEN parentId + $tocEntryOffset ELSE NULL END,
          textId + $tocTextOffset,
          level,
          CASE WHEN lineId IS NOT NULL THEN lineId + $lineOffset ELSE NULL END,
          isLastChild,
          hasChildren
        FROM personal.tocEntry
      ''');

      // Commit transaction
      await db.execute('COMMIT');
      print('   ✅ Transaction committed');

    } catch (e) {
      await db.execute('ROLLBACK');
      print('   ❌ Error during merge: $e');
      print('   🔙 Transaction rolled back');
      rethrow;
    }

    // Verify
    print('\n📊 After merge:');
    final totalBooks = (await db.rawQuery('SELECT COUNT(*) as count FROM book')).first['count'];
    final totalLines = (await db.rawQuery('SELECT COUNT(*) as count FROM line')).first['count'];
    final totalTocEntries = (await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry')).first['count'];

    print('   Total books: $totalBooks');
    print('   Total lines: $totalLines');
    print('   Total TOC entries: $totalTocEntries');

    // Detach
    await db.execute('DETACH DATABASE personal');

    print('\n═══════════════════════════════════════');
    print('✅ Merge completed successfully!');
    print('═══════════════════════════════════════');
    print('\nYour personal books are now in seforim.db');
    print('You can delete my_books.db if you want.');
    print('\nBackup saved as: seforim.db.backup.*');

  } finally {
    await db.close();
  }
}
