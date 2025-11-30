import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/file_sync/database_migration_event.dart';
import 'package:otzaria/file_sync/database_migration_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart' as lib;
import 'package:otzaria/migration/generator/generator.dart';
import 'package:otzaria/migration/dao/drift/database.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as path;

/// Bloc for managing database migration process
class DatabaseMigrationBloc extends Bloc<DatabaseMigrationEvent, DatabaseMigrationState> {
  final FileSystemData _fileSystemData;
  bool _isCancelled = false;

  DatabaseMigrationBloc({
    required FileSystemData fileSystemData,
  })  : _fileSystemData = fileSystemData,
        super(const DatabaseMigrationState()) {
    on<CheckBooksToMigrate>(_onCheckBooksToMigrate);
    on<StartMigration>(_onStartMigration);
    on<CancelMigration>(_onCancelMigration);
    on<ResetMigrationState>(_onResetMigrationState);
    on<UpdateMigrationProgress>(_onUpdateMigrationProgress);
    on<MigrateFolderToDatabase>(_onMigrateFolderToDatabase);
  }

  Future<void> _onCheckBooksToMigrate(
    CheckBooksToMigrate event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    emit(state.copyWith(status: DatabaseMigrationStatus.checking));

    try {
      // Get all books from the library
      final library = await _fileSystemData.getLibrary();
      final allBooks = <String>[];

      void collectBooks(dynamic item) {
        if (item is lib.Category) {
          for (final book in item.books) {
            if (book is TextBook) {
              allBooks.add(book.title);
            }
          }
          for (final subCategory in item.subCategories) {
            collectBooks(subCategory);
          }
        }
      }

      for (final category in library.subCategories) {
        collectBooks(category);
      }

      // Filter books that are not yet in the database
      final booksToMigrate = <String>[];
      for (final bookTitle in allBooks) {
        final isInDb = await _fileSystemData.isBookInDatabase(bookTitle);
        if (!isInDb) {
          // Check if it's not in the personal folder
          final titleToPath = await _fileSystemData.titleToPath;
          final bookPath = titleToPath[bookTitle];
          if (bookPath != null && !bookPath.contains('${path.separator}אישי${path.separator}')) {
            booksToMigrate.add(bookTitle);
          }
        }
      }

      emit(state.copyWith(
        status: DatabaseMigrationStatus.ready,
        booksToMigrate: booksToMigrate,
        totalCount: booksToMigrate.length,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: DatabaseMigrationStatus.error,
        errorMessage: 'שגיאה בבדיקת ספרים: $e',
      ));
    }
  }

  Future<void> _onStartMigration(
    StartMigration event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    _isCancelled = false;

    emit(state.copyWith(
      status: DatabaseMigrationStatus.migrating,
      booksToMigrate: event.bookTitles,
      totalCount: event.bookTitles.length,
      processedCount: 0,
    ));

    try {
      // Initialize database
      final dbPath = path.join(
        _fileSystemData.libraryPath,
        DatabaseConstants.otzariaFolderName,
        DatabaseConstants.databaseFileName,
      );

      // Ensure directory exists
      final dbDir = Directory(path.dirname(dbPath));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();

      // Create generator
      final generator = DatabaseGenerator(
        _fileSystemData.libraryPath,
        repository,
      );

      final startTime = DateTime.now();
      int processedCount = 0;

      // Process each book
      for (final bookTitle in event.bookTitles) {
        if (_isCancelled) {
          emit(state.copyWith(
            status: DatabaseMigrationStatus.cancelled,
            currentBook: null,
          ));
          return;
        }

        emit(state.copyWith(
          currentBook: bookTitle,
          processedCount: processedCount,
        ));

        try {
          // Get book path
          final titleToPath = await _fileSystemData.titleToPath;
          final bookPath = titleToPath[bookTitle];

          if (bookPath != null) {
            // Get metadata
            final metadata = await generator.loadMetadata();

            // For now, use a default category ID (1)
            // In a full implementation, we'd properly map categories from the library
            final categoryId = 1;

            // Process the book
            await generator.createAndProcessBook(
              bookPath,
              categoryId,
              metadata,
            );

            // Move the file to "קבצים שטופלו" folder after successful migration
            final file = File(bookPath);
            if (await file.exists()) {
              await _moveToProcessedFolder(bookPath);
              debugPrint('📦 Moved file to processed folder: $bookPath');
            }

            // Clear cache for this book
            _fileSystemData.clearBookCache();
          }

          processedCount++;

          // Calculate estimated time remaining
          final elapsed = DateTime.now().difference(startTime);
          final avgTimePerBook = elapsed.inMilliseconds / processedCount;
          final remaining = event.bookTitles.length - processedCount;
          final estimatedMs = (avgTimePerBook * remaining).round();
          final estimatedTime = Duration(milliseconds: estimatedMs);

          emit(state.copyWith(
            processedCount: processedCount,
            estimatedTimeRemaining: estimatedTime,
          ));
        } catch (e) {
          debugPrint('⚠️ Error migrating book "$bookTitle": $e');
          // Continue with next book
        }
      }

      // Close database
      await repository.close();

      emit(state.copyWith(
        status: DatabaseMigrationStatus.completed,
        currentBook: null,
        processedCount: event.bookTitles.length,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: DatabaseMigrationStatus.error,
        errorMessage: 'שגיאה בתהליך ההמרה: $e',
      ));
    }
  }

  Future<void> _onCancelMigration(
    CancelMigration event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    _isCancelled = true;
    // The actual cancellation will be handled in the migration loop
  }

  Future<void> _onResetMigrationState(
    ResetMigrationState event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    emit(const DatabaseMigrationState());
  }

  Future<void> _onUpdateMigrationProgress(
    UpdateMigrationProgress event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    emit(state.copyWith(
      currentBook: event.currentBook,
      processedCount: event.processedCount,
      totalCount: event.totalCount,
    ));
  }

  /// Moves a file to the "קבצים שטופלו" folder while preserving directory structure
  Future<void> _moveToProcessedFolder(String originalPath) async {
    try {
      final libraryPath = _fileSystemData.libraryPath;
      final otzariaPath = path.join(libraryPath, 'אוצריא');
      
      String relativePath;
      
      // Check if the file is inside the "אוצריא" folder
      if (originalPath.contains(otzariaPath)) {
        // Get the relative path from "אוצריא" folder
        relativePath = path.relative(originalPath, from: otzariaPath);
      } else {
        // For files outside "אוצריא", use the file name and create a simple structure
        // Extract the folder structure from the original path
        final fileName = path.basename(originalPath);
        final parentDir = path.dirname(originalPath);
        final parentDirName = path.basename(parentDir);
        
        // Create a relative path that preserves some context
        relativePath = path.join('חיצוני', parentDirName, fileName);
      }
      
      // Create the target path in "קבצים שטופלו" folder
      final processedFolderPath = path.join(libraryPath, 'קבצים שטופלו');
      final targetPath = path.join(processedFolderPath, relativePath);
      
      // Create target directory if it doesn't exist
      final targetDir = Directory(path.dirname(targetPath));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
        debugPrint('📁 Created directory: ${targetDir.path}');
      }
      
      // Move the file (copy then delete)
      final file = File(originalPath);
      await file.copy(targetPath);
      await file.delete();
      
      debugPrint('✅ Moved file from $originalPath to $targetPath');
    } catch (e) {
      debugPrint('⚠️ Error moving file to processed folder: $e');
      // Don't throw - we don't want to stop the migration process
    }
  }

  /// Handles migration of books from a specific folder
  Future<void> _onMigrateFolderToDatabase(
    MigrateFolderToDatabase event,
    Emitter<DatabaseMigrationState> emit,
  ) async {
    _isCancelled = false;
    
    emit(state.copyWith(status: DatabaseMigrationStatus.checking));

    try {
      // Get all text files from the folder recursively
      final folder = Directory(event.folderPath);
      if (!await folder.exists()) {
        emit(state.copyWith(
          status: DatabaseMigrationStatus.error,
          errorMessage: 'התקייה לא נמצאה: ${event.folderPath}',
        ));
        return;
      }

      final bookFiles = <File>[];
      await for (final entity in folder.list(recursive: true)) {
        if (entity is File) {
          final filePath = entity.path.toLowerCase();
          if (filePath.endsWith('.txt') || filePath.endsWith('.docx')) {
            bookFiles.add(entity);
          }
        }
      }

      if (bookFiles.isEmpty) {
        emit(state.copyWith(
          status: DatabaseMigrationStatus.error,
          errorMessage: 'לא נמצאו קבצי טקסט בתקייה',
        ));
        return;
      }

      debugPrint('📚 Found ${bookFiles.length} books to migrate from folder');

      // Start migration immediately
      emit(state.copyWith(
        status: DatabaseMigrationStatus.migrating,
        booksToMigrate: [],
        totalCount: bookFiles.length,
        processedCount: 0,
      ));

      // Initialize database
      final dbPath = path.join(
        _fileSystemData.libraryPath,
        DatabaseConstants.otzariaFolderName,
        DatabaseConstants.databaseFileName,
      );

      // Ensure directory exists
      final dbDir = Directory(path.dirname(dbPath));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();

      // Create generator
      final generator = DatabaseGenerator(
        _fileSystemData.libraryPath,
        repository,
      );

      final startTime = DateTime.now();
      int processedCount = 0;

      // Load metadata once
      final metadata = await generator.loadMetadata();

      // Process each book file
      for (final bookFile in bookFiles) {
        if (_isCancelled) {
          await repository.close();
          emit(state.copyWith(
            status: DatabaseMigrationStatus.cancelled,
            currentBook: null,
          ));
          return;
        }

        final bookTitle = path.basenameWithoutExtension(bookFile.path);
        
        emit(state.copyWith(
          currentBook: bookTitle,
          processedCount: processedCount,
        ));

        try {
          // For now, use a default category ID (1)
          // In a full implementation, we'd properly map categories from the library
          final categoryId = 1;

          // Process the book
          await generator.createAndProcessBook(
            bookFile.path,
            categoryId,
            metadata,
          );

          // Move the file to "קבצים שטופלו" folder after successful migration
          if (await bookFile.exists()) {
            await _moveToProcessedFolder(bookFile.path);
            debugPrint('📦 Moved file to processed folder: ${bookFile.path}');
          }

          // Clear cache for this book
          _fileSystemData.clearBookCache();

          processedCount++;

          // Calculate estimated time remaining
          final elapsed = DateTime.now().difference(startTime);
          final avgTimePerBook = elapsed.inMilliseconds / processedCount;
          final remaining = bookFiles.length - processedCount;
          final estimatedMs = (avgTimePerBook * remaining).round();
          final estimatedTime = Duration(milliseconds: estimatedMs);

          emit(state.copyWith(
            processedCount: processedCount,
            estimatedTimeRemaining: estimatedTime,
          ));
        } catch (e) {
          debugPrint('⚠️ Error migrating book "$bookTitle": $e');
          // Continue with next book
        }
      }

      // Close database
      await repository.close();

      emit(state.copyWith(
        status: DatabaseMigrationStatus.completed,
        currentBook: null,
        processedCount: bookFiles.length,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: DatabaseMigrationStatus.error,
        errorMessage: 'שגיאה בתהליך ההמרה: $e',
      ));
    }
  }
}
