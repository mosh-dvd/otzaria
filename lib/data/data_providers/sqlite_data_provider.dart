import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';

/// SQLite data provider for reading books from the seforim.db database
/// 
/// This provider reads book content, table of contents, and links from a SQLite database
/// instead of individual text files, providing much better performance.
class SqliteDataProvider {
  static Database? _database;
  static String? _dbPath;

  /// Get the singleton database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database connection
  static Future<Database> _initDatabase() async {
    try {
      // Initialize FFI for desktop platforms
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Try to find the database file
      final dbFile = await _findDatabaseFile();
      if (dbFile == null) {
        throw Exception('Database file seforim.db not found');
      }

      _dbPath = dbFile.path;
      debugPrint('Opening database at: $_dbPath');

      // Open the database in read-only mode
      final db = await openDatabase(
        _dbPath!,
        readOnly: true,
        singleInstance: true,
      );

      debugPrint('Database opened successfully');
      return db;
    } catch (e) {
      debugPrint('Error initializing database: $e');
      rethrow;
    }
  }

  /// Find the database file in various possible locations
  static Future<File?> _findDatabaseFile() async {
    // 1. Check in project root
    var dbFile = File('seforim.db');
    if (await dbFile.exists()) return dbFile;

    // 2. Check in application documents directory
    try {
      final appDir = await getApplicationDocumentsDirectory();
      dbFile = File(join(appDir.path, 'seforim.db'));
      if (await dbFile.exists()) return dbFile;
    } catch (e) {
      debugPrint('Could not check app documents directory: $e');
    }

    // 3. Check in application support directory
    try {
      final appDir = await getApplicationSupportDirectory();
      dbFile = File(join(appDir.path, 'seforim.db'));
      if (await dbFile.exists()) return dbFile;
    } catch (e) {
      debugPrint('Could not check app support directory: $e');
    }

    return null;
  }

  /// Close the database connection
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Get book ID by title
  Future<int?> getBookId(String title) async {
    try {
      final db = await database;
      final result = await db.query(
        'book',
        columns: ['id'],
        where: 'title = ?',
        whereArgs: [title],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return result.first['id'] as int;
    } catch (e) {
      debugPrint('Error getting book ID for "$title": $e');
      return null;
    }
  }

  /// Get all lines of a book as a list of strings
  Future<List<String>> getBookLines(String title) async {
    try {
      final bookId = await getBookId(title);
      if (bookId == null) {
        throw Exception('Book not found: $title');
      }

      final db = await database;
      final result = await db.query(
        'line',
        columns: ['content'],
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'lineIndex ASC',
      );

      return result.map((row) => row['content'] as String).toList();
    } catch (e) {
      debugPrint('Error getting book lines for "$title": $e');
      rethrow;
    }
  }

  /// Get book text as a single string
  Future<String> getBookText(String title) async {
    final lines = await getBookLines(title);
    return lines.join('\n');
  }

  /// Get table of contents for a book
  Future<List<TocEntry>> getBookToc(String title) async {
    try {
      final bookId = await getBookId(title);
      if (bookId == null) {
        throw Exception('Book not found: $title');
      }

      final db = await database;
      
      // Get TOC entries with their text
      final result = await db.rawQuery('''
        SELECT 
          te.id,
          te.level,
          te.parentId,
          te.lineId,
          tt.text,
          l.lineIndex
        FROM tocEntry te
        JOIN tocText tt ON te.textId = tt.id
        LEFT JOIN line l ON te.lineId = l.id
        WHERE te.bookId = ?
        ORDER BY l.lineIndex ASC
      ''', [bookId]);

      // Build TOC tree
      final entries = <TocEntry>[];
      final entryMap = <int, TocEntry>{};

      for (final row in result) {
        final id = row['id'] as int;
        final level = row['level'] as int;
        final parentId = row['parentId'] as int?;
        final text = row['text'] as String;
        final lineIndex = row['lineIndex'] as int? ?? 0;

        final entry = TocEntry(
          text: text,
          index: lineIndex,
          level: level,
          parent: parentId != null ? entryMap[parentId] : null,
        );

        entryMap[id] = entry;

        // Add to parent's children if has parent
        if (parentId != null && entryMap.containsKey(parentId)) {
          entryMap[parentId]!.children.add(entry);
        }

        // Add to root list if no parent or parent not found yet
        if (parentId == null || !entryMap.containsKey(parentId)) {
          entries.add(entry);
        }
      }

      return entries;
    } catch (e) {
      debugPrint('Error getting TOC for "$title": $e');
      return [];
    }
  }

  /// Get all links for a book
  Future<List<Link>> getBookLinks(String title) async {
    try {
      final bookId = await getBookId(title);
      if (bookId == null) {
        return [];
      }

      final db = await database;
      
      // Get links where this book is the source
      final result = await db.rawQuery('''
        SELECT 
          l.id,
          l.sourceBookId,
          l.targetBookId,
          l.sourceLineId,
          l.targetLineId,
          ct.name as connectionType,
          sb.title as sourceTitle,
          tb.title as targetTitle,
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex
        FROM link l
        JOIN connection_type ct ON l.connectionTypeId = ct.id
        JOIN book sb ON l.sourceBookId = sb.id
        JOIN book tb ON l.targetBookId = tb.id
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        WHERE l.sourceBookId = ?
        ORDER BY sl.lineIndex ASC
      ''', [bookId]);

      return result.map((row) {
        final connectionType = row['connectionType'] as String;
        final sourceLineIndex = row['sourceLineIndex'] as int;
        final targetLineIndex = row['targetLineIndex'] as int;
        final targetTitle = row['targetTitle'] as String;

        return Link(
          heRef: '', // Empty for now, can be populated if needed
          index1: sourceLineIndex + 1, // Convert to 1-based index
          index2: targetLineIndex + 1,
          connectionType: connectionType.toLowerCase(),
          path2: targetTitle, // Use title as path
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting links for "$title": $e');
      return [];
    }
  }

  /// Check if a book exists in the database
  Future<bool> bookExists(String title) async {
    final bookId = await getBookId(title);
    return bookId != null;
  }

  /// Get all book titles from the database
  Future<List<String>> getAllBookTitles() async {
    try {
      final db = await database;
      final result = await db.query(
        'book',
        columns: ['title'],
        orderBy: 'orderIndex ASC, title ASC',
      );

      return result.map((row) => row['title'] as String).toList();
    } catch (e) {
      debugPrint('Error getting all book titles: $e');
      return [];
    }
  }

  /// Get book metadata
  Future<Map<String, dynamic>?> getBookMetadata(String title) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT 
          b.*,
          c.title as categoryTitle,
          s.name as sourceName
        FROM book b
        LEFT JOIN category c ON b.categoryId = c.id
        LEFT JOIN source s ON b.sourceId = s.id
        WHERE b.title = ?
        LIMIT 1
      ''', [title]);

      if (result.isEmpty) return null;
      return result.first;
    } catch (e) {
      debugPrint('Error getting metadata for "$title": $e');
      return null;
    }
  }
}
