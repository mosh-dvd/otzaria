import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../core/models/author.dart';
import '../core/models/book.dart';
import '../core/models/book_metadata.dart';
import '../core/models/category.dart';
import '../core/models/line.dart';
import '../core/models/link.dart';
import '../core/models/pub_date.dart';
import '../core/models/pub_place.dart';
import '../core/models/toc_entry.dart';
import '../core/models/topic.dart';
import '../dao/repository/seforim_repository.dart';
import 'hebrew_text_utils.dart' as hebrew_text_utils;

/// DatabaseGenerator is responsible for generating the Otzaria database from source files.
/// It processes directories, books, and links to create a structured database.
///
/// This is a Dart conversion of the original Kotlin DatabaseGenerator.
class DatabaseGenerator {
  static final _log = Logger('DatabaseGenerator');

  /// The path to the source directory containing the data files
  final String sourceDirectory;

  /// Cache for acronym data loaded from acronym.json
  Map<String, dynamic>? _acronymData;

  /// The repository used to store the generated data
  final SeforimRepository repository;

  final JsonCodec _json;

  /// Callback to handle duplicate books. Returns true to replace, false to skip.
  /// If null, duplicates will be skipped by default.
  Future<bool> Function(String bookTitle)? onDuplicateBook;

  /// Counter for book IDs
  int _nextBookId = 1;

  /// Counter for line IDs
  int _nextLineId = 1;

  /// Counter for TOC entry IDs
  int _nextTocEntryId = 1;

  /// Caches for performance optimization
  final Map<String, int> _bookTitleToId = {};
  final Map<int, List<int>> _bookLineIndexToId =
      {}; // bookId -> array of lineIds indexed by lineIndex

  /// Track duplicate checks for performance measurement
  int _duplicateChecks = 0;
  int _duplicatesFound = 0;

  /// Library root path for relative path computations
  late String _libraryRoot;

  /// Map from library-relative book key to source name
  final Map<String, String> _manifestSourcesByRel = {};

  /// Cache of source name -> id from DB
  final Map<String, int> _sourceNameToId = {};

  /// Source blacklist
  final Set<String> _sourceBlacklist = {'wiki_jewish_books'};

  /// Tracks books processed from priority list to avoid double insertion
  final Set<String> _processedPriorityBookKeys = {};

  /// Overall progress across books
  int _totalBooksToProcess = 0;
  int _processedBooksCount = 0;

  /// Getter for total books to process (for subclasses)
  int get totalBooksToProcess => _totalBooksToProcess;

  /// Book contents cache: maps library-relative key -> list of lines
  final Map<String, List<String>> _bookContentCache = {};

  DatabaseGenerator(this.sourceDirectory, this.repository,
      {this.onDuplicateBook})
      : _json = const JsonCodec(reviver: _jsonReviver);

  /// JSON reviver to handle numeric values that might come as doubles
  static dynamic _jsonReviver(Object? key, Object? value) {
    if (value is double && value == value.toInt().toDouble()) {
      return value.toInt();
    }
    return value;
  }

  /// Generates the database by processing metadata, directories, and links.
  /// This is the main entry point for the database generation process.
  Future<void> generate() async {
    _log.info('Starting database generation...');
    _log.info('Source directory: $sourceDirectory');

    try {
      // Disable foreign keys for better performance
      _log.info('Disabling foreign keys for better performance...');
      await _disableForeignKeys();

      // Set maximum performance mode for bulk generation
      _log.info('Setting maximum performance mode for bulk generation');
      await repository.setMaxPerformanceMode();

      // Load metadata
      final metadata = await loadMetadata();
      _log.info('Metadata loaded: ${metadata.length} entries');

      // Load sources from files_manifest.json and upsert source table
      await _loadSourcesFromManifest();
      await _precreateSourceEntries();

      // Process hierarchy
      String libraryPath;
      if (path.basename(sourceDirectory) == 'אוצריא') {
        libraryPath = sourceDirectory;
      } else {
        libraryPath = path.join(sourceDirectory, 'אוצריא');
      }

      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) {
        throw StateError(
            'התיקייה "אוצריא" לא נמצאה. נא לבחור את התיקייה "אוצריא" או את התיקייה האב שלה.');
      }

      _libraryRoot = libraryPath;

      // Estimate total number of books for progress tracking
      _totalBooksToProcess = await _countTxtFiles(libraryPath);
      _log.info('Planned to process approximately $_totalBooksToProcess books');

      // Process priority books first (if any)
      try {
        await _processPriorityBooks(metadata);
      } catch (e) {
        _log.warning(
            'Failed processing priority list; continuing with full generation',
            e);
      }

      _log.info('🚀 Starting to process library directory: $libraryPath');
      // Preload all book contents into RAM
      await _preloadAllBookContents(libraryPath);
      await processDirectory(libraryPath, null, 0, metadata);

      // Process links
      await processLinks();

      // Build category closure table
      _log.info('Building category_closure (ancestor-descendant) table...');
      await repository.rebuildCategoryClosure();

      // Restore PRAGMAs
      _log.info('Re-enabling foreign keys...');
      await _enableForeignKeys();
      _log.info('Restoring normal performance mode');
      await repository.restoreNormalMode();

      _log.info('Generation completed successfully!');
      _log.info('📊 Performance Statistics:');
      _log.info('   Duplicate checks performed: $_duplicateChecks');
      _log.info('   Duplicates found: $_duplicatesFound');
      if (_duplicateChecks > 0) {
        final dupRate =
            (_duplicatesFound * 100 / _duplicateChecks).toStringAsFixed(1);
        _log.info('   Duplicate rate: $dupRate%');
      }
    } catch (e, stackTrace) {
      // Restore settings on error
      try {
        await _enableForeignKeys();
        await repository.restoreNormalMode();
      } catch (innerEx) {
        _log.warning(
            'Error restoring database settings after failure', innerEx);
      }

      _log.severe('Error during generation', e, stackTrace);
      rethrow;
    }
  }

  /// Loads book metadata from the metadata.json file.
  /// Attempts to parse the file in different formats (Map or List).
  ///
  /// Returns a map of book titles to their metadata
  Future<Map<String, BookMetadata>> loadMetadata() async {
    // Check if metadata.json is in sourceDirectory or in parent directory
    File metadataFile = File(path.join(sourceDirectory, 'metadata.json'));
    if (!await metadataFile.exists() &&
        path.basename(sourceDirectory) == 'אוצריא') {
      // If user selected "אוצריא" directory, look for metadata.json in parent
      metadataFile =
          File(path.join(path.dirname(sourceDirectory), 'metadata.json'));
    }

    if (!await metadataFile.exists()) {
      _log.warning('Metadata file metadata.json not found');
      return {};
    }

    final content = await metadataFile.readAsString();
    try {
      // Try to parse as Map first (original format)
      final metadataMap = _json.decode(content) as Map<String, dynamic>;
      _log.info('Parsed metadata as Map with ${metadataMap.length} entries');
      return metadataMap.map((key, value) =>
          MapEntry(key, BookMetadata.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      // If that fails, try to parse as List and convert to Map
      try {
        final metadataList = (_json.decode(content) as List<dynamic>)
            .map((item) => BookMetadata.fromJson(item as Map<String, dynamic>))
            .toList();
        _log.info(
            'Parsed metadata as List with ${metadataList.length} entries');
        // Convert list to map using title as key
        return {for (var item in metadataList) item.title: item};
      } catch (e) {
        _log.info('Failed to parse metadata.json', e);
        return {};
      }
    }
  }

  /// Processes a directory recursively, creating categories and books.
  ///
  /// [directory] The directory to process
  /// [parentCategoryId] The ID of the parent category, if any
  /// [level] The current level in the directory hierarchy
  /// [metadata] The metadata for books
  Future<void> processDirectory(
    String directory,
    int? parentCategoryId,
    int level,
    Map<String, BookMetadata> metadata,
  ) async {
    final dir = Directory(directory);
    final entities = await dir.list().toList();
    final sortedEntities = entities
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    for (final entity in sortedEntities) {
      if (entity is Directory) {
        final categoryId =
            await createCategory(entity.path, parentCategoryId, level);
        await processDirectory(entity.path, categoryId, level + 1, metadata);
      } else if (entity is File && path.extension(entity.path) == '.txt') {
        // Skip if already processed from priority list
        final key = _toLibraryRelativeKey(entity.path);
        if (_processedPriorityBookKeys.contains(key)) {
          continue;
        }

        // Skip companion notes files named 'הערות על <title>.txt'
        final filename = path.basename(entity.path);
        final titleNoExt = path.basenameWithoutExtension(filename);
        if (titleNoExt.startsWith('הערות על ')) {
          _log.info(
              '📝 Skipping notes file \'$filename\' (will be attached to base book if present)');
          continue;
        }

        if (parentCategoryId == null) {
          _log.warning('❌ Book found without category: ${entity.path}');
          continue;
        }
        _log.info(
            '📚 Processing book $filename with categoryId: $parentCategoryId');
        await createAndProcessBook(entity.path, parentCategoryId, metadata);
      } else {
        _log.fine(
            'Skipping entry: ${path.basename(entity.path)} (not a supported file type)');
      }
    }
    _log.info(
        '=== Finished processing directory: ${path.basename(directory)} ===');
  }

  /// Creates a category in the database.
  ///
  /// [path] The path representing the category
  /// [parentId] The ID of the parent category, if any
  /// [level] The level in the category hierarchy
  /// Returns the ID of the created category
  Future<int> createCategory(
    String categoryPath,
    int? parentId,
    int level,
  ) async {
    final title = path.basename(categoryPath);
    _log.info(
        '🏗️ Creating category: \'$title\' (level $level, parent: $parentId)');

    final category = Category(
      parentId: parentId,
      title: title,
      level: level,
    );

    final insertedId = await repository.insertCategory(category);
    _log.info('✅ Category \'$title\' created with ID: $insertedId');

    return insertedId;
  }

  /// Creates a book in the database and processes its content.
  ///
  /// [bookPath] The path to the book file
  /// [categoryId] The ID of the category the book belongs to
  /// [metadata] The metadata for the book
  /// [isBaseBook] Whether this is a base/priority book
  Future<void> createAndProcessBook(
    String bookPath,
    int categoryId,
    Map<String, BookMetadata> metadata, {
    bool isBaseBook = false,
  }) async {
    final filename = path.basename(bookPath);
    final title = path.basenameWithoutExtension(filename);
    final meta = metadata[title];
    _log.info('Processing book: $title with categoryId: $categoryId');

    // Apply source blacklist
    final srcName = _getSourceNameFor(bookPath);
    if (_sourceBlacklist.contains(srcName)) {
      _log.info('⛔ Skipping \'$title\' from blacklisted source \'$srcName\'');
      _processedBooksCount++;
      final pct = _totalBooksToProcess > 0
          ? (_processedBooksCount * 100 ~/ _totalBooksToProcess)
          : 0;
      _log.info(
          'Books progress: $_processedBooksCount/$_totalBooksToProcess ($pct%)');
      return;
    }

    // Check for duplicates (for performance measurement)
    _duplicateChecks++;
    final existingBook = await repository.checkBookExists(title);
    if (existingBook != null) {
      _duplicatesFound++;

      // Call the callback if provided
      if (onDuplicateBook != null) {
        final shouldReplace = await onDuplicateBook!(title);
        if (!shouldReplace) {
          _processedBooksCount++;
          return;
        }
        // Delete the existing book and continue with insertion
        await repository.deleteBookCompletely(existingBook.id);
      } else {
        // Default behavior: skip duplicates
        _processedBooksCount++;
        return;
      }
    }

    // Assign a unique ID to this book
    final currentBookId = _nextBookId++;
    _log.fine(
        'Assigning ID $currentBookId to book \'$title\' with categoryId: $categoryId');

    // Create author list if author is available in metadata
    final authors =
        meta?.author != null ? [Author(name: meta!.author!)] : <Author>[];

    // Create publication places list if pubPlace is available in metadata
    final pubPlaces = meta?.pubPlace != null
        ? [PubPlace(name: meta!.pubPlace!)]
        : <PubPlace>[];

    // Create publication dates list if pubDate is available in metadata
    final pubDates =
        meta?.pubDate != null ? [PubDate(date: meta!.pubDate!)] : <PubDate>[];

    // Detect companion notes file named 'הערות על <title>.txt' in the same directory
    String? notesContent;
    try {
      final dir = Directory(path.dirname(bookPath));
      final notesTitle = 'הערות על $title';
      final candidate = path.join(dir.path, '$notesTitle.txt');
      final candidateFile = File(candidate);
      if (await candidateFile.exists()) {
        // Prefer preloaded cache if available
        final key = _toLibraryRelativeKey(candidate);
        final lines = _bookContentCache[key];
        notesContent = lines != null
            ? lines.join('\n')
            : await candidateFile.readAsString();
      }
    } catch (e) {
      // Ignore errors reading notes
    }

    final sourceId = await _resolveSourceIdFor(bookPath);
    final book = Book(
      id: currentBookId,
      categoryId: categoryId,
      sourceId: sourceId,
      title: title,
      authors: authors,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
      heShortDesc: meta?.heShortDesc,
      notesContent: notesContent,
      order: meta?.order ?? 999.0,
      topics: extractTopics(bookPath),
      isBaseBook: isBaseBook,
    );

    _log.fine(
        'Inserting book \'${book.title}\' with ID: ${book.id} and categoryId: ${book.categoryId}');
    final insertedBookId = await repository.insertBook(book);

    // ✅ Important verification: ensure that ID and categoryId are correct
    final insertedBook = await repository.getBook(insertedBookId);
    if (insertedBook?.categoryId != categoryId) {
      _log.warning(
          'WARNING: Book inserted with wrong categoryId! Expected: $categoryId, Got: ${insertedBook?.categoryId}');
      // Correct the categoryId if necessary
      await repository.updateBookCategoryId(insertedBookId, categoryId);
    }
    _log.fine(
        'Book \'${book.title}\' inserted with ID: $insertedBookId and categoryId: $categoryId');

    // Insert acronyms for this book
    try {
      final terms = await fetchAcronymsForTitle(title);
      if (terms.isNotEmpty) {
        await repository.bulkInsertBookAcronyms(insertedBookId, terms);
        _log.info('Inserted ${terms.length} acronyms for \'$title\'');
      }
    } catch (e) {
      _log.warning('Failed to insert acronyms for \'$title\'', e);
    }

    // Process content of the book
    await processBookContent(bookPath, insertedBookId);

    // Book-level progress
    _processedBooksCount++;
    final pct = _totalBooksToProcess > 0
        ? (_processedBooksCount * 100 ~/ _totalBooksToProcess)
        : 0;
    _log.info(
        'Books progress: $_processedBooksCount/$_totalBooksToProcess ($pct%)');
  }

  /// Processes the content of a book, extracting lines and TOC entries.
  ///
  /// [bookPath] The path to the book file
  /// [bookId] The ID of the book in the database
  Future<void> processBookContent(String bookPath, int bookId) async {
    _log.fine('Processing content for book ID: $bookId');
    _log.info(
        'Processing content of book ID: $bookId (ID generated by the database)');

    // Prefer preloaded content from RAM if available
    final key = _toLibraryRelativeKey(bookPath);
    final lines = _bookContentCache[key] ?? await _readBookLines(bookPath);
    _log.info('Number of lines: ${lines.length}');

    // Process each line one by one, handling TOC entries as we go
    await processLinesWithTocEntries(bookId, lines);

    // Update the total number of lines
    await repository.updateBookTotalLines(bookId, lines.length);

    _log.info(
        'Content processed successfully for book ID: $bookId (ID generated by the database)');
  }

  /// Reads book lines from file
  Future<List<String>> _readBookLines(String bookPath) async {
    final file = File(bookPath);
    final content = await file.readAsString(encoding: utf8);
    return content.split('\n');
  }

  /// Processes lines of a book, identifying and creating TOC entries.
  /// OPTIMIZED: Uses batch inserts for maximum performance
  ///
  /// [bookId] The ID of the book in the database
  /// [lines] The lines of the book content
  Future<void> processLinesWithTocEntries(
      int bookId, List<String> lines) async {
    _log.fine('Processing lines and TOC entries for book ID: $bookId');

    // Data structures for TOC processing
    final allTocEntries = <TocEntryData>[];
    final parentStack = <int, int>{};
    final entriesByParent = <int?, List<int>>{};
    int? currentOwningTocEntryId;

    // Batch buffers
    final linesBatch = <Line>[];
    final tocEntriesBatch = <TocEntry>[];
    final lineTocBuffer = <({int lineId, int tocId})>[];
    final tocUpdates = <({int tocId, int lineId})>[];

    const batchSize = 1000;

    // First pass - collect all data
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final plainText = cleanHtml(line);
      final level = detectHeaderLevel(line);

      if (level > 0) {
        if (plainText.trim().isEmpty) {
          _log.fine(
              '⚠️ Skipping empty header at level $level (line $lineIndex)');
          parentStack.remove(level);
          continue;
        }

        int? parentId;
        for (int l = level - 1; l >= 1; l--) {
          if (parentStack.containsKey(l)) {
            parentId = parentStack[l];
            break;
          }
        }

        final currentTocEntryId = _nextTocEntryId++;
        final currentLineId = _nextLineId++;

        // Store TOC entry info
        allTocEntries.add(TocEntryData(
          id: currentTocEntryId,
          parentId: parentId,
          level: level,
          text: plainText,
          lineIndex: lineIndex,
        ));

        // Buffer TOC entry
        tocEntriesBatch.add(TocEntry(
          id: currentTocEntryId,
          bookId: bookId,
          parentId: parentId,
          text: plainText,
          level: level,
          lineId: null,
          isLastChild: false,
          hasChildren: false,
        ));

        parentStack[level] = currentTocEntryId;
        entriesByParent.putIfAbsent(parentId, () => []).add(currentTocEntryId);
        currentOwningTocEntryId = currentTocEntryId;

        // Buffer line
        linesBatch.add(Line(
          id: currentLineId,
          bookId: bookId,
          lineIndex: lineIndex,
          content: line,
        ));

        // Store update for later
        tocUpdates.add((tocId: currentTocEntryId, lineId: currentLineId));

        // Buffer line-toc mapping
        lineTocBuffer.add((lineId: currentLineId, tocId: currentTocEntryId));
      } else {
        // Regular line
        final currentLineId = _nextLineId++;

        linesBatch.add(Line(
          id: currentLineId,
          bookId: bookId,
          lineIndex: lineIndex,
          content: line,
        ));

        // Buffer mapping for regular line if there is a current owner
        if (currentOwningTocEntryId != null) {
          lineTocBuffer
              .add((lineId: currentLineId, tocId: currentOwningTocEntryId));
        }
      }

      // Flush batches when they reach size limit
      if (linesBatch.length >= batchSize) {
        await repository.insertLinesBatch(linesBatch);
        linesBatch.clear();
      }
      if (tocEntriesBatch.length >= batchSize) {
        await repository.insertTocEntriesBatch(tocEntriesBatch);
        tocEntriesBatch.clear();
      }

      if (lineIndex % 1000 == 0) {
        final pct = lines.isNotEmpty ? (lineIndex * 100 ~/ lines.length) : 0;
        _log.info('Book $bookId: $lineIndex/${lines.length} lines ($pct%)');
      }
    }

    // Flush remaining batches
    if (linesBatch.isNotEmpty) {
      await repository.insertLinesBatch(linesBatch);
    }
    if (tocEntriesBatch.isNotEmpty) {
      await repository.insertTocEntriesBatch(tocEntriesBatch);
    }
    if (lineTocBuffer.isNotEmpty) {
      await repository.bulkUpsertLineToc(lineTocBuffer);
    }

    // Update TOC entries with their line IDs in batch
    if (tocUpdates.isNotEmpty) {
      await repository.bulkUpdateTocEntryLineIds(tocUpdates);
    }

    // Second pass: Update isLastChild and hasChildren in batch
    _log.fine('Updating isLastChild and hasChildren for book ID: $bookId');

    final parentIds =
        allTocEntries.map((e) => e.parentId).whereType<int>().toSet();

    // Collect IDs to update
    final hasChildrenIds = allTocEntries
        .where((e) => parentIds.contains(e.id))
        .map((e) => e.id)
        .toList();
    final lastChildIds = entriesByParent.values
        .where((children) => children.isNotEmpty)
        .map((children) => children.last)
        .toList();

    // Batch update
    if (hasChildrenIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryHasChildren(hasChildrenIds, true);
    }
    if (lastChildIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryIsLastChild(lastChildIds, true);
    }

    _log.info(
        '✅ Finished processing lines and TOC entries for book ID: $bookId');
    _log.info('   Total TOC entries: ${allTocEntries.length}');
    _log.info('   Entries with children: ${parentIds.length}');
  }

  /// Loads all books into cache for faster link processing
  Future<void> _loadBooksCache() async {
    _log.info('Loading books cache...');
    final books = await repository.getAllBooks();
    for (final book in books) {
      _bookTitleToId[book.title] = book.id;
    }
    _log.info('Loaded ${_bookTitleToId.length} books to cache');
  }

  /// Loads all lines of a book into cache
  Future<void> _loadBookLinesCache(int bookId) async {
    if (_bookLineIndexToId.containsKey(bookId)) return;

    _log.fine('Loading lines cache for book $bookId...');
    final book = await repository.getBook(bookId);
    final totalLines = book?.totalLines ?? 0;
    final arr = List<int>.filled(totalLines, 0);

    if (totalLines > 0) {
      final lines = await repository.getLines(bookId, 0, totalLines - 1);
      for (final ln in lines) {
        final idx = ln.lineIndex;
        if (idx >= 0 && idx < arr.length) {
          arr[idx] = ln.id;
        }
      }
    }

    _bookLineIndexToId[bookId] = arr;
    _log.fine(
        'Loaded ${arr.length} line id/index pairs for book $bookId into memory');
  }

  /// Processes all link files in the links directory.
  /// Links connect lines between different books.
  Future<void> processLinks() async {
    // Check if links directory is in sourceDirectory or in parent directory
    Directory linksDir = Directory(path.join(sourceDirectory, 'links'));
    if (!await linksDir.exists() &&
        path.basename(sourceDirectory) == 'אוצריא') {
      // If user selected "אוצריא" directory, look for links in parent
      linksDir = Directory(path.join(path.dirname(sourceDirectory), 'links'));
    }

    if (!await linksDir.exists()) {
      _log.warning('Links directory not found');
      return;
    }

    // Load all books into cache for faster processing
    await _loadBooksCache();

    // Count links before processing
    final linksBefore = await repository.countLinks();
    _log.fine('Links in database before processing: $linksBefore');

    _log.info('Processing links...');
    var totalLinks = 0;

    await for (final entity in linksDir.list()) {
      if (entity is File && path.extension(entity.path) == '.json') {
        final processedLinks = await processLinkFile(entity.path);
        totalLinks += processedLinks;
        _log.fine(
            'Processed $processedLinks links from ${path.basename(entity.path)}, total so far: $totalLinks');
      }
    }

    // Count links after processing
    final linksAfter = await repository.countLinks();
    _log.fine('Links in database after processing: $linksAfter');
    _log.fine('Added ${linksAfter - linksBefore} links to the database');

    _log.info('Total of $totalLinks links processed');

    // Update the book_has_links table
    await updateBookHasLinksTable();
  }

  /// Processes a single link file, creating links between books.
  /// OPTIMIZED: Uses caching and batch inserts for better performance
  ///
  /// [linkFile] The path to the link file
  /// Returns the number of links successfully processed
  Future<int> processLinkFile(String linkFile) async {
    final bookTitle = path
        .basenameWithoutExtension(path.basename(linkFile))
        .replaceAll('_links', '');
    _log.fine('Processing link file for book: $bookTitle');

    // Use cache instead of query
    final sourceBookId = _bookTitleToId[bookTitle];
    if (sourceBookId == null) {
      _log.warning('Source book not found for links: $bookTitle');
      return 0;
    }
    _log.fine('Found source book with ID: $sourceBookId (from cache)');

    // Load lines cache for source book
    await _loadBookLinesCache(sourceBookId);

    try {
      final file = File(linkFile);
      final content = await file.readAsString();
      _log.fine('Link file content length: ${content.length}');
      final links = (_json.decode(content) as List<dynamic>)
          .map((item) => LinkData.fromJson(item as Map<String, dynamic>))
          .toList();
      _log.fine('Decoded ${links.length} links from file');

      // Prepare batch of links
      final linksToInsert = <Link>[];
      var skipped = 0;

      for (var index = 0; index < links.length; index++) {
        final linkData = links[index];
        try {
          // Handle paths with backslashes
          final pathStr = linkData.path2;
          final targetTitle = pathStr.contains('\\')
              ? pathStr.split('\\').last.replaceAll(RegExp(r'\.[^.]*$'), '')
              : path.basenameWithoutExtension(pathStr);

          // Use cache instead of query
          final targetBookId = _bookTitleToId[targetTitle];
          if (targetBookId == null) {
            _log.fine('Target book not found: $targetTitle');
            skipped++;
            continue;
          }

          // Load lines cache for target book
          await _loadBookLinesCache(targetBookId);

          // Adjust indices from 1-based to 0-based
          final sourceLineIndex = (linkData.lineIndex1.toInt() - 1)
              .clamp(0, double.infinity)
              .toInt();
          final targetLineIndex = (linkData.lineIndex2.toInt() - 1)
              .clamp(0, double.infinity)
              .toInt();

          // Use cache instead of queries
          final sourceLineArr = _bookLineIndexToId[sourceBookId];
          final targetLineArr = _bookLineIndexToId[targetBookId];

          final sourceLineId = (sourceLineArr != null &&
                  sourceLineIndex >= 0 &&
                  sourceLineIndex < sourceLineArr.length)
              ? (sourceLineArr[sourceLineIndex] != 0
                  ? sourceLineArr[sourceLineIndex]
                  : null)
              : null;
          final targetLineId = (targetLineArr != null &&
                  targetLineIndex >= 0 &&
                  targetLineIndex < targetLineArr.length)
              ? (targetLineArr[targetLineIndex] != 0
                  ? targetLineArr[targetLineIndex]
                  : null)
              : null;

          if (sourceLineId == null || targetLineId == null) {
            _log.fine(
                'Line not found - source: $sourceLineIndex, target: $targetLineIndex');
            skipped++;
            continue;
          }

          linksToInsert.add(Link(
            sourceBookId: sourceBookId,
            targetBookId: targetBookId,
            sourceLineId: sourceLineId,
            targetLineId: targetLineId,
            connectionType: ConnectionType.fromString(linkData.connectionType),
          ));

          // Insert in batches of 1000
          if (linksToInsert.length >= 1000) {
            await repository.insertLinksBatch(linksToInsert);
            _log.fine('Batch inserted ${linksToInsert.length} links');
            linksToInsert.clear();
          }
        } catch (e) {
          _log.fine('Error processing link: ${linkData.heRef2}', e);
          skipped++;
        }
      }

      // Insert remaining links
      if (linksToInsert.isNotEmpty) {
        await repository.insertLinksBatch(linksToInsert);
        _log.fine('Batch inserted ${linksToInsert.length} links');
      }

      final processed = links.length - skipped;
      _log.fine(
          'Processed $processed links out of ${links.length} (skipped: $skipped)');
      return processed;
    } catch (e, stackTrace) {
      _log.warning('Error processing link file: ${path.basename(linkFile)}', e,
          stackTrace);
      return 0;
    }
  }

  /// Extracts topics from the file path.
  /// Topics are derived from the directory structure.
  ///
  /// [path] The path to the book file
  /// Returns a list of topics extracted from the path
  List<Topic> extractTopics(String bookPath) {
    // Extract topics from the path
    final parts = path.split(bookPath);
    final topicNames = parts
        .take(parts.length - 1)
        .toList()
        .reversed
        .take(2)
        .toList()
        .reversed;

    return topicNames.map((name) => Topic(name: name)).toList();
  }

  /// Updates the book_has_links table to indicate which books have source links, target links, or both.
  /// This should be called after all links have been processed.
  Future<void> updateBookHasLinksTable() async {
    // שליפת כל סוגי ההקשרים מטבלת connection_type
    final connectionTypes = await repository.getAllConnectionTypesObj();
    final connectionTypeMap = <String, int>{};
    for (final type in connectionTypes) {
      connectionTypeMap[type.name.toUpperCase()] = type.id;
    }

    // Get all books
    final books = await repository.getAllBooks();

    var booksWithSourceLinks = 0;
    var booksWithTargetLinks = 0;
    var booksWithAnyLinks = 0;
    var processedBooks = 0;

    // For each book, check if it has source links and/or target links
    for (final book in books) {
      // Check if the book has any links as source
      final hasSourceLinks =
          await repository.countLinksBySourceBook(book.id) > 0;

      // Check if the book has any links as target
      final hasTargetLinks =
          await repository.countLinksByTargetBook(book.id) > 0;

      // Update the book_has_links table with separate flags for source and target links
      await repository.updateBookHasLinks(
          book.id, hasSourceLinks, hasTargetLinks);

      // Additionally: compute per-connection-type flags across source and target, then update book row
      final targumId = connectionTypeMap['TARGUM'];
      final referenceId = connectionTypeMap['REFERENCE'];
      final commentaryId = connectionTypeMap['COMMENTARY'];
      final otherId = connectionTypeMap['OTHER'];

      final targumCount = (targumId != null
              ? await repository.countLinksBySourceBookAndTypeId(
                  book.id, targumId)
              : 0) +
          (targumId != null
              ? await repository.countLinksByTargetBookAndTypeId(
                  book.id, targumId)
              : 0);
      final referenceCount = (referenceId != null
              ? await repository.countLinksBySourceBookAndTypeId(
                  book.id, referenceId)
              : 0) +
          (referenceId != null
              ? await repository.countLinksByTargetBookAndTypeId(
                  book.id, referenceId)
              : 0);
      final commentaryCount = (commentaryId != null
              ? await repository.countLinksBySourceBookAndTypeId(
                  book.id, commentaryId)
              : 0) +
          (commentaryId != null
              ? await repository.countLinksByTargetBookAndTypeId(
                  book.id, commentaryId)
              : 0);
      final otherCount = (otherId != null
              ? await repository.countLinksBySourceBookAndTypeId(
                  book.id, otherId)
              : 0) +
          (otherId != null
              ? await repository.countLinksByTargetBookAndTypeId(
                  book.id, otherId)
              : 0);

      final hasTargum = targumCount > 0;
      final hasReference = referenceCount > 0;
      final hasCommentary = commentaryCount > 0;
      final hasOther = otherCount > 0;

      await repository.updateBookConnectionFlags(
          book.id, hasTargum, hasReference, hasCommentary, hasOther);

      // Update counters
      if (hasSourceLinks) booksWithSourceLinks++;
      if (hasTargetLinks) booksWithTargetLinks++;
      if (hasSourceLinks || hasTargetLinks) booksWithAnyLinks++;
      processedBooks++;

      // Log progress every 100 books
      if (processedBooks % 100 == 0) {
        _log.fine('Processed $processedBooks/${books.length} books: '
            '$booksWithSourceLinks with source links, '
            '$booksWithTargetLinks with target links, '
            '$booksWithAnyLinks with any links');
      }
    }

    _log.info('Book_has_links table updated. Found:');
    _log.info('- $booksWithSourceLinks books with source links');
    _log.info('- $booksWithTargetLinks books with target links');
    _log.info('- $booksWithAnyLinks books with any links (source or target)');
    _log.info('- ${books.length} total books');
  }

  /// Helper methods for source management and priority processing

  /// Loads files_manifest.json and builds mapping from library-relative path to source name
  Future<void> _loadSourcesFromManifest() async {
    _manifestSourcesByRel.clear();
    final primary = File(path.join(sourceDirectory, 'files_manifest.json'));
    final fallback = File('otzaria-library/files_manifest.json');
    final manifestFile = await primary.exists()
        ? primary
        : (await fallback.exists() ? fallback : null);

    if (manifestFile == null) {
      _log.warning(
          'files_manifest.json not found; assigning source \'Unknown\' to all books');
      return;
    }

    try {
      final content = await manifestFile.readAsString();
      final map = _json.decode(content) as Map<String, dynamic>;

      for (final entry in map.entries) {
        final pathStr = entry.key;
        final parts = pathStr.split('/');
        if (parts.isEmpty) continue;

        final sourceName = parts.first;
        final idx = parts.indexOf('אוצריא');
        if (idx < 0 || idx == parts.length - 1) continue;

        final rel = parts.skip(idx + 1).join('/');
        final prev = _manifestSourcesByRel.putIfAbsent(rel, () => sourceName);
        if (prev != sourceName) {
          _log.warning(
              'Duplicate source mapping for \'$rel\': existing=$prev new=$sourceName; keeping existing');
        }
      }
      _log.info(
          'Loaded ${_manifestSourcesByRel.length} book→source mappings from manifest');
    } catch (e) {
      _log.warning(
          'Failed to parse files_manifest.json; sources will be \'Unknown\'',
          e);
    }
  }

  /// Ensure all known source names from manifest are present in DB
  Future<void> _precreateSourceEntries() async {
    // Always ensure 'Unknown' exists
    final unknownId = await repository.insertSource('Unknown');
    _sourceNameToId['Unknown'] = unknownId;

    // Insert all discovered sources
    final uniqueSources = _manifestSourcesByRel.values.toSet();
    for (final name in uniqueSources) {
      final id = await repository.insertSource(name);
      _sourceNameToId[name] = id;
    }
    _log.info('Prepared ${_sourceNameToId.length} sources in DB');
  }

  /// Compute a normalized key for a book file relative to the library root
  String _toLibraryRelativeKey(String filePath) {
    try {
      final rel =
          path.relative(filePath, from: _libraryRoot).replaceAll('\\', '/');
      return rel;
    } catch (e) {
      return path.basename(filePath);
    }
  }

  /// Resolve a source id for a book file using the manifest mapping
  Future<int> _resolveSourceIdFor(String filePath) async {
    final rel = _toLibraryRelativeKey(filePath);
    final sourceName = _manifestSourcesByRel[rel] ?? 'Unknown';
    final cached = _sourceNameToId[sourceName];
    if (cached != null) return cached;
    final id = await repository.insertSource(sourceName);
    _sourceNameToId[sourceName] = id;
    return id;
  }

  String _getSourceNameFor(String filePath) {
    final rel = _toLibraryRelativeKey(filePath);
    return _manifestSourcesByRel[rel] ?? 'Unknown';
  }

  /// Count txt files in directory for progress tracking
  Future<int> _countTxtFiles(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      var count = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.extension(entity.path) == '.txt') {
          final filename = path.basename(entity.path);
          final titleNoExt = path.basenameWithoutExtension(filename);
          if (!titleNoExt.startsWith('הערות על ')) {
            count++;
          }
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Preload all book file contents into RAM
  Future<void> _preloadAllBookContents(String libraryPath) async {
    if (_bookContentCache.isNotEmpty) return;
    _log.info('Preloading book contents into RAM from $libraryPath ...');

    final files = <String>[];
    final notesFiles = <String>[];
    final dir = Directory(libraryPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && path.extension(entity.path) == '.txt') {
        final filename = path.basename(entity.path);
        final titleNoExt = path.basenameWithoutExtension(filename);

        // Separate notes files from regular books
        if (titleNoExt.startsWith('הערות על ')) {
          notesFiles.add(entity.path);
          continue;
        }

        final rel = _toLibraryRelativeKey(entity.path);
        final src = _manifestSourcesByRel[rel] ?? 'Unknown';
        if (_sourceBlacklist.contains(src)) {
          _log.fine('Skipping preload for blacklisted source \'$src\': $rel');
          continue;
        }
        files.add(entity.path);
      }
    }

    _log.info(
        'Found ${files.length} books and ${notesFiles.length} notes files to preload');

    // Preload regular books
    for (final filePath in files) {
      try {
        final key = _toLibraryRelativeKey(filePath);
        final content = await File(filePath).readAsString();
        _bookContentCache[key] = content.split('\n');
      } catch (e) {
        _log.warning('Failed to preload $filePath', e);
      }
    }

    // Preload notes files (for faster notesContent loading)
    for (final filePath in notesFiles) {
      try {
        final key = _toLibraryRelativeKey(filePath);
        final content = await File(filePath).readAsString();
        _bookContentCache[key] = content.split('\n');
      } catch (e) {
        _log.warning('Failed to preload notes file $filePath', e);
      }
    }

    _log.info(
        'Preloaded ${_bookContentCache.length} files into RAM (${files.length} books + ${notesFiles.length} notes)');
  }

  /// Process priority books first
  Future<void> _processPriorityBooks(Map<String, BookMetadata> metadata) async {
    final entries = await _loadPriorityList();
    if (entries.isEmpty) {
      _log.info('No priority entries found');
      return;
    }

    _log.info('Processing ${entries.length} priority entries first');

    for (var idx = 0; idx < entries.length; idx++) {
      final relative = entries[idx];
      final parts = relative.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) continue;

      final categories =
          parts.length > 1 ? parts.sublist(0, parts.length - 1) : <String>[];
      final bookFileName = parts.last;

      // Skip notes-only entries
      if (path.basenameWithoutExtension(bookFileName).startsWith('הערות על ')) {
        _log.info('⏭️ Skipping notes file in priority list: $bookFileName');
        continue;
      }

      // Build filesystem path
      var currentPath = _libraryRoot;
      for (final cat in categories) {
        currentPath = path.join(currentPath, cat);
      }
      final bookPath = path.join(currentPath, bookFileName);

      if (!await File(bookPath).exists()) {
        _log.warning(
            'Priority entry ${idx + 1}/${entries.length}: file not found: $bookPath');
        continue;
      }

      // Avoid duplicates
      final key = _toLibraryRelativeKey(bookPath);
      if (_processedPriorityBookKeys.contains(key)) {
        _log.fine(
            'Priority entry ${idx + 1}/${entries.length}: already processed (dup in list): $key');
        continue;
      }

      // Ensure categories exist
      int? parentId;
      var level = 0;
      var catPath = _libraryRoot;
      for (final cat in categories) {
        catPath = path.join(catPath, cat);
        parentId = await createCategory(catPath, parentId, level);
        level++;
      }

      if (parentId == null) {
        _log.warning(
            'Priority entry ${idx + 1}/${entries.length}: missing parent category for $bookPath; skipping');
        continue;
      }

      _log.info(
          '⭐ Priority ${idx + 1}/${entries.length}: processing $bookFileName under categories ${categories.join("/")}');
      await createAndProcessBook(bookPath, parentId, metadata,
          isBaseBook: true);

      _processedPriorityBookKeys.add(key);
    }
  }

  /// Load priority list from resources
  /// Reads the priority list from file and returns normalized relative paths under the library root.
  Future<List<String>> _loadPriorityList() async {
    try {
      // priority.txt is typically in the parent directory of sourceDirectory
      final priorityPath =
          path.join(path.dirname(sourceDirectory), 'priority.txt');
      final priorityFile = File(priorityPath);

      if (!await priorityFile.exists()) {
        _log.fine('priority.txt not found at $priorityPath');
        return [];
      }

      _log.info('Loading priority list from: ${priorityFile.path}');

      final content = await priorityFile.readAsString(encoding: utf8);
      final lines = content.split('\n');

      final result = <String>[];
      for (var line in lines) {
        var s = line.trim();

        // Skip empty lines and comments
        if (s.isEmpty || s.startsWith('#')) continue;

        // Normalize separators
        s = s.replaceAll('\\', '/');

        // Remove BOM if present
        if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
          s = s.substring(1);
        }

        // Remove leading slash
        if (s.startsWith('/')) {
          s = s.substring(1);
        }

        // Try to start from 'אוצריא' if present
        final idx = s.indexOf('אוצריא');
        if (idx >= 0) {
          s = s.substring(idx + 'אוצריא'.length);
          if (s.startsWith('/')) {
            s = s.substring(1);
          }
        }

        // Filter for .txt files
        if (s.toLowerCase().endsWith('.txt')) {
          result.add(s);
        }
      }

      _log.info(
          'Loaded ${result.length} priority entries from ${priorityFile.path}');
      return result;
    } catch (e) {
      _log.warning('Unable to read priority.txt', e);
      return [];
    }
  }

  /// Disables foreign key constraints
  Future<void> _disableForeignKeys() async {
    _log.fine('Disabling foreign key constraints');
    await repository.executeRawQuery('PRAGMA foreign_keys = OFF');
  }

  /// Re-enables foreign key constraints
  Future<void> _enableForeignKeys() async {
    _log.fine('Re-enabling foreign key constraints');
    await repository.executeRawQuery('PRAGMA foreign_keys = ON');
  }

  /// Sanitizes an acronym term by removing diacritics, maqaf, gershayim and geresh.
  ///
  /// [raw] The raw acronym term to sanitize.
  /// Returns the sanitized term.
  String sanitizeAcronymTerm(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    s = hebrew_text_utils.removeAllDiacritics(s);
    s = hebrew_text_utils.replaceMaqaf(s, replacement: ' ');
    s = s.replaceAll('\u05F4', ''); // remove Hebrew gershayim (״)
    s = s.replaceAll('\u05F3', ''); // remove Hebrew geresh (׳)
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }

  /// Fetches and sanitizes acronym terms for a given book title from acronym.json.
  ///
  /// The acronym.json file is expected to be in the parent directory of [sourceDirectory].
  /// [title] The book title to look up.
  /// Returns a list of sanitized acronym terms, or empty list if not found.
  Future<List<String>> fetchAcronymsForTitle(String title) async {
    // Determine the path to acronym.json (in parent of sourceDirectory)
    final acronymPath =
        path.join(path.dirname(sourceDirectory), 'acronym.json');

    try {
      // Load acronym data if not already cached
      if (_acronymData == null) {
        final file = File(acronymPath);
        if (!await file.exists()) {
          _log.fine('acronym.json not found at $acronymPath');
          return [];
        }

        final content = await file.readAsString();
        final decoded = _json.decode(content);

        // Handle both Map and List formats
        if (decoded is Map<String, dynamic>) {
          _acronymData = decoded;
        } else if (decoded is List) {
          // Convert list to map using 'title' field as key
          _acronymData = <String, dynamic>{};
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final itemTitle = item['book_title'] as String?;
              if (itemTitle != null) {
                _acronymData![itemTitle] = item;
              }
            }
          }
        } else {
          _log.warning('Unexpected acronym.json format');
          _acronymData = <String, dynamic>{};
        }
        _log.info('Loaded acronym data with ${_acronymData!.length} entries');
      }

      // Look up the title in the acronym data
      final entry = _acronymData![title];
      if (entry == null) {
        return [];
      }

      // Extract terms - handle both string and list formats
      String? raw;
      if (entry is String) {
        raw = entry;
      } else if (entry is Map<String, dynamic>) {
        raw = entry['terms'] as String?;
      } else if (entry is List) {
        // If it's already a list, process each item
        final parts = entry.map((e) => e.toString()).toList();
        final clean = parts
            .map((t) => sanitizeAcronymTerm(t))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final titleNormalized = sanitizeAcronymTerm(title);
        return clean
            .where((t) => !t.toLowerCase().contains(title.toLowerCase()))
            .where(
                (t) => !t.toLowerCase().contains(titleNormalized.toLowerCase()))
            .toSet()
            .toList();
      }

      if (raw == null || raw.isEmpty) {
        return [];
      }

      // Split by comma and sanitize each term
      final parts = raw.split(',');
      final clean = parts
          .map((t) => sanitizeAcronymTerm(t))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // De-duplicate and drop items identical to the title after normalization
      final titleNormalized = sanitizeAcronymTerm(title);
      return clean
          .where((t) => !t.toLowerCase().contains(title.toLowerCase()))
          .where(
              (t) => !t.toLowerCase().contains(titleNormalized.toLowerCase()))
          .toSet()
          .toList();
    } catch (e) {
      _log.warning(
          'Error reading acronyms for \'$title\' from $acronymPath', e);
      return [];
    }
  }
}

/// Data class representing a link between two books.
/// Used for deserializing link data from JSON files.
class LinkData {
  final String heRef2;
  final double lineIndex1;
  final String path2;
  final double lineIndex2;
  final String connectionType;

  const LinkData({
    required this.heRef2,
    required this.lineIndex1,
    required this.path2,
    required this.lineIndex2,
    this.connectionType = '',
  });

  factory LinkData.fromJson(Map<String, dynamic> json) {
    return LinkData(
      heRef2: json['heRef_2'] as String,
      lineIndex1: (json['line_index_1'] as num).toDouble(),
      path2: json['path_2'] as String,
      lineIndex2: (json['line_index_2'] as num).toDouble(),
      connectionType: json['Conection Type'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'heRef_2': heRef2,
      'line_index_1': lineIndex1,
      'path_2': path2,
      'line_index_2': lineIndex2,
      'Conection Type': connectionType,
    };
  }
}

/// Structure to store TOC entry data during processing
class TocEntryData {
  final int id;
  final int? parentId;
  final int level;
  final String text;
  final int lineIndex;

  const TocEntryData({
    required this.id,
    this.parentId,
    required this.level,
    required this.text,
    required this.lineIndex,
  });
}

/// Utility functions for HTML and text processing
String cleanHtml(String html) {
  // Simple HTML tag removal - replace with space to avoid concatenating words
  final tagRegex = RegExp(r'<[^>]*>');
  final cleaned = html.replaceAll(tagRegex, ' ');
  // Clean up multiple spaces and trim
  return hebrew_text_utils.removeNikud(
    cleaned.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

int detectHeaderLevel(String line) {
  final lowerLine = line.toLowerCase();
  if (lowerLine.startsWith('<h1')) return 1;
  if (lowerLine.startsWith('<h2')) return 2;
  if (lowerLine.startsWith('<h3')) return 3;
  if (lowerLine.startsWith('<h4')) return 4;
  if (lowerLine.startsWith('<h5')) return 5;
  if (lowerLine.startsWith('<h6')) return 6;
  return 0;
}
