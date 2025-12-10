import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/migration/dao/daos/database.dart';
import 'package:otzaria/migration/adapters/model_adapters.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as path;

/// A data provider that manages SQLite database operations for the library.
///
/// This class handles all database related operations including:
/// - Reading book content from the database
/// - Managing the library structure (categories and books)
/// - Providing table of contents functionality
/// - Falling back to file system when data is not in database
class SqliteDataProvider {
  late SeforimRepository _repository;
  late String _libraryPath;
  late String _dbPath;
  bool _isInitialized = false;

  /// Singleton instance
  static SqliteDataProvider? _instance;

  SqliteDataProvider._();

  static SqliteDataProvider get instance {
    _instance ??= SqliteDataProvider._();
    return _instance!;
  }

  /// Initializes the database connection
  Future<void> initialize() async {
    if (_isInitialized) return;

    _libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    _dbPath = path.join(_libraryPath, DatabaseConstants.otzariaFolderName,
        DatabaseConstants.databaseFileName);

    debugPrint('Initializing SQLite database at: $_dbPath');

    // Check if database file exists
    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      debugPrint('Database file does not exist yet at: $_dbPath');
      // Database will be created when first book is migrated
      return;
    }

    try {
      final database = MyDatabase.withPath(_dbPath);
      _repository = SeforimRepository(database);
      await _repository.ensureInitialized();
      _isInitialized = true;
      debugPrint('SQLite database initialized successfully');
    } catch (e) {
      debugPrint('Error initializing SQLite database: $e');
      rethrow;
    }
  }

  /// Checks if the database is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Checks if a book exists in the database
  Future<bool> isBookInDatabase(String title) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return false;

    try {
      final book = await _repository.getBookByTitle(title);
      return book != null;
    } catch (e) {
      debugPrint('Error checking if book exists in database: $e');
      return false;
    }
  }

  /// Retrieves the text content of a book from the database
  Future<String?> getBookTextFromDb(String title) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final book = await _repository.getBookByTitle(title);
      if (book == null) return null;

      final lines = await _repository.getLines(book.id, 0, book.totalLines - 1);
      return migrationLinesToText(lines);
    } catch (e) {
      debugPrint('Error getting book text from database: $e');
      return null;
    }
  }

  /// Retrieves the table of contents of a book from the database
  Future<List<TocEntry>?> getBookTocFromDb(String title) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;

    try {
      final book = await _repository.getBookByTitle(title);
      if (book == null) return null;

      final migrationTocEntries = await _repository.getBookTocs(book.id);

      // Convert migration TOC entries to otzaria TOC entries
      final Map<int, TocEntry> idToEntry = {};
      final List<TocEntry> rootEntries = [];

      for (final migrationToc in migrationTocEntries) {
        TocEntry? parent;
        if (migrationToc.parentId != null) {
          parent = idToEntry[migrationToc.parentId];
        }

        final otzariaToc = migrationTocToOtzariaToc(migrationToc, parent);
        idToEntry[migrationToc.id] = otzariaToc;

        if (parent != null) {
          parent.children.add(otzariaToc);
        } else {
          rootEntries.add(otzariaToc);
        }
      }

      return rootEntries;
    } catch (e) {
      debugPrint('Error getting book TOC from database: $e');
      return null;
    }
  }

  /// Gets the repository instance (for advanced operations)
  SeforimRepository? get repository => _isInitialized ? _repository : null;

  /// Gets the database path
  String get dbPath => _dbPath;

  /// Checks if database file exists
  Future<bool> databaseExists() async {
    final dbFile = File(_dbPath);
    return await dbFile.exists();
  }

  /// Exports the database to a specified path
  Future<void> exportDatabase(String destinationPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file does not exist');
    }

    await dbFile.copy(destinationPath);
    debugPrint('Database exported to: $destinationPath');
  }

  /// Imports a database from a specified path
  Future<void> importDatabase(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source database file does not exist');
    }

    // Close existing connection if open
    if (_isInitialized) {
      // TODO: Add close method to repository/database
      _isInitialized = false;
    }

    // Copy the file
    await sourceFile.copy(_dbPath);
    debugPrint('Database imported from: $sourcePath');

    // Reinitialize
    await initialize();
  }

  /// Gets statistics about the database
  Future<Map<String, int>> getDatabaseStats() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) {
      return {'books': 0, 'lines': 0, 'links': 0};
    }

    try {
      final bookCount = await _repository.countAllBooks();
      final linkCount = await _repository.countLinks();

      return {
        'books': bookCount,
        'links': linkCount,
      };
    } catch (e) {
      debugPrint('Error getting database stats: $e');
      return {'books': 0, 'lines': 0, 'links': 0};
    }
  }

  /// Performs a health check on the database
  Future<Map<String, dynamic>> performHealthCheck() async {
    final results = <String, dynamic>{
      'healthy': true,
      'issues': <String>[],
      'warnings': <String>[],
    };

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (!_isInitialized) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database not initialized');
        return results;
      }

      // Check if database file exists
      if (!await databaseExists()) {
        results['healthy'] = false;
        (results['issues'] as List).add('Database file does not exist');
        return results;
      }

      // Check if we can query the database
      try {
        await _repository.countAllBooks();
      } catch (e) {
        results['healthy'] = false;
        (results['issues'] as List).add('Cannot query database: $e');
        return results;
      }

      debugPrint('✅ Database health check passed');
    } catch (e) {
      results['healthy'] = false;
      (results['issues'] as List).add('Health check failed: $e');
    }

    return results;
  }

  /// Optimizes the database (VACUUM)
  Future<void> optimizeDatabase() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) {
      throw Exception('Database not initialized');
    }

    try {
      debugPrint('🔧 Optimizing database...');
      final db = await _repository.database.database;
      await db.execute('VACUUM');
      debugPrint('✅ Database optimized');
    } catch (e) {
      debugPrint('❌ Error optimizing database: $e');
      rethrow;
    }
  }
}
