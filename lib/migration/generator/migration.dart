import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import '../dao/repository/seforim_repository.dart';
import '../dao/drift/database.dart';

/// Utilities to migrate an existing Otzaria database to include the new
/// per-connection-type flags on the `book` table and populate them based
/// on existing links.
class DatabaseMigration {
  static final Logger _logger = Logger('DatabaseMigration');

  /// Runs the migration on an existing database file opened by the provided repository.
  /// Steps:
  /// 1) Add new columns to book (if they don't already exist) with default 0.
  /// 2) For every book, compute whether it has links of type TARGUM, REFERENCE,
  ///    COMMENTARY, OTHER (as source or target) and update the flags.
  static Future<void> migrateBookConnectionFlags(
      SeforimRepository repository) async {
    _logger.info(
        'Starting migration: add book connection flag columns and backfill values');

    // 1) Add columns (attempt; ignore error if column already exists)
    await _addColumnIfMissing(repository, "hasTargumConnection");
    await _addColumnIfMissing(repository, "hasReferenceConnection");
    await _addColumnIfMissing(repository, "hasCommentaryConnection");
    await _addColumnIfMissing(repository, "hasOtherConnection");

    // 2) Backfill flags per book based on existing links - OPTIMIZED with single query
    final books = await repository.getAllBooks();
    _logger.info('Found ${books.length} books to migrate');

    // Create a single query that computes all flags for all books at once
    _logger
        .info('Computing connection flags for all books in a single query...');
    await repository.updateAllBookConnectionFlagsOptimized();

    final processed = books.length;
    _logger.info(
        'Migration completed: backfilled flags for $processed/${books.length} books');

    _logger.info(
        'Migration completed: backfilled flags for $processed/${books.length} books');
  }

  static Future<void> _addColumnIfMissing(
      SeforimRepository repository, String column) async {
    // SQLite doesn't universally support IF NOT EXISTS for ADD COLUMN; just try/catch
    final sql =
        "ALTER TABLE book ADD COLUMN $column INTEGER NOT NULL DEFAULT 0";
    try {
      await repository.executeRawQuery(sql);
      _logger.info('Added column \'$column\' to book');
    } catch (e) {
      // Column probably exists; log at debug level
      _logger.fine(
          'Column \'$column\' likely exists already; skipping (error: ${e.toString()})');
    }
  }
}

/// Standalone entry point to run ONLY the migration on an existing database.
///
/// Usage:
///   export SEFORIM_DB=/path/to/seforim.db
///   (then run this main from your IDE or command line)
Future<void> main(List<String> args) async {
  // Set up logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // Using stderr for logging output instead of print
    stderr.writeln('${record.level.name}: ${record.time}: ${record.message}');
  });

  final logger = Logger('MigrationMain');

  // Parse command line arguments or environment variable
  String? dbPath;

  if (args.isNotEmpty) {
    dbPath = args[0];
  } else {
    dbPath = Platform.environment['SEFORIM_DB'];
  }

  if (dbPath == null || dbPath.isEmpty) {
    logger.severe('Missing required database path');
    logger.severe(
        'Usage: dart run lib/generator/migration.dart <path/to/seforim.db>');
    logger.severe(
        'Or set environment variable: export SEFORIM_DB=/path/to/seforim.db');
    exit(1);
  }

  final dbFile = File(dbPath);
  if (!await dbFile.exists()) {
    logger.severe('Database file does not exist: $dbPath');
    exit(1);
  }

  logger.info('=== SEFORIM Database Migration (existing DB) ===');
  logger.info('Database: $dbPath');

  // Create database with custom path
  final database = MyDatabase.withPath(dbPath);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();

  try {
    await DatabaseMigration.migrateBookConnectionFlags(repository);
    logger.info('Migration completed successfully!');
  } catch (e) {
    logger.severe('Error during migration', e);
    exit(1);
  } finally {
    await repository.close();
  }
}
