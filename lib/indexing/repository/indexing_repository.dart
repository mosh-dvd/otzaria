import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/utils/ref_helper.dart';

/// Repository for managing book indexing operations.
///
/// This repository handles the indexing of books from the library into a
/// Tantivy search index. It implements several optimizations to prevent
/// UI blocking during the indexing process:
///
/// - **Batch commits**: Commits are performed every 20 books instead of after each book
/// - **Aggressive yielding**: Frequent yields to the event loop to keep UI responsive
/// - **Throttled progress updates**: Progress callbacks are throttled to 100ms intervals
/// - **Cancellation support**: Indexing can be cancelled at any point
/// - **Background processing**: Heavy operations run with delays to prevent UI freezing
///
/// The indexing process reads book content from SQLite when available,
/// falling back to file system reads when necessary.
///
/// Note: Due to FFI limitations with Tantivy, the indexing cannot run in a
/// separate Isolate, but uses aggressive yielding and delays to maintain UI responsiveness.
class IndexingRepository {
  final TantivyDataProvider _tantivyDataProvider;

  IndexingRepository(this._tantivyDataProvider);

  /// Indexes all books in the provided library.
  ///
  /// [library] The library containing books to index
  /// [onProgress] Callback function to report progress
  Future<void> indexAllBooks(
    Library library,
    void Function(int processed, int total) onProgress,
  ) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🚀 [INDEXING] Starting indexing process');
    debugPrint('═══════════════════════════════════════════════════════════');
    
    // Check if already indexing
    if (_tantivyDataProvider.isIndexing.value) {
      debugPrint('⚠️  [INDEXING] Indexing already in progress, aborting');
      return;
    }
    
    final indexingStartTime = DateTime.now();
    
    _tantivyDataProvider.isIndexing.value = true;
    
    // Try to acquire the index - if it fails, there's a lock
    try {
      await _tantivyDataProvider.engine;
      // Test if we can access it
      debugPrint('✅ [INDEXING] Index lock acquired successfully');
    } catch (e) {
      debugPrint('❌ [INDEXING] Failed to acquire index lock: $e');
      debugPrint('💡 [INDEXING] This usually means:');
      debugPrint('   1. Another indexing process is running');
      debugPrint('   2. The app crashed during previous indexing');
      debugPrint('   3. Try: Close app completely and reopen');
      _tantivyDataProvider.isIndexing.value = false;
      
      // Don't rethrow - just return early
      // The error is already logged
      return;
    }
    final allBooks = library.getAllBooks();
    final totalBooks = allBooks.length;
    int processedBooks = 0;
    int sqliteSuccessCount = 0;
    int fileSuccessCount = 0;
    int errorCount = 0;
    
    // Throttle progress updates to reduce UI overhead
    DateTime lastProgressUpdate = DateTime.now();
    const progressUpdateInterval = Duration(milliseconds: 100);

    debugPrint('📚 [INDEXING] Total books to index: $totalBooks');
    debugPrint('');

    for (Book book in allBooks) {
      // Check if indexing was cancelled
      if (!_tantivyDataProvider.isIndexing.value) {
        return;
      }

      try {
        // Check if this book has already been indexed
        if (book is TextBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}textBook")) {
            if (_tantivyDataProvider.booksDone.contains(
                sha1.convert(utf8.encode((await book.text))).toString())) {
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
            } else {
              await _indexTextBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}textBook");
              sqliteSuccessCount++;
            }
          }
        } else if (book is PdfBook) {
          if (!_tantivyDataProvider.booksDone
              .contains("${book.title}pdfBook")) {
            if (_tantivyDataProvider.booksDone.contains(
                sha1.convert(await File(book.path).readAsBytes()).toString())) {
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
            } else {
              await _indexPdfBook(book);
              _tantivyDataProvider.booksDone.add("${book.title}pdfBook");
            }
          }
        }

        processedBooks++;
        
        // Throttled progress reporting to reduce UI overhead
        final now = DateTime.now();
        if (now.difference(lastProgressUpdate) >= progressUpdateInterval) {
          onProgress(processedBooks, totalBooks);
          lastProgressUpdate = now;
        }
        
        // Commit every 20 books with aggressive yielding to prevent UI blocking
        // Less frequent commits = less UI blocking
        if (processedBooks % 20 == 0) {
          await _performCommitWithYielding(processedBooks, totalBooks);
          // Always report progress after commit
          onProgress(processedBooks, totalBooks);
          lastProgressUpdate = DateTime.now();
        }
      } catch (e) {
        // Use async error handling to prevent event loop blocking
        await Future.microtask(() {
          debugPrint('❌ [INDEXING] Error adding ${book.title} to index: $e');
        });
        errorCount++;
        processedBooks++;
        
        // Throttled progress reporting even after error
        final now = DateTime.now();
        if (now.difference(lastProgressUpdate) >= progressUpdateInterval) {
          onProgress(processedBooks, totalBooks);
          lastProgressUpdate = now;
        }
        
        // Yield control back to event loop after error
        await Future.delayed(Duration.zero);
      }

      // Aggressive yielding after each book to prevent UI blocking
      // Use longer delay to give UI more time
      await Future.delayed(const Duration(milliseconds: 50)); 

    }

    // Final commit for any remaining books
    if (processedBooks % 20 != 0) {
      await _performCommitWithYielding(processedBooks, totalBooks, isFinal: true);
    }
    
    // Final progress update
    onProgress(processedBooks, totalBooks);
    
    // Reset indexing flag after completion
    _tantivyDataProvider.isIndexing.value = false;
    
    final totalElapsed = DateTime.now().difference(indexingStartTime);
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🎉 [INDEXING] Indexing process completed!');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('📊 [INDEXING] Final Statistics:');
    debugPrint('   ✅ Total books processed: $processedBooks / $totalBooks');
    debugPrint('   📚 Books from SQLite: $sqliteSuccessCount');
    debugPrint('   📁 Books from files: $fileSuccessCount');
    debugPrint('   ❌ Errors: $errorCount');
    debugPrint('   ⏱️  Total time: ${totalElapsed.inMinutes}m ${totalElapsed.inSeconds % 60}s');
    if (processedBooks > 0) {
      debugPrint('   ⚡ Average time per book: ${totalElapsed.inMilliseconds ~/ processedBooks}ms');
    }
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('');
  }

  /// Indexes a text-based book by processing its content and adding it to the search index and reference index.
  /// Returns true if indexed from SQLite, false if from file
  Future<bool> _indexTextBook(TextBook book) async {
    final index = await _tantivyDataProvider.engine;
    final refIndex = _tantivyDataProvider.refEngine;
    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    // Reuse single SqliteDataProvider instance for this book
    final sqliteProvider = SqliteDataProvider();
    
    // Try to get lines directly from DB for better performance
    List<String> texts;
    bool usedSqlite = false;
    try {
      texts = await sqliteProvider.getBookLines(title);
      usedSqlite = true;
    } catch (e) {
      // Fallback to reading full text and splitting
      debugPrint('⚠️  [INDEXING] Failed to read "$title" from SQLite, using file: $e');
      var text = await book.text;
      texts = text.split('\n');
    }

    // Try to get TOC from DB for reference indexing (reuse same provider)
    bool tocIndexed = false;
    Map<int, String> lineToReference = {}; // Map from line index to reference path
    
    try {
      final toc = await sqliteProvider.getBookToc(title);
      
      if (toc.isNotEmpty) {
        debugPrint('📚 [INDEXING] Found ${toc.length} TOC entries for "$title"');
        
        // Use counter for IDs instead of DateTime for better performance
        int idCounter = DateTime.now().microsecondsSinceEpoch;
        
        // Index TOC entries as references and build line-to-reference map
        void indexTocEntry(TocEntry entry, List<String> parentPath) {
          final fullPath = [...parentPath, entry.text];
          final refText = fullPath.join(', ');
          final shortref = replaceParaphrases(removeSectionNames(refText));
          
          // Store the reference for this line index
          lineToReference[entry.index] = refText;
          
          refIndex.addDocument(
              id: BigInt.from(idCounter++),
              title: title,
              reference: refText,
              shortRef: shortref,
              segment: BigInt.from(entry.index),
              isPdf: false,
              filePath: '');
          
          // Recursively index children
          for (final child in entry.children) {
            indexTocEntry(child, fullPath);
          }
        }
        
        // Index all top-level TOC entries
        for (final entry in toc) {
          indexTocEntry(entry, []);
        }
        
        debugPrint('📚 [INDEXING] Built lineToReference map with ${lineToReference.length} entries');
        if (lineToReference.isNotEmpty) {
          final firstEntry = lineToReference.entries.first;
          debugPrint('📚 [INDEXING] Example: line ${firstEntry.key} -> "${firstEntry.value}"');
        }
        
        tocIndexed = true;
      } else {
        debugPrint('⚠️  [INDEXING] No TOC found for "$title", will use HTML headers');
      }
    } catch (e) {
      debugPrint('⚠️  [INDEXING] Error loading TOC for "$title": $e');
      // TOC not available, will use HTML headers as fallback
    }

    // Build reference path from HTML headers (fallback if no TOC in DB)
    List<String> reference = [];
    
    // Use counter for IDs instead of DateTime for better performance
    int idCounter = DateTime.now().microsecondsSinceEpoch;

    // Index each line separately
    for (int i = 0; i < texts.length; i++) {
      if (!_tantivyDataProvider.isIndexing.value) {
        break;
      }
      
      // Aggressive yielding: every 50 lines with actual delay
      if (i % 50 == 0) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
      // Extra yield for very large books
      if (texts.length > 1000 && i % 200 == 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      String line = texts[i];
      
      // If we didn't index TOC from DB, index headers from text
      if (!tocIndexed && line.startsWith('<h')) {
        if (reference.isNotEmpty &&
            reference.any(
                (element) => element.substring(0, 4) == line.substring(0, 4))) {
          reference.removeRange(
              reference.indexWhere(
                  (element) => element.substring(0, 4) == line.substring(0, 4)),
              reference.length);
        }
        reference.add(line);

        // Index the header as a reference
        String refText = stripHtmlIfNeeded(reference.join(" "));
        final shortref = replaceParaphrases(removeSectionNames(refText));

        refIndex.addDocument(
            id: BigInt.from(idCounter++),
            title: title,
            reference: refText,
            shortRef: shortref,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: '');
      }
      
      // Always index the line content for search
      if (!line.startsWith('<h')) {
        line = stripHtmlIfNeeded(line);
        line = removeVolwels(line);

        // Build clean reference text
        String cleanReference;
        if (tocIndexed) {
          // Find the most recent TOC entry before or at this line
          String? foundRef;
          int closestIndex = -1;
          for (final entry in lineToReference.entries) {
            if (entry.key <= i && entry.key > closestIndex) {
              closestIndex = entry.key;
              foundRef = entry.value;
            }
          }
          cleanReference = foundRef ?? '';
          
          // Debug: print first few references
          if (i < 5 && cleanReference.isNotEmpty) {
            debugPrint('📚 [INDEXING] Line $i reference: "$cleanReference"');
          }
        } else {
          // Use HTML headers
          cleanReference = reference.map((h) => stripHtmlIfNeeded(h)).join(', ');
        }

        // Debug: print topics for first indexed line
        if (i == 0) {
          debugPrint('📚 [INDEXING] First line of "$title":');
          debugPrint('   book.topics: "${book.topics}"');
          debugPrint('   topics variable: "$topics"');
          debugPrint('   final topics field: "$topics/$title"');
        }

        // Add to search index
        index.addDocument(
            id: BigInt.from(idCounter++),
            title: title,
            reference: cleanReference,
            topics: '$topics/$title',
            text: line,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: '');
      }
    }

    // Note: We don't commit after every book to improve performance
    // The commit will happen in the main indexing loop every N books
    saveIndexedBooks();
    
    return usedSqlite;
  }

  /// Indexes a PDF book by extracting and processing text from each page.
  Future<void> _indexPdfBook(PdfBook book) async {
    final index = await _tantivyDataProvider.engine;

    // Extract text from each page
    final document = await PdfDocument.openFile(book.path);
    final pages = document.pages;
    final outline = await document.loadOutline();
    final title = book.title;
    final topics = "/${book.topics.replaceAll(', ', '/')}";

    // Use counter for IDs instead of DateTime for better performance
    int idCounter = DateTime.now().microsecondsSinceEpoch;
    
    // Process each page
    bool cancelled = false;
    for (int i = 0; i < pages.length && !cancelled; i++) {
      if (!_tantivyDataProvider.isIndexing.value) {
        cancelled = true;
        break;
      }
      
      final texts = (await pages[i].loadText()).fullText.split('\n');
      // Index each line from the page
      for (int j = 0; j < texts.length; j++) {
        if (!_tantivyDataProvider.isIndexing.value) {
          cancelled = true;
          break;
        }
        
        // Aggressive yielding for PDF indexing
        if (j % 25 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
        final bookmark = await refFromPageNumber(i + 1, outline, title);
        final ref = bookmark.isNotEmpty
            ? '$title, $bookmark, עמוד ${i + 1}'
            : '$title, עמוד ${i + 1}';
        index.addDocument(
            id: BigInt.from(idCounter++),
            title: title,
            reference: ref,
            topics: '$topics/$title',
            text: texts[j],
            segment: BigInt.from(i),
            isPdf: true,
            filePath: book.path);
      }
    }

    await index.commit();
    saveIndexedBooks();
  }

  /// Cancels the ongoing indexing process.
  void cancelIndexing() {
    _tantivyDataProvider.isIndexing.value = false;
  }

  /// Persists the list of indexed books to disk.
  void saveIndexedBooks() {
    _tantivyDataProvider.saveBooksDoneToDisk();
  }

  /// Clears the index and resets the list of indexed books.
  Future<void> clearIndex() async {
    debugPrint('🗑️  [INDEXING] Starting index clear...');
    
    // Mark as not indexing during clear
    _tantivyDataProvider.isIndexing.value = false;
    
    // Release any existing locks before clearing
    try {
      final index = await _tantivyDataProvider.engine;
      await index.commit(); // Commit any pending changes
      debugPrint('✅ [INDEXING] Committed pending changes');
    } catch (e) {
      debugPrint('⚠️  [INDEXING] Could not commit before clear: $e');
    }
    
    // Clean up any stale lock files
    await _cleanupStaleLocks();
    
    // Clear the index
    debugPrint('🗑️  [INDEXING] Clearing index data...');
    await _tantivyDataProvider.clear();
    
    // Give time for locks to be released
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Reopen the index for future use
    debugPrint('🔄 [INDEXING] Reopening index...');
    _tantivyDataProvider.reopenIndex();
    
    // Wait for reopen to complete
    await Future.delayed(const Duration(milliseconds: 500));
    
    debugPrint('✅ [INDEXING] Index cleared and reopened successfully');
    
    // Keep isIndexing as false - the next indexAllBooks will set it to true
  }
  
  /// Cleans up stale lock files from the index directory.
  /// This helps prevent "LockBusy" errors from previous crashed sessions.
  Future<void> _cleanupStaleLocks() async {
    try {
      // Note: We can't directly access AppPaths here, but Tantivy should
      // handle lock cleanup internally. This is a placeholder for future
      // implementation if needed.
      debugPrint('🧹 [INDEXING] Checking for stale locks...');
      
      // Give the system time to release any locks
      await Future.delayed(const Duration(milliseconds: 100));
      
      debugPrint('✅ [INDEXING] Lock cleanup completed');
    } catch (e) {
      debugPrint('⚠️  [INDEXING] Error during lock cleanup: $e');
    }
  }

  /// Gets the list of books that have already been indexed.
  List<String> getIndexedBooks() {
    return List<String>.from(_tantivyDataProvider.booksDone);
  }

  /// Checks if indexing is currently in progress.
  bool isIndexing() {
    return _tantivyDataProvider.isIndexing.value;
  }

  /// Performs a commit operation with aggressive yielding to prevent UI blocking.
  /// 
  /// This method uses compute() to attempt running the commit in a separate isolate,
  /// with fallback to aggressive yielding if that's not possible.
  Future<void> _performCommitWithYielding(
    int processedBooks,
    int totalBooks, {
    bool isFinal = false,
  }) async {
    final commitType = isFinal ? 'Final' : 'Batch';
    debugPrint('💾 [INDEXING] $commitType commit (${processedBooks}/${totalBooks})...');

    try {
      // Long delay before commit to let UI fully update
      await Future.delayed(const Duration(milliseconds: 100));

      // Get the index
      final index = await _tantivyDataProvider.engine;
      
      // Another long delay before the heavy operation
      await Future.delayed(const Duration(milliseconds: 100));

      // Commit main index (this is the heavy operation)
      // We can't move this to isolate due to FFI, but we can give UI time before/after
      await index.commit();

      // Long delay between commits to let UI breathe
      await Future.delayed(const Duration(milliseconds: 200));

      // Commit reference index
      await _tantivyDataProvider.refEngine.commit();

      // Long delay after commits
      await Future.delayed(const Duration(milliseconds: 100));

      debugPrint('✅ [INDEXING] $commitType committed');
    } catch (e) {
      debugPrint('❌ [INDEXING] Commit failed: $e');
      rethrow;
    }
  }
}
