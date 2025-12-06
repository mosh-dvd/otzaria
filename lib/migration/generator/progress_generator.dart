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
  String _currentBookTitle = '';
  Timer? _progressTimer;

  ProgressDatabaseGenerator(
    super.sourceDirectory,
    super.repository, {
    super.onDuplicateBook,
    this.createIndexes = true,
  });

  @override
  Future<void> generate() async {
    // Start a periodic timer to emit progress updates every 500ms
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_currentBookTitle.isNotEmpty) {
        _emitProgress(GenerationProgress(
          phase: GenerationPhase.processingBooks,
          currentBook: _currentBookTitle,
          processedBooks: _processedBooks,
          totalBooks: _totalBooks,
          message: 'מעבד: $_currentBookTitle',
          progress: _totalBooks > 0 ? 0.1 + (0.5 * (_processedBooks / _totalBooks)) : 0.1,
        ));
      }
    });
    
    try {
      _emitProgress(GenerationProgress(
        phase: GenerationPhase.initializing,
        message: 'מאתחל מסד נתונים...',
        progress: 0.0,
      ));

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

      // Call the parent class generate() method which does all the work
      await super.generate();

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
      rethrow;
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
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
    
    // Update current book title (will be picked up by timer)
    _currentBookTitle = title;
    _processedBooks++;

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
    _progressTimer?.cancel();
    _progressController.close();
  }
}
