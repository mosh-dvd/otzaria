/// Standalone script to convert text books to SQLite database
///
/// This script reads text files from a directory and converts them to SQLite format.
/// The output is a separate database file that can be tested independently.
///
/// Usage:
///   dart run tools/convert_books_to_db.dart `<input_dir>` `<output_db>`
///
/// Example:
///   dart run tools/convert_books_to_db.dart "C:\Books\אוצריא" "output_books.db"
library;

import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void debugPrint(String message) => debugPrint(message);

void main(List<String> args) async {
  debugPrint('📚 Book to SQLite Converter');
  debugPrint('═══════════════════════════════════════\n');

  // Parse arguments
  if (args.length < 2) {
    debugPrint('❌ Error: Missing arguments');
    debugPrint('');
    debugPrint('Usage:');
    debugPrint(
        '  dart run tools/convert_books_to_db.dart <input_dir> <output_db>');
    debugPrint('');
    debugPrint('Example:');
    debugPrint(
        '  dart run tools/convert_books_to_db.dart "C:\\Books\\אוצריא" "output_books.db"');
    exit(1);
  }

  final inputDir = args[0];
  final outputDb = args[1];

  // Validate input directory
  if (!await Directory(inputDir).exists()) {
    debugPrint('❌ Error: Input directory does not exist: $inputDir');
    exit(1);
  }

  // Initialize SQLite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  debugPrint('📂 Input directory: $inputDir');
  debugPrint('💾 Output database: $outputDb');
  debugPrint('');

  try {
    // Create converter
    final converter = BookToDbConverter(inputDir, outputDb);

    // Run conversion
    await converter.convert();

    debugPrint('');
    debugPrint('═══════════════════════════════════════');
    debugPrint('✅ Conversion completed successfully!');
    debugPrint('═══════════════════════════════════════');
  } catch (e, stackTrace) {
    debugPrint('');
    debugPrint('❌ Error during conversion: $e');
    debugPrint('Stack trace: $stackTrace');
    exit(1);
  }
}

class BookToDbConverter {
  final String inputDir;
  final String outputDbPath;
  late Database db;

  int bookIdCounter = 1;
  int lineIdCounter = 1;
  int tocIdCounter = 1;
  int tocTextIdCounter = 1;
  int categoryIdCounter = 1;
  int sourceIdCounter = 1;

  final Map<String, int> categoryCache = {};
  final Map<String, int> tocTextCache = {};
  int defaultSourceId = 1;
  Map<String, dynamic> metadata = {};

  BookToDbConverter(this.inputDir, this.outputDbPath);

  Future<void> convert() async {
    debugPrint('🔧 Step 1: Loading metadata...');
    await _loadMetadata();
    debugPrint('✅ Metadata loaded\n');

    debugPrint('🔧 Step 2: Creating database schema...');
    await _createDatabase();

    debugPrint('✅ Database schema created\n');

    debugPrint('🔧 Step 3: Scanning for text files...');
    final textFiles = await _scanTextFiles();
    debugPrint('✅ Found ${textFiles.length} text files\n');

    if (textFiles.isEmpty) {
      debugPrint('⚠️  No text files found. Nothing to convert.');
      return;
    }

    debugPrint('🔧 Step 3: Converting books...');
    int converted = 0;
    int failed = 0;

    for (final file in textFiles) {
      try {
        await _convertBook(file);
        converted++;
        if (converted % 10 == 0) {
          debugPrint('   Converted $converted/${textFiles.length} books...');
        }
      } catch (e) {
        failed++;
        debugPrint('   ⚠️  Failed to convert ${path.basename(file.path)}: $e');
      }
    }

    debugPrint('✅ Converted $converted books successfully');
    if (failed > 0) {
      debugPrint('⚠️  Failed to convert $failed books');
    }

    debugPrint('');
    debugPrint('🔧 Step 4: Creating indexes...');
    await _createIndexes();
    debugPrint('✅ Indexes created');

    debugPrint('');
    debugPrint('📊 Statistics:');
    await _printStatistics();

    await db.close();
  }

  Future<void> _createDatabase() async {
    // Delete existing database
    if (await File(outputDbPath).exists()) {
      await File(outputDbPath).delete();
      debugPrint('   Deleted existing database');
    }

    // Create new database
    db = await openDatabase(
      outputDbPath,
      version: 1,
      onCreate: (db, version) async {
        // Create tables (same structure as seforim.db)
        await db.execute('''
          CREATE TABLE category (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parentId INTEGER,
            title TEXT NOT NULL,
            level INTEGER NOT NULL DEFAULT 0,
            orderIndex INTEGER NOT NULL DEFAULT 999,
            description TEXT,
            shortDescription TEXT,
            FOREIGN KEY (parentId) REFERENCES category(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE source (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute('''
          CREATE TABLE book (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            categoryId INTEGER NOT NULL,
            sourceId INTEGER NOT NULL,
            title TEXT NOT NULL,
            author TEXT,
            heShortDesc TEXT,
            pubDate TEXT,
            pubPlace TEXT,
            notesContent TEXT,
            orderIndex INTEGER NOT NULL DEFAULT 999,
            totalLines INTEGER NOT NULL DEFAULT 0,
            isBaseBook INTEGER NOT NULL DEFAULT 0,
            hasTargumConnection INTEGER NOT NULL DEFAULT 0,
            hasReferenceConnection INTEGER NOT NULL DEFAULT 0,
            hasCommentaryConnection INTEGER NOT NULL DEFAULT 0,
            hasOtherConnection INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (categoryId) REFERENCES category(id) ON DELETE CASCADE,
            FOREIGN KEY (sourceId) REFERENCES source(id) ON DELETE RESTRICT
          )
        ''');

        await db.execute('''
          CREATE TABLE line (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL,
            lineIndex INTEGER NOT NULL,
            content TEXT NOT NULL,
            tocEntryId INTEGER,
            FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE tocText (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute('''
          CREATE TABLE tocEntry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL,
            parentId INTEGER,
            textId INTEGER NOT NULL,
            level INTEGER NOT NULL,
            lineId INTEGER,
            isLastChild INTEGER NOT NULL DEFAULT 0,
            hasChildren INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
            FOREIGN KEY (parentId) REFERENCES tocEntry(id) ON DELETE CASCADE,
            FOREIGN KEY (textId) REFERENCES tocText(id) ON DELETE CASCADE,
            FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE SET NULL
          )
        ''');

        // Insert default source
        await db
            .insert('source', {'id': 1, 'name': 'Converted from text files'});
      },
    );
  }

  Future<void> _loadMetadata() async {
    try {
      final metadataFile = File(path.join(inputDir, 'metadata.json'));
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final jsonData = jsonDecode(content);
        
        // Convert List to Map (title -> metadata)
        if (jsonData is List) {
          for (final item in jsonData) {
            if (item is Map<String, dynamic> && item.containsKey('title')) {
              final title = item['title'].toString().replaceAll('"', '');
              metadata[title] = item;
            }
          }
          debugPrint('   Loaded metadata for ${metadata.length} items from List');
        } else if (jsonData is Map) {
          metadata = Map<String, dynamic>.from(jsonData);
          debugPrint('   Loaded metadata for ${metadata.length} items from Map');
        }
      } else {
        debugPrint('   ⚠️  metadata.json not found, using defaults');
      }
    } catch (e) {
      debugPrint('   ⚠️  Error loading metadata: $e');
    }
  }

  Future<List<File>> _scanTextFiles() async {
    final files = <File>[];

    await for (final entity in Directory(inputDir).list(recursive: true)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (ext == '.txt') {
          files.add(entity);
        }
      }
    }

    return files;
  }

  Future<void> _convertBook(File file) async {
    final bookTitle = _extractBookTitle(file.path);
    final categoryId = await _getOrCreateCategory(file.path);

    // Get metadata for this book
    final bookMeta = metadata[bookTitle] as Map<String, dynamic>?;
    final orderIndex = bookMeta?['order'] ?? 999;
    final author = bookMeta?['author'] ?? '';
    final heShortDesc = bookMeta?['heShortDesc'] ?? '';
    final pubDate = bookMeta?['pubDate'] ?? '';
    final pubPlace = bookMeta?['pubPlace'] ?? '';

    // Read file content
    final content = await file.readAsString();
    final lines = content.split('\n');

    // Insert book
    final bookId = await db.insert('book', {
      'id': bookIdCounter,
      'categoryId': categoryId,
      'sourceId': defaultSourceId,
      'title': bookTitle,
      'author': author,
      'heShortDesc': heShortDesc,
      'pubDate': pubDate,
      'pubPlace': pubPlace,
      'orderIndex': orderIndex,
      'totalLines': lines.length,
      'isBaseBook': 0,
    });

    // Insert lines and parse TOC
    final tocEntries = <Map<String, dynamic>>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Insert line
      await db.insert('line', {
        'id': lineIdCounter,
        'bookId': bookId,
        'lineIndex': i,
        'content': line,
      });

      // Check if this is a heading (TOC entry)
      final headingLevel = _extractHeadingLevel(line);
      if (headingLevel > 0) {
        final headingText = _extractHeadingText(line);
        final tocTextId = await _getOrCreateTocText(headingText);

        tocEntries.add({
          'bookId': bookId,
          'textId': tocTextId,
          'level': headingLevel,
          'lineId': lineIdCounter,
        });
      }

      lineIdCounter++;
    }

    // Insert TOC entries
    for (final entry in tocEntries) {
      await db.insert('tocEntry', {
        'id': tocIdCounter,
        ...entry,
      });
      tocIdCounter++;
    }

    bookIdCounter++;
  }

  String _extractBookTitle(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);
    return fileName;
  }

  Future<int> _getOrCreateCategory(String filePath) async {
    // Extract category from path
    final relativePath = path.relative(filePath, from: inputDir);
    final parts = path.split(relativePath);

    if (parts.length <= 1) {
      // No category, use default
      return await _getOrCreateCategoryByName('אחר', null);
    }

    // Use the parent directory as category
    final categoryName = parts[parts.length - 2];
    return await _getOrCreateCategoryByName(categoryName, null);
  }

  Future<int> _getOrCreateCategoryByName(String name, int? parentId) async {
    // Check cache
    final cacheKey = '$name-$parentId';
    if (categoryCache.containsKey(cacheKey)) {
      return categoryCache[cacheKey]!;
    }

    // Check database
    final existing = await db.query(
      'category',
      where: 'title = ? AND parentId ${parentId == null ? 'IS NULL' : '= ?'}',
      whereArgs: parentId == null ? [name] : [name, parentId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      categoryCache[cacheKey] = id;
      return id;
    }

    // Get metadata for this category
    final categoryMeta = metadata[name] as Map<String, dynamic>?;
    final orderIndex = categoryMeta?['order'] ?? 999;
    final description = categoryMeta?['heDesc'] ?? '';
    final shortDescription = categoryMeta?['heShortDesc'] ?? '';

    // Create new category
    final id = await db.insert('category', {
      'id': categoryIdCounter,
      'parentId': parentId,
      'title': name,
      'level': parentId == null ? 0 : 1,
      'orderIndex': orderIndex,
      'description': description,
      'shortDescription': shortDescription,
    });

    categoryCache[cacheKey] = id;
    categoryIdCounter++;
    return id;
  }

  Future<int> _getOrCreateTocText(String text) async {
    // Check cache
    if (tocTextCache.containsKey(text)) {
      return tocTextCache[text]!;
    }

    // Check database
    final existing = await db.query(
      'tocText',
      where: 'text = ?',
      whereArgs: [text],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      tocTextCache[text] = id;
      return id;
    }

    // Create new
    final id = await db.insert('tocText', {
      'id': tocTextIdCounter,
      'text': text,
    });

    tocTextCache[text] = id;
    tocTextIdCounter++;
    return id;
  }

  int _extractHeadingLevel(String line) {
    // Check for HTML headings
    final h1 = RegExp(r'<h1[^>]*>');
    final h2 = RegExp(r'<h2[^>]*>');
    final h3 = RegExp(r'<h3[^>]*>');
    final h4 = RegExp(r'<h4[^>]*>');

    if (h1.hasMatch(line)) return 1;
    if (h2.hasMatch(line)) return 2;
    if (h3.hasMatch(line)) return 3;
    if (h4.hasMatch(line)) return 4;

    return 0;
  }

  String _extractHeadingText(String line) {
    // Remove HTML tags
    final text = line.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return text;
  }

  Future<void> _createIndexes() async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_book_category ON book(categoryId)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_book_title ON book(title)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_line_book_index ON line(bookId, lineIndex)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_toc_book ON tocEntry(bookId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_toc_text_id ON tocEntry(textId)');
  }

  Future<void> _printStatistics() async {
    final bookCount = await db.rawQuery('SELECT COUNT(*) as count FROM book');
    final lineCount = await db.rawQuery('SELECT COUNT(*) as count FROM line');
    final tocCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM tocEntry');
    final categoryCount =
        await db.rawQuery('SELECT COUNT(*) as count FROM category');

    debugPrint('   Books: ${bookCount.first['count']}');
    debugPrint('   Lines: ${lineCount.first['count']}');
    debugPrint('   TOC entries: ${tocCount.first['count']}');
    debugPrint('   Categories: ${categoryCount.first['count']}');

    final dbFile = File(outputDbPath);
    final size = await dbFile.length();
    debugPrint(
        '   Database size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
  }
}
