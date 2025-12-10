import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import '../dao/daos/database.dart';
import '../dao/repository/seforim_repository.dart';
import 'generator.dart';

/// Main entry point for the Otzaria database generator.
/// This function initializes the database, sets up the repository,
/// and runs the generation process.
class BuildFromScratch {
  static Future<void> main() async {
    // Configure logging to show all logs for live monitoring
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('${record.level.name}: ${record.time}: ${record.message}');
    });

    final logger = Logger('Main');

    // Resolve required environment variables for generation mode
    final dbPathEnv =
        "C:/Users/lenovo/Desktop/ozariaDB/seforim.db"; //Platform.environment['SEFORIM_DB'];
    if (dbPathEnv.isEmpty) {
      logger.severe('Missing required environment variable SEFORIM_DB');
      logger.severe('Example: export SEFORIM_DB=/path/to/seforim.db');
      exit(1);
    }
    final dbPath = dbPathEnv;

    final sourceDirEnv =
        'C:/Users/lenovo/Desktop/ozariaDB/librery'; //Platform.environment['OTZARIA_SOURCE_DIR'];

    if (sourceDirEnv.isEmpty) {
      logger.severe(
          'Missing required environment variable OTZARIA_SOURCE_DIR for generation mode');
      logger
          .severe('Example: export OTZARIA_SOURCE_DIR=/path/to/otzaria_latest');
      exit(1);
    }

    final sourcePath = sourceDirEnv;

    final dbFile = File(dbPath);
    final dbExists = dbFile.existsSync();
    logger.info('Database file exists: $dbExists at $dbPath');

    // If the database file exists, rename it to make sure we're creating a new one
    if (dbExists) {
      final backupFile = File('$dbPath.bak');
      if (backupFile.existsSync()) {
        backupFile.deleteSync();
      }
      dbFile.renameSync(backupFile.path);
      logger.info('Renamed existing database to ${backupFile.path}');
    }
    MyDatabase.initialize();
    final database = MyDatabase.withPath(dbPath);

    if (!Directory(sourcePath).existsSync()) {
      logger.severe('The source directory does not exist: $sourcePath');
      exit(1);
    }

    logger.info('=== Otzaria Database Generator ===');
    logger.info('Source: $sourcePath');
    logger.info('Database: $dbPath');

    final repository = SeforimRepository(database);
    await repository.ensureInitialized();

    try {
      final generator = DatabaseGenerator(sourcePath, repository);
      await generator.generate();

      logger.info('Generation completed successfully!');
      logger.info('Database created: $dbPath');
    } catch (e, stackTrace) {
      logger.severe('Error during generation', e, stackTrace);
      exit(1);
    } finally {
      await repository.close();
    }
  }
}
