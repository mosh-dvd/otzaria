import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../core/models/book_metadata.dart';
import '../core/models/generation_progress.dart';
import 'generator.dart';

/// Database generator with progress tracking
class ProgressDatabaseGenerator extends DatabaseGenerator {
  final _progressController = StreamController<GenerationProgress>.broadcast();
  final bool createIndexes;
  
  Stream<GenerationProgress> get progressStream => _progressController.stream;
  
  int _totalBooks = 0;
  int _processedBooks = 0;
  int _totalLinks = 0;
  int _processedLinks = 0;

  ProgressDatabaseGenerator(
    super.sourceDirectory,
    super.repository, {
    super.onDuplicateBook,
    this.createIndexes = true,
  });

  @override
  Future<void> generate() async {
    try {
      _emitProgress(GenerationProgress(
        phase: GenerationPhase.initializing,
        message: 'מאתחל מסד נתונים...',
        progress: 0.0,
      ));

      await repository.disableForeignKeys();
      
      if (createIndexes) {
        _emitProgress(GenerationProgress(
          phase: GenerationPhase.initializing,
          message: 'יוצר אינדקסים...',
          progress: 0.02,
        ));
        await repository.createOptimizationIndexes();
      }

      _emitProgress(GenerationProgress(
        phase: GenerationPhase.loadingMetadata,
        message: 'טוען מטא-דאטה...',
        progress: 0.05,
      ));

      final metadata = await loadMetadata();
      _totalBooks = metadata.length;

      // Check if the selected directory is already "אוצריא" or if it contains "אוצריא"
      String libraryPath;
      if (path.basename(sourceDirectory) == 'אוצריא') {
        // User selected the "אוצריא" directory directly
        libraryPath = sourceDirectory;
      } else {
        // User selected the parent directory, look for "אוצריא" inside
        libraryPath = path.join(sourceDirectory, 'אוצריא');
      }
      
      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        throw StateError('התיקייה "אוצריא" לא נמצאה. נא לבחור את התיקייה "אוצריא" או את התיקייה האב שלה.');
      }

      _emitProgress(GenerationProgress(
        phase: GenerationPhase.processingBooks,
        message: 'מתחיל לעבד ספרים...',
        totalBooks: _totalBooks,
        progress: 0.1,
      ));

      await processDirectory(libraryPath, null, 0, metadata);

      _emitProgress(GenerationProgress(
        phase: GenerationPhase.processingLinks,
        message: 'מתחיל לעבד קישורים...',
        processedBooks: _processedBooks,
        totalBooks: _totalBooks,
        progress: 0.6,
      ));

      await processLinks();

      _emitProgress(GenerationProgress(
        phase: GenerationPhase.finalizing,
        message: 'משלים את התהליך...',
        processedBooks: _processedBooks,
        totalBooks: _totalBooks,
        processedLinks: _processedLinks,
        totalLinks: _totalLinks,
        progress: 0.9,
      ));

      await repository.enableForeignKeys();
      await repository.finalizeDatabase();
      // FTS5 removed - no longer rebuilding FTS5 index
      // await repository.rebuildFts5Index();

      if (!createIndexes) {
        _emitProgress(GenerationProgress(
          phase: GenerationPhase.finalizing,
          message: 'הושלם ללא אינדקסים - ניתן ליצור אותם מאוחר יותר',
          processedBooks: _processedBooks,
          totalBooks: _totalBooks,
          processedLinks: _processedLinks,
          totalLinks: _totalLinks,
          progress: 0.95,
        ));
      }

      _emitProgress(GenerationProgress.complete());
    } catch (e, stackTrace) {
      Logger('ProgressDatabaseGenerator').severe('Error during generation', e, stackTrace);
      _emitProgress(GenerationProgress.error(e.toString()));
      
      try {
        await repository.enableForeignKeys();
        await repository.finalizeDatabase();
      } catch (_) {}
      
      rethrow;
    }
  }

  @override
  Future<void> createAndProcessBook(
    String bookPath,
    int categoryId,
    Map<String, BookMetadata> metadata, {
    bool isBaseBook = false,
  }) async {
    final filename = path.basename(bookPath);
    final title = path.basenameWithoutExtension(filename);
    
    _processedBooks++;
    
    _emitProgress(GenerationProgress(
      phase: GenerationPhase.processingBooks,
      currentBook: title,
      processedBooks: _processedBooks,
      totalBooks: _totalBooks,
      message: 'מעבד: $title',
      progress: 0.1 + (0.5 * (_processedBooks / _totalBooks)),
    ));

    await super.createAndProcessBook(bookPath, categoryId, metadata, isBaseBook: isBaseBook);
  }

  @override
  Future<int> processLinkFile(String linkFile) async {
    final bookTitle = path.basenameWithoutExtension(path.basename(linkFile))
        .replaceAll('_links', '');
    
    _emitProgress(GenerationProgress(
      phase: GenerationPhase.processingLinks,
      currentBook: bookTitle,
      processedBooks: _processedBooks,
      totalBooks: _totalBooks,
      processedLinks: _processedLinks,
      message: 'מעבד קישורים: $bookTitle',
      progress: 0.6 + (0.3 * (_processedLinks / (_totalLinks > 0 ? _totalLinks : 1))),
    ));

    final result = await super.processLinkFile(linkFile);
    _processedLinks += result;
    
    return result;
  }

  @override
  Future<void> processLinks() async {
    // Check if links directory is in sourceDirectory or in parent directory
    Directory linksDir = Directory(path.join(sourceDirectory, 'links'));
    if (!await linksDir.exists() && path.basename(sourceDirectory) == 'אוצריא') {
      // If user selected "אוצריא" directory, look for links in parent
      linksDir = Directory(path.join(path.dirname(sourceDirectory), 'links'));
    }
    
    if (await linksDir.exists()) {
      _totalLinks = await linksDir.list().where((e) => e is File && path.extension(e.path) == '.json').length;
    }
    
    await super.processLinks();
  }

  void _emitProgress(GenerationProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  void dispose() {
    _progressController.close();
  }
}
