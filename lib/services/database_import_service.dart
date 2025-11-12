import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

class DatabaseImportService {
  static bool _isCancelled = false;
  static const String _importedCategoriesKey = 'key-imported-categories';

  /// Cancel the current import operation
  static void cancelImport() {
    _isCancelled = true;
  }

  /// Reset cancellation flag
  static void resetCancellation() {
    _isCancelled = false;
  }

  /// Get list of user-imported categories
  static List<String> getImportedCategories() {
    final jsonString = Settings.getValue<String>(_importedCategoriesKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.cast<String>();
    } catch (e) {
      debugPrint('⚠️ Failed to decode imported categories: $e');
      return [];
    }
  }

  /// Add a category to the imported categories list
  static Future<void> addImportedCategory(String categoryTitle) async {
    final categories = getImportedCategories();
    if (!categories.contains(categoryTitle)) {
      categories.add(categoryTitle);
      await Settings.setValue(_importedCategoriesKey, json.encode(categories));
      debugPrint('✅ Added "$categoryTitle" to imported categories list');
    }
  }

  /// Remove a category from the imported categories list
  static Future<void> removeImportedCategory(String categoryTitle) async {
    final categories = getImportedCategories();
    categories.remove(categoryTitle);
    await Settings.setValue(_importedCategoriesKey, json.encode(categories));
    debugPrint('✅ Removed "$categoryTitle" from imported categories list');
  }

  /// Remove a category and all its books from the database
  static Future<void> removeCategoryFromDatabase(
    String dbPath,
    String categoryTitle,
    void Function(String status)? onProgress,
  ) async {
    debugPrint('🗑️ Starting category removal...');
    debugPrint('📂 Database: $dbPath');
    debugPrint('📁 Category: $categoryTitle');

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('קובץ מאגר הנתונים לא קיים: $dbPath');
    }

    Database? db;
    try {
      onProgress?.call('פותח מאגר נתונים...');
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          readOnly: false,
          singleInstance: false,
        ),
      );
      debugPrint('✅ Database opened');

      // Find the category ID
      onProgress?.call('מחפש קטגוריה...');
      final categoryResult = await db.rawQuery(
        'SELECT id FROM category WHERE title = ?',
        [categoryTitle],
      );

      if (categoryResult.isEmpty) {
        throw Exception('הקטגוריה "$categoryTitle" לא נמצאה במאגר');
      }

      final categoryId = categoryResult.first['id'] as int;
      debugPrint('📁 Found category ID: $categoryId');

      // Count books in this category
      final bookCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM book WHERE categoryId = ?',
        [categoryId],
      );
      final bookCount = bookCountResult.first['count'] as int;
      debugPrint('📚 Found $bookCount books in category');

      onProgress?.call('מוחק $bookCount ספרים...');

      // Use proper transaction API for atomic operations
      await db.transaction((txn) async {
        // Get all book IDs in this category
        final bookIdsResult = await txn.query(
          'book',
          columns: ['id'],
          where: 'categoryId = ?',
          whereArgs: [categoryId],
        );
        final bookIds = bookIdsResult.map((row) => row['id'] as int).toList();
        debugPrint('📚 Book IDs to delete: $bookIds');

        if (bookIds.isNotEmpty) {
          // Delete lines for these books
          onProgress?.call('מוחק שורות טקסט...');
          for (final bookId in bookIds) {
            await txn.delete('line', where: 'bookId = ?', whereArgs: [bookId]);
          }
          debugPrint('✅ Lines deleted');

          // Delete TOC entries for these books
          onProgress?.call('מוחק תוכן עניינים...');
          for (final bookId in bookIds) {
            await txn
                .delete('tocEntry', where: 'bookId = ?', whereArgs: [bookId]);
          }
          debugPrint('✅ TOC entries deleted');

          // Delete books
          onProgress?.call('מוחק ספרים...');
          await txn
              .delete('book', where: 'categoryId = ?', whereArgs: [categoryId]);
          debugPrint('✅ Books deleted');
        }

        // Delete the category itself
        onProgress?.call('מוחק קטגוריה...');
        await txn.delete('category', where: 'id = ?', whereArgs: [categoryId]);
        debugPrint('✅ Category deleted');
      });

      debugPrint('✅ Transaction committed successfully');

      // Remove from imported categories list
      await removeImportedCategory(categoryTitle);

      onProgress?.call('הקטגוריה "$categoryTitle" נמחקה בהצלחה!');
    } catch (e) {
      debugPrint('❌ Fatal error: $e');
      rethrow;
    } finally {
      if (db != null) {
        await db.close();
        debugPrint('✅ Database closed');
      }
    }
  }

  /// Get the CREATE TABLE statement for a table
  static Future<String> getTableSchema(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    if (result.isEmpty) {
      throw Exception('Table $tableName not found');
    }
    return result.first['sql'] as String;
  }

  /// Convert books from a folder to a temporary database
  static Future<String> convertBooksToDatabase(
    String folderPath,
    void Function(int current, int total, String bookName)? onProgress, {
    String? mainDbPath,
  }) async {
    _isCancelled = false;
    debugPrint('📖 Starting book conversion...');
    debugPrint('📂 Folder: $folderPath');

    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      debugPrint('❌ Folder does not exist: $folderPath');
      throw Exception('התיקייה לא קיימת: $folderPath');
    }
    debugPrint('✅ Folder exists');

    // Create temporary database
    final tempDbPath = path.join(
      Directory.systemTemp.path,
      'temp_books_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    debugPrint('💾 Creating temp database: $tempDbPath');

    final db = await databaseFactory.openDatabase(tempDbPath);
    debugPrint('✅ Temp database created');

    try {
      // If mainDbPath provided, copy ALL tables schema from it
      if (mainDbPath != null && await File(mainDbPath).exists()) {
        debugPrint(
            '📋 Copying ALL tables schema from main database: $mainDbPath');
        final mainDb = await databaseFactory.openDatabase(mainDbPath);

        try {
          // Get ALL tables from main database
          final tablesResult = await mainDb.rawQuery(
              "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");

          debugPrint('📊 Found ${tablesResult.length} tables in main database');

          // Create all tables in temp database
          for (final table in tablesResult) {
            final tableName = table['name'] as String;
            final sql = table['sql'] as String;

            try {
              await db.execute(sql);
              debugPrint('✅ Created table: $tableName');
            } catch (e) {
              debugPrint('⚠️ Failed to create table $tableName: $e');
              // Continue anyway - some tables might not be needed
            }
          }

          debugPrint('✅ All tables created successfully!');
        } finally {
          await mainDb.close();
        }
      } else {
        debugPrint('📋 Creating minimal schema (no main DB provided)...');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS category (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL
          )
        ''');
        debugPrint('✅ Category table created');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS book (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL
          )
        ''');
        debugPrint('✅ Book table created');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS line (
          id INTEGER PRIMARY KEY,
          book INTEGER NOT NULL,
          line_number INTEGER NOT NULL,
          text TEXT NOT NULL,
          FOREIGN KEY (book) REFERENCES book(id)
        )
      ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS tocEntry (
          id INTEGER PRIMARY KEY,
          book INTEGER NOT NULL,
          parent INTEGER,
          text INTEGER NOT NULL,
          level INTEGER NOT NULL,
          order_num INTEGER NOT NULL,
          start_line INTEGER NOT NULL,
          FOREIGN KEY (book) REFERENCES book(id),
          FOREIGN KEY (text) REFERENCES tocText(id)
        )
      ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS tocText (
            id INTEGER PRIMARY KEY,
            text TEXT NOT NULL UNIQUE
          )
        ''');
        debugPrint('✅ TOC text table created');
      }

      // Get all text files
      final files = await folder
          .list()
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.txt') || entity.path.endsWith('.text')))
          .cast<File>()
          .toList();

      debugPrint('📚 Found ${files.length} text files');

      if (files.isEmpty) {
        throw Exception('לא נמצאו קבצי טקסט בתיקייה');
      }

      // Get folder name for category
      final folderName = path.basename(folderPath);
      debugPrint('📁 Using folder name as category: $folderName');

      // Create category with folder name
      await db.insert('category', {
        'id': 1,
        'title': folderName,
        'level': 0,
      });
      debugPrint('✅ Category created: $folderName');

      // Create default source (if source table exists)
      try {
        await db.insert('source', {
          'id': 1,
          'name': 'ייבוא מקומי',
        });
        debugPrint('✅ Default source created');
      } catch (e) {
        debugPrint('⚠️ Could not create default source: $e');
      }

      int bookId = 1;
      int lineId = 1;
      int tocTextId = 1;
      int tocEntryId = 1;

      // Get actual column names from tables
      debugPrint('📋 Reading table schemas...');
      final bookColumns = await getTableColumns(db, 'book');
      final lineColumns = await getTableColumns(db, 'line');
      final tocEntryColumns = await getTableColumns(db, 'tocEntry');
      debugPrint('   book columns: ${bookColumns.join(", ")}');
      debugPrint('   line columns: ${lineColumns.join(", ")}');
      debugPrint('   tocEntry columns: ${tocEntryColumns.join(", ")}');

      debugPrint('🔄 Starting to process ${files.length} files...');

      for (int i = 0; i < files.length; i++) {
        // Check for cancellation
        if (_isCancelled) {
          await db.close();
          final tempFile = File(tempDbPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          throw Exception('הפעולה בוטלה על ידי המשתמש');
        }

        final file = files[i];
        final rawTitle = path.basenameWithoutExtension(file.path);

        // Sanitize and validate book title
        final bookTitle = _sanitizeTitle(rawTitle);
        if (bookTitle.isEmpty) {
          debugPrint('   ⚠️ Skipping file with invalid title: $rawTitle');
          continue;
        }

        debugPrint('📖 Processing file ${i + 1}/${files.length}: $bookTitle');
        onProgress?.call(i + 1, files.length, bookTitle);

        // Check for duplicates
        final existing =
            await db.query('book', where: 'title = ?', whereArgs: [bookTitle]);
        if (existing.isNotEmpty) {
          debugPrint('   ⚠️ Book "$bookTitle" already exists, skipping');
          continue;
        }

        // Insert book with all required fields
        try {
          await db.insert('book', {
            'id': bookId,
            'title': bookTitle,
            'categoryId': 1,
            'sourceId': 1,
            'orderIndex': bookId, // Use bookId as order
            'totalLines': 0, // Will be updated later
            'isBaseBook': 0,
            'hasTargumConnection': 0,
            'hasReferenceConnection': 0,
            'hasCommentaryConnection': 0,
            'hasOtherConnection': 0,
          });
          debugPrint('   ✅ Book inserted: $bookTitle');
        } catch (e) {
          debugPrint('   ❌ Failed to insert book: $e');
          throw Exception('Failed to insert book "$bookTitle": $e');
        }

        // Read and insert lines
        debugPrint('   📝 Reading file content...');
        final content = await file.readAsString();
        final lines = content.split('\n');
        debugPrint('   📝 Found ${lines.length} lines');

        int linesInserted = 0;
        for (int lineNum = 0; lineNum < lines.length; lineNum++) {
          final lineText = lines[lineNum].trim();
          if (lineText.isNotEmpty) {
            try {
              await db.insert('line', {
                'id': lineId,
                'bookId': bookId,
                'lineIndex': lineNum, // 0-based index
                'content': lineText, // 'content' not 'text'!
              });
              lineId++;
              linesInserted++;
            } catch (e) {
              debugPrint('   ❌ Failed to insert line $lineNum: $e');
              throw Exception('Failed to insert line in "$bookTitle": $e');
            }
          }
        }
        debugPrint('   ✅ Inserted $linesInserted lines');

        // Create simple TOC entry
        await db.insert('tocText', {
          'id': tocTextId,
          'text': bookTitle,
        });

        await db.insert('tocEntry', {
          'id': tocEntryId,
          'bookId': bookId,
          'parentId': null, // 'parentId' not 'parent'
          'textId': tocTextId, // 'textId' not 'text'
          'level': 0,
          'isLastChild': 1,
          'hasChildren': 0,
        });

        tocTextId++;
        tocEntryId++;
        bookId++;
      }

      await db.close();
      return tempDbPath;
    } catch (e) {
      await db.close();
      // Clean up temp file on error
      final tempFile = File(tempDbPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Get the actual schema of a table from the database
  static Future<List<String>> getTableColumns(
      Database db, String tableName) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = result.map((row) => row['name'] as String).toList();
    debugPrint('📋 Table $tableName columns: ${columns.join(", ")}');
    return columns;
  }

  /// Sanitize book title to prevent SQL injection and invalid characters
  static String _sanitizeTitle(String title) {
    // Remove control characters and trim
    title = title.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();

    // Limit length to prevent overflow
    if (title.length > 255) {
      title = title.substring(0, 255);
    }

    return title;
  }

  /// Merge temporary database with main seforim.db
  static Future<void> mergeDatabases(
    String mainDbPath,
    String tempDbPath,
    void Function(String status)? onProgress, {
    bool createBackup = true,
    String? backupPath,
  }) async {
    debugPrint('🔄 Starting merge process...');
    debugPrint('📂 Main DB: $mainDbPath');
    debugPrint('📂 Temp DB: $tempDbPath');

    // Check if main DB is locked
    final mainDbFile = File(mainDbPath);
    if (!await mainDbFile.exists()) {
      throw Exception('קובץ מאגר הנתונים לא קיים: $mainDbPath');
    }

    debugPrint('✅ Main DB file exists');

    Database? mainDb;
    try {
      debugPrint('🔓 Attempting to open main database...');

      // Try to enable WAL mode for concurrent access
      try {
        final testDb = await databaseFactory.openDatabase(mainDbPath);
        await testDb.execute('PRAGMA journal_mode=WAL');
        await testDb.close();
        debugPrint('✅ WAL mode enabled');
      } catch (e) {
        debugPrint('⚠️ Could not enable WAL mode: $e');
      }

      mainDb = await databaseFactory.openDatabase(
        mainDbPath,
        options: OpenDatabaseOptions(
          readOnly: false,
          singleInstance: true, // Prevent concurrent access issues
        ),
      );
      debugPrint('✅ Main database opened successfully (single instance mode)');

      // Get actual schema from main database
      debugPrint('📋 Reading main database schema...');
      final categoryColumns = await getTableColumns(mainDb, 'category');
      final bookColumns = await getTableColumns(mainDb, 'book');
      final lineColumns = await getTableColumns(mainDb, 'line');
      final tocEntryColumns = await getTableColumns(mainDb, 'tocEntry');
      final tocTextColumns = await getTableColumns(mainDb, 'tocText');

      debugPrint('');
      debugPrint('🔍 DETECTED SCHEMA:');
      debugPrint('   category: ${categoryColumns.join(", ")}');
      debugPrint('   book: ${bookColumns.join(", ")}');
      debugPrint('   line: ${lineColumns.join(", ")}');
      debugPrint('   tocEntry: ${tocEntryColumns.join(", ")}');
      debugPrint('   tocText: ${tocTextColumns.join(", ")}');
      debugPrint('');
    } catch (e) {
      debugPrint('❌ Failed to open main database: $e');
      throw Exception(
          'לא ניתן לפתוח את מאגר הנתונים.\n\nהסיבה: $e\n\nנסה לסגור את האפליקציה ולהריץ את הייבוא מחוץ לאפליקציה.');
    }

    try {
      // Create backup if requested
      if (createBackup) {
        onProgress?.call('יוצר גיבוי...');
        debugPrint('💾 Creating backup...');

        try {
          final defaultBackupPath =
              '$mainDbPath.backup.${DateTime.now().millisecondsSinceEpoch}';
          final finalBackupPath = backupPath ?? defaultBackupPath;

          // Check if there's enough space
          final dbFile = File(mainDbPath);
          final dbSize = await dbFile.length();
          debugPrint(
              '📊 Database size: ${(dbSize / 1024 / 1024).toStringAsFixed(2)} MB');

          await dbFile.copy(finalBackupPath);
          debugPrint('✅ Backup created: $finalBackupPath');
        } catch (e) {
          debugPrint('⚠️ Backup failed: $e');
          if (e.toString().contains('not enough space')) {
            debugPrint('💡 Continuing without backup due to disk space...');
            onProgress?.call('⚠️ אין מספיק מקום לגיבוי, ממשיך בלי גיבוי...');
          } else {
            rethrow;
          }
        }
      } else {
        debugPrint('⚠️ Skipping backup as requested');
        onProgress?.call('מדלג על גיבוי...');
      }

      onProgress?.call('מחשב offsets...');
      debugPrint('🔢 Calculating offsets...');

      // Get max IDs from main database
      final maxBookIdResult =
          await mainDb.rawQuery('SELECT MAX(id) as max_id FROM book');
      final maxBookId = maxBookIdResult.first['max_id'] as int? ?? 0;
      debugPrint('📚 Max book ID: $maxBookId');

      final maxLineIdResult =
          await mainDb.rawQuery('SELECT MAX(id) as max_id FROM line');
      final maxLineId = maxLineIdResult.first['max_id'] as int? ?? 0;
      debugPrint('📝 Max line ID: $maxLineId');

      final maxTocEntryIdResult =
          await mainDb.rawQuery('SELECT MAX(id) as max_id FROM tocEntry');
      final maxTocEntryId = maxTocEntryIdResult.first['max_id'] as int? ?? 0;
      debugPrint('📖 Max TOC entry ID: $maxTocEntryId');

      final maxTocTextIdResult =
          await mainDb.rawQuery('SELECT MAX(id) as max_id FROM tocText');
      final maxTocTextId = maxTocTextIdResult.first['max_id'] as int? ?? 0;
      debugPrint('📑 Max TOC text ID: $maxTocTextId');

      final maxCategoryIdResult =
          await mainDb.rawQuery('SELECT MAX(id) as max_id FROM category');
      final maxCategoryId = maxCategoryIdResult.first['max_id'] as int? ?? 0;
      debugPrint('📂 Max category ID: $maxCategoryId');

      // Calculate offsets
      final categoryOffset = maxCategoryId + 10000;
      final bookOffset = maxBookId + 1000;
      final lineOffset = maxLineId + 10000;
      final tocEntryOffset = maxTocEntryId + 1000;
      final tocTextOffset = maxTocTextId + 1000;

      debugPrint(
          '➕ Offsets: book=$bookOffset, line=$lineOffset, toc=$tocEntryOffset');

      onProgress?.call('מאחד מאגרי נתונים...');
      debugPrint('🔗 Attaching temp database...');

      // Attach temp database
      await mainDb.execute("ATTACH DATABASE '$tempDbPath' AS temp_db");
      debugPrint('✅ Temp database attached');

      // Start transaction
      debugPrint('🔄 Starting transaction...');
      await mainDb.execute('BEGIN TRANSACTION');

      try {
        // Get columns again for INSERT statements
        final catColumns = await getTableColumns(mainDb, 'category');
        final bkColumns = await getTableColumns(mainDb, 'book');

        // Check if category already exists by title
        debugPrint('📂 Checking for existing category...');
        final tempCategoryResult = await mainDb
            .rawQuery('SELECT title FROM temp_db.category WHERE id = 1');
        final categoryTitle = tempCategoryResult.first['title'] as String;
        debugPrint('   Looking for category: $categoryTitle');

        final existingCategoryResult = await mainDb.rawQuery(
          'SELECT id FROM category WHERE title = ?',
          [categoryTitle],
        );

        int actualCategoryId;
        if (existingCategoryResult.isNotEmpty) {
          actualCategoryId = existingCategoryResult.first['id'] as int;
          debugPrint('   ✅ Category already exists with id: $actualCategoryId');
        } else {
          // Create new category
          debugPrint('   Creating new category...');
          final catCols = catColumns.join(', ');
          final catColsWithOffset = catColumns.map((col) {
            if (col == 'id') {
              return 'id + $categoryOffset';
            }
            if (col == 'parentId') {
              return 'CASE WHEN parentId IS NULL THEN NULL ELSE parentId + $categoryOffset END';
            }
            return col;
          }).join(', ');

          await mainDb.execute('''
            INSERT INTO category ($catCols)
            SELECT $catColsWithOffset
            FROM temp_db.category
          ''');
          actualCategoryId = 1 + categoryOffset;
          debugPrint('   ✅ New category created with id: $actualCategoryId');
        }

        // Copy books - link to the actual category
        debugPrint('📚 Copying books...');
        final bookCols = bkColumns.join(', ');
        final bookColsWithOffset = bkColumns.map((col) {
          if (col == 'id') {
            return 'id + $bookOffset';
          }
          if (col == 'categoryId') {
            return '$actualCategoryId'; // Use actual category ID!
          }
          return col;
        }).join(', ');

        debugPrint('   Using columns: $bookCols');
        debugPrint('   Linking books to category: $actualCategoryId');
        await mainDb.execute('''
          INSERT INTO book ($bookCols)
          SELECT $bookColsWithOffset
          FROM temp_db.book
        ''');
        debugPrint('✅ Books copied');

        // Copy TOC texts (use INSERT OR IGNORE for UNIQUE constraint)
        debugPrint('📑 Copying TOC texts...');
        await mainDb.execute('''
          INSERT OR IGNORE INTO tocText (id, text)
          SELECT 
            id + $tocTextOffset,
            text
          FROM temp_db.tocText
        ''');
        debugPrint('✅ TOC texts copied');

        // Copy lines - use actual columns
        debugPrint('📝 Copying lines...');
        final lineColumns = await getTableColumns(mainDb, 'line');
        final lineCols = lineColumns.join(', ');
        final lineColsWithOffset = lineColumns.map((col) {
          if (col == 'id') return 'id + $lineOffset';
          if (col == 'bookId') return 'bookId + $bookOffset';
          return col;
        }).join(', ');

        debugPrint('   Using columns: $lineCols');
        await mainDb.execute('''
          INSERT INTO line ($lineCols)
          SELECT $lineColsWithOffset
          FROM temp_db.line
        ''');
        debugPrint('✅ Lines copied');

        // Copy TOC entries - use actual columns
        debugPrint('📖 Copying TOC entries...');
        final tocColumns = await getTableColumns(mainDb, 'tocEntry');
        final tocCols = tocColumns.join(', ');
        final tocColsWithOffset = tocColumns.map((col) {
          if (col == 'id') return 'id + $tocEntryOffset';
          if (col == 'bookId') return 'bookId + $bookOffset';
          if (col == 'parentId') {
            return 'CASE WHEN parentId IS NULL THEN NULL ELSE parentId + $tocEntryOffset END';
          }
          if (col == 'textId') return 'textId + $tocTextOffset';
          return col;
        }).join(', ');

        debugPrint('   Using columns: $tocCols');
        await mainDb.execute('''
          INSERT INTO tocEntry ($tocCols)
          SELECT $tocColsWithOffset
          FROM temp_db.tocEntry
        ''');
        debugPrint('✅ TOC entries copied');

        debugPrint('💾 Committing transaction...');
        await mainDb.execute('COMMIT');
        debugPrint('✅ Transaction committed successfully');
        onProgress?.call('הושלם בהצלחה!');
      } catch (e) {
        debugPrint('❌ Error during merge: $e');
        debugPrint('🔙 Rolling back transaction...');
        await mainDb.execute('ROLLBACK');
        debugPrint('✅ Rollback completed');
        onProgress?.call('שגיאה: $e');
        rethrow;
      } finally {
        debugPrint('🔌 Detaching temp database...');
        await mainDb.execute('DETACH DATABASE temp_db');
        debugPrint('✅ Temp database detached');
      }
    } catch (e) {
      debugPrint('❌ Fatal error in merge: $e');
      rethrow;
    } finally {
      debugPrint('🔒 Closing main database...');
      await mainDb.close();
      debugPrint('✅ Main database closed');
    }
  }

  /// Full import process: convert and merge
  static Future<void> importBooksFromFolder(
    String folderPath,
    String mainDbPath,
    void Function(String status, {int? current, int? total})? onProgress, {
    bool createBackup = true,
    String? backupPath,
    bool deleteSourceFiles = false,
  }) async {
    String? tempDbPath;
    List<File> importedFiles = [];

    try {
      onProgress?.call('ממיר קבצים למאגר נתונים...');

      // Get list of files before conversion
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        importedFiles = await folder
            .list()
            .where((entity) =>
                entity is File &&
                (entity.path.endsWith('.txt') || entity.path.endsWith('.text')))
            .cast<File>()
            .toList();
      }

      // Convert books to temporary database
      tempDbPath = await convertBooksToDatabase(
        folderPath,
        (current, total, bookName) {
          onProgress?.call(
            'ממיר: $bookName',
            current: current,
            total: total,
          );
        },
        mainDbPath: mainDbPath,
      );

      onProgress?.call('מאחד עם מאגר הנתונים הראשי...');

      // Merge with main database
      await mergeDatabases(
        mainDbPath,
        tempDbPath,
        (status) => onProgress?.call(status),
        createBackup: createBackup,
        backupPath: backupPath,
      );

      // Add category to imported categories list (using folder name)
      final folderName = path.basename(folderPath);
      await addImportedCategory(folderName);
      debugPrint('📝 Registered category "$folderName" as user-imported');

      // Delete source text files if requested (for internal folders)
      if (deleteSourceFiles && importedFiles.isNotEmpty) {
        onProgress?.call('מוחק קבצי טקסט מקוריים...');
        debugPrint('🗑️ Deleting ${importedFiles.length} source text files...');

        int deletedCount = 0;
        for (final file in importedFiles) {
          try {
            if (await file.exists()) {
              await file.delete();
              deletedCount++;
              debugPrint('   ✅ Deleted: ${path.basename(file.path)}');
            }
          } catch (e) {
            debugPrint(
                '   ⚠️ Failed to delete ${path.basename(file.path)}: $e');
            // Continue with other files even if one fails
          }
        }
        debugPrint(
            '✅ Deleted $deletedCount/${importedFiles.length} text files');
      }

      onProgress?.call('הושלם בהצלחה!');
    } finally {
      // Clean up temporary database
      if (tempDbPath != null) {
        final tempFile = File(tempDbPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }
  }
}
