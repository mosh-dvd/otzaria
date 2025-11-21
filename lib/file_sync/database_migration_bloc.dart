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
        'אוצריא',
        'otzaria.db',
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

            // Delete the file after successful migration
            final file = File(bookPath);
            if (await file.exists()) {
              await file.delete();
              debugPrint('🗑️ Deleted file: $bookPath');
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
}
