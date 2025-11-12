/// Merge my_books.db into seforim.db with proper ID offsets
///
/// Usage:
///   dart run tools/merge_databases.dart
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  debugPrint('🔄 Database Merger');
  debugPrint('═══════════════════════════════════════\n');

  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Check files exist
  if (!await File('seforim.db').exists()) {
    debugPrint('❌ seforim.db not found!');
    exit(1);
  }

  if (!await File('my_books.db').exists()) {
    debugPrint('❌ my_books.db not found!');
    exit(1);
  }

  // Backup seforim.db
  debugPrint('💾 Creating backup...');
  await File('seforim.db')
      .copy('seforim.db.backup.${DateTime.now().millisecondsSinceEpoch}');
  debugPrint('✅ Backup created\n');

  // Open main database
  debugPrint('📂 Opening seforim.db...');
  final db = await openDatabase('seforim.db');

  try {
    // Attach personal database
    debugPrint('📎 Attaching my_books.db...');
    await db.execute("ATTACH DATABASE 'my_books.db' AS personal");

    // Get current max IDs
    debugPrint('\n📊 Current state:');
    final maxBookId = (await db.rawQuery('SELECT MAX(id) as max FROM book'))
            .first['max'] as int? ??
        0;
    final maxLineId = (await db.rawQuery('SELECT MAX(id) as max FROM line'))
            .first['max'] as int? ??
        0;
    final maxTocEntryId =
        (await db.rawQuery('SELECT MAX(id) as max FROM tocEntry')).first['max']
                as int? ??
            0;
    final maxTocTextId =
        (await db.rawQuery('SELECT MAX(id) as max FROM tocText')).first['max']
                as int? ??
            0;
    final maxCategoryId =
        (await db.rawQuery('SELECT MAX(id) as max FROM category')).first['max']
                as int? ??
            0;

    debugPrint('   Max book ID: $maxBookId');
    debugPrint('   Max line ID: $maxLineId');
    debugPrint('   Max TOC entry ID: $maxTocEntryId');
    debugPrint('   Max TOC text ID: $maxTocTextId');
    debugPrint('   Max category ID: $maxCategoryId');

    // Count books in personal DB
    final personalBookCount =
        (await db.rawQuery('SELECT COUNT(*) as count FROM personal.book'))
            .first['count'] as int;
    debugPrint('\n📚 Books in my_books.db: $personalBookCount');

    if (personalBookCount == 0) {
      debugPrint('⚠️  No books to merge!');
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

    debugPrint('\n🔢 Using offsets:');
    debugPrint('   Category: +$categoryOffset');
    debugPrint('   Book: +$bookOffset');
    debugPrint('   Line: +$lineOffset');
    debugPrint('   TOC Entry: +$tocEntryOffset');
    debugPrint('   TOC Text: +$tocTextOffset');

    // Start transaction
    debugPrint('\n🔄 Starting merge...');
    await db.execute('BEGIN TRANSACTION');

    try {
      // 1. Copy categories
      debugPrint('   📂 Copying categories...');
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
      debugPrint('   📚 Copying books...');
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
      debugPrint('   📑 Copying TOC texts...');
      await db.execute('''
        INSERT OR IGNORE INTO tocText (id, text)
        SELECT 
          id + $tocTextOffset,
          text
        FROM personal.tocText
      ''');

      // 4. Copy lines
      debugPrint('   📝 Copying lines...');
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
      debugPrint('   📖 Copying TOC entries...');
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
      debugPrint('   ✅ Transaction committed');
    } catch (e) {
      await db.execute('ROLLBACK');
      debugPrint('   ❌ Error during merge: $e');
      debugPrint('   🔙 Transaction rolled back');
      rethrow;
    }

    // Verify
    debugPrint('\n📊 After merge:');
    final totalBooks = (await db.rawQuery('SELECT COUNT(*) as count FROM book'))
        .first['count'];
    final totalLines = (await db.rawQuery('SELECT COUNT(*) as count FROM line'))
        .first['count'];
    final totalTocEntries =
        (await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry'))
            .first['count'];

    debugPrint('   Total books: $totalBooks');
    debugPrint('   Total lines: $totalLines');
    debugPrint('   Total TOC entries: $totalTocEntries');

    // Detach
    await db.execute('DETACH DATABASE personal');

    debugPrint('\n═══════════════════════════════════════');
    debugPrint('✅ Merge completed successfully!');
    debugPrint('═══════════════════════════════════════');
    debugPrint('\nYour personal books are now in seforim.db');
    debugPrint('You can delete my_books.db if you want.');
    debugPrint('\nBackup saved as: seforim.db.backup.*');
  } finally {
    await db.close();
  }
}
