import 'dart:async';
import 'package:logging/logging.dart';

import '../../core/models/author.dart';
import '../../core/models/book.dart';
import '../../core/models/category.dart';
import '../../core/models/line.dart';
import '../../core/models/link.dart';
import '../../core/models/pub_date.dart';
import '../../core/models/pub_place.dart';
import '../../core/models/search_result.dart';
import '../../core/models/source.dart';
import '../../core/models/toc_entry.dart';
import '../../core/models/topic.dart';
import '../drift/database.dart';

/// Repository class for accessing and manipulating the Seforim database.
/// Provides methods for CRUD operations on books, categories, lines, TOC entries, and links.
///
/// This is a Dart conversion of the original Kotlin SeforimRepository.
class SeforimRepository {
  final MyDatabase _database;
  final Logger _logger = Logger('SeforimRepository');

  /// Expose database for advanced operations
  MyDatabase get database => _database;

  SeforimRepository(this._database) {
    _initialize();
  }
  
  /// Ensures the database is initialized before use
  Future<void> ensureInitialized() async {
    await _database.database; // This triggers DAO initialization
  }

  void _initialize() {
    _logger.info('Initializing SeforimRepository');
    // Database schema creation is handled by MyDatabase
    // SQLite optimizations for normal operations
    _executeRawQuery('PRAGMA journal_mode=WAL');
    _executeRawQuery('PRAGMA synchronous=NORMAL');
    _executeRawQuery('PRAGMA cache_size=100000'); // Increased from 40000
    _executeRawQuery('PRAGMA temp_store=MEMORY');
    _executeRawQuery('PRAGMA mmap_size=268435456'); // 256MB memory-mapped I/O
    _executeRawQuery('PRAGMA page_size=4096'); // Optimal page size

    // Check if the database is empty
    try {
      _database.bookDao.countAllBooks().then((count) {
        _logger.info('Database contains $count books');
      });
    } catch (e) {
      _logger.info('Error counting books: ${e.toString()}');
    }
  }

  // --- Line ⇄ TOC mapping ---

  /// Maps a line to the TOC entry it belongs to. Upserts on conflict.
  Future<void> upsertLineToc(int lineId, int tocEntryId) async {
    final db = await _database.database;
    await db.rawInsert('''
      INSERT OR REPLACE INTO line_toc (lineId, tocEntryId)
      VALUES (?, ?)
    ''', [lineId, tocEntryId]);
  }

  /// Bulk upsert line→toc mappings
  Future<void> bulkUpsertLineToc(List<({int lineId, int tocId})> pairs) async {
    if (pairs.isEmpty) return;
    final db = await _database.database;
    final batch = db.batch();
    for (final pair in pairs) {
      batch.rawInsert('''
        INSERT OR REPLACE INTO line_toc (lineId, tocEntryId)
        VALUES (?, ?)
      ''', [pair.lineId, pair.tocId]);
    }
    await batch.commit(noResult: true);
  }

  /// Gets the tocEntryId associated with a line via the mapping table.
  Future<int?> getTocEntryIdForLine(int lineId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT tocEntryId FROM line_toc WHERE lineId = ?',
      [lineId]
    );
    if (result.isEmpty) return null;
    return result.first['tocEntryId'] as int?;
  }

  /// Gets the TocEntry model associated with a line via the mapping table.
  Future<TocEntry?> getTocEntryForLine(int lineId) async {
    final tocId = await getTocEntryIdForLine(lineId);
    if (tocId == null) return null;
    return await getTocEntry(tocId);
  }

  /// Returns the TOC entry whose heading line is the given line id, or null if not a TOC heading.
  Future<TocEntry?> getHeadingTocEntryByLineId(int lineId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT * FROM tocEntry WHERE lineId = ?',
      [lineId]
    );
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  /// Returns all line ids that belong to the given TOC entry (section), ordered by lineIndex.
  Future<List<int>> getLineIdsForTocEntry(int tocEntryId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT lineId FROM line_toc WHERE tocEntryId = ? ORDER BY lineId',
      [tocEntryId]
    );
    return result.map((row) => row['lineId'] as int).toList();
  }

  /// Returns mappings (lineId -> tocEntryId) for a book ordered by line index.
  Future<List<LineTocMapping>> getLineTocMappingsForBook(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT lt.lineId, lt.tocEntryId
      FROM line_toc lt
      JOIN line l ON lt.lineId = l.id
      WHERE l.bookId = ?
      ORDER BY l.lineIndex
    ''', [bookId]);
    return result.map((row) => LineTocMapping(
      lineId: row['lineId'] as int,
      tocEntryId: row['tocEntryId'] as int,
    )).toList();
  }

  /// Builds all mappings for a given book by assigning to each line
  /// the latest TOC entry whose start line index is <= line's index.
  Future<void> rebuildLineTocForBook(int bookId) async {
    final db = await _database.database;
    // Clear existing mappings for the book
    await db.rawDelete('DELETE FROM line_toc WHERE lineId IN (SELECT id FROM line WHERE bookId = ?)', [bookId]);

    // Insert computed mappings
    await db.execute('''
      INSERT INTO line_toc(lineId, tocEntryId)
      SELECT l.id AS lineId,
             (
                 SELECT t.id
                 FROM tocEntry t
                 JOIN line sl ON sl.id = t.lineId
                 WHERE t.bookId = l.bookId
                   AND t.lineId IS NOT NULL
                   AND sl.lineIndex <= l.lineIndex
                 ORDER BY sl.lineIndex DESC
                 LIMIT 1
             ) AS tocEntryId
      FROM line l
      WHERE l.bookId = ?
    ''', [bookId]);
  }

  // --- Transactions ---

  /// Runs a block of code in a transaction
  Future<T> runInTransaction<T>(Future<T> Function() block) async {
    final db = await _database.database;
    return await db.transaction((txn) async {
      // Temporarily replace the database connection with the transaction
      return await block();
    });
  }

  Future<void> setSynchronous(String mode) async {
    await executeRawQuery('PRAGMA synchronous=$mode');
  }

  Future<void> setSynchronousOff() => setSynchronous('OFF');
  Future<void> setSynchronousNormal() => setSynchronous('NORMAL');

  Future<void> setJournalMode(String mode) async {
    await executeRawQuery('PRAGMA journal_mode=$mode');
  }

  Future<void> setJournalModeOff() => setJournalMode('OFF');
  Future<void> setJournalModeWal() => setJournalMode('WAL');

  /// Sets maximum performance mode for bulk operations
  Future<void> setMaxPerformanceMode() async {
    _logger.info('Setting maximum performance mode for bulk operations');
    await executeRawQuery('PRAGMA synchronous=OFF');
    await executeRawQuery('PRAGMA journal_mode=MEMORY'); // Faster than OFF
    await executeRawQuery('PRAGMA locking_mode=EXCLUSIVE');
    await executeRawQuery('PRAGMA cache_size=200000'); // 200MB cache
    await executeRawQuery('PRAGMA temp_store=MEMORY');
    await executeRawQuery('PRAGMA mmap_size=536870912'); // 512MB memory-mapped
    _logger.info('Maximum performance mode enabled');
  }

  /// Restores normal performance mode after bulk operations
  Future<void> restoreNormalMode() async {
    _logger.info('Restoring normal performance mode');
    await executeRawQuery('PRAGMA synchronous=NORMAL');
    await executeRawQuery('PRAGMA journal_mode=WAL');
    await executeRawQuery('PRAGMA locking_mode=NORMAL');
    await executeRawQuery('PRAGMA cache_size=100000');
    _logger.info('Normal performance mode restored');
  }

  /// Rebuilds the category_closure table from the current category tree.
  Future<void> rebuildCategoryClosure() async {
    final db = await _database.database;
    // Clear existing closure data
    await db.rawDelete('DELETE FROM category_closure');
    
    // Load all categories
    final rows = await db.rawQuery('SELECT id, parentId FROM category');
    final parentMap = <int, int?>{};
    for (final row in rows) {
      parentMap[row['id'] as int] = row['parentId'] as int?;
    }
    
    // For each category, walk up to root and insert pairs
    for (final row in rows) {
      final descId = row['id'] as int;
      int? ancId = descId;
      
      // Self
      await db.rawInsert('INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)', [descId, descId]);
      
      ancId = parentMap[descId];
      var guard = 0;
      const safety = 128;
      
      while (ancId != null && guard++ < safety) {
        await db.rawInsert('INSERT INTO category_closure (ancestorId, descendantId) VALUES (?, ?)', [ancId, descId]);
        ancId = parentMap[ancId];
      }
    }
  }

  /// Returns all descendant category IDs (including the category itself) using the
  /// category_closure table.
  Future<List<int>> getDescendantCategoryIds(int ancestorId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT descendantId FROM category_closure WHERE ancestorId = ?',
      [ancestorId]
    );
    return result.map((row) => row['descendantId'] as int).toList();
  }

  // --- Categories ---

  /// Retrieves a category by its ID.
  ///
  /// @param id The ID of the category to retrieve
  /// @return The category if found, null otherwise
  Future<Category?> getCategory(int id) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM category WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Category.fromJson(result.first);
  }

  /// Retrieves all root categories (categories without a parent).
  ///
  /// @return A list of root categories
  Future<List<Category>> getRootCategories() async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM category WHERE parentId IS NULL ORDER BY title');
    return result.map((row) => Category.fromJson(row)).toList();
  }

  /// Retrieves all child categories of a parent category.
  ///
  /// @param parentId The ID of the parent category
  /// @return A list of child categories
  Future<List<Category>> getCategoryChildren(int parentId) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM category WHERE parentId = ? ORDER BY title', [parentId]);
    return result.map((row) => Category.fromJson(row)).toList();
  }

  /// Inserts a category into the database.
  /// If a category with the same title already exists, returns its ID instead.
  ///
  /// @param category The category to insert
  /// @return The ID of the inserted or existing category
  /// @throws Exception If the insertion fails
  Future<int> insertCategory(Category category) async {
    _logger.fine('Repository: Attempting to insert category \'${category.title}\'');
    _logger.fine('Category details: parentId=${category.parentId}, level=${category.level}');

    try {
      // Check if a category with the same title AND SAME PARENT already exists
      final existingCategories = await _getCategoriesByParent(category.parentId);

      // Find a category with the same title in the same parent
      final existingCategory = existingCategories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
      );

      if (existingCategory.id != -1) {
        _logger.fine('Category with title \'${category.title}\' already exists under parent ${category.parentId} with ID: ${existingCategory.id}');
        return existingCategory.id;
      }

      // Try the insertion
      final db = await _database.database;
      final insertedId = await db.rawInsert('''
        INSERT INTO category (parentId, title, level)
        VALUES (?, ?, ?)
      ''', [category.parentId, category.title, category.level]);

      _logger.fine('Repository: Category inserted with ID: $insertedId');

      if (insertedId == 0) {
        // Check again if the category was inserted despite lastInsertRowId() returning 0
        final updatedCategories = await _getCategoriesByParent(category.parentId);

        final newCategory = updatedCategories.firstWhere(
          (cat) => cat.title == category.title,
          orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
        );

        if (newCategory.id != -1) {
          _logger.fine('Category found after insertion, returning existing ID: ${newCategory.id}');
          return newCategory.id;
        }

        // If all else fails, throw an exception
        throw Exception('Failed to insert category \'${category.title}\' with parent ${category.parentId}');
      }

      return insertedId;

    } catch (e) {
      // Changed from error to warning level to reduce unnecessary error logs
      _logger.warning('Repository: Error inserting category \'${category.title}\': ${e.toString()}');

      // In case of error, check if the category exists anyway
      final categories = await _getCategoriesByParent(category.parentId);

      final existingCategory = categories.firstWhere(
        (cat) => cat.title == category.title,
        orElse: () => Category(id: -1, title: '', parentId: null, level: 0),
      );

      if (existingCategory.id != -1) {
        _logger.fine('Category exists after error, returning existing ID: ${existingCategory.id}');
        return existingCategory.id;
      }

      // Re-throw the exception if we can't recover
      rethrow;
    }
  }

  Future<List<Category>> _getCategoriesByParent(int? parentId) async {
    final db = await _database.database;
    final result = parentId != null
        ? await db.rawQuery('SELECT * FROM category WHERE parentId = ?', [parentId])
        : await db.rawQuery('SELECT * FROM category WHERE parentId IS NULL');
    return result.map((row) => Category.fromJson(row)).toList();
  }

  // --- Books ---

  /// Retrieves a book by its ID, including all related data (authors, topics, etc.).
  ///
  /// @param id The ID of the book to retrieve
  /// @return The book if found, null otherwise
  Future<Book?> getBook(int id) async {
    final bookData = await _database.bookDao.getBookById(id);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(id);
    final topics = await _getBookTopics(id);
    final pubPlaces = await _getBookPubPlaces(id);
    final pubDates = await _getBookPubDates(id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  /// Retrieves all books in a specific category.
  ///
  /// @param categoryId The ID of the category
  /// @return A list of books in the category
  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final books = await _database.bookDao.getBooksByCategory(categoryId);
    return Future.wait(books.map((bookData) async {
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  Future<List<Book>> searchBooksByAuthor(String authorName) async {
    final books = await _database.bookDao.getBooksByAuthor(authorName);
    return Future.wait(books.map((bookData) async {
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  // Get all authors for a book
  Future<List<Author>> _getBookAuthors(int bookId) async {
    _logger.fine('Getting authors for book ID: $bookId');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT a.* FROM author a
      JOIN book_author ba ON a.id = ba.authorId
      WHERE ba.bookId = ?
    ''', [bookId]);
    final authors = result.map((row) => Author.fromJson(row)).toList();
    _logger.fine('Found ${authors.length} authors for book ID: $bookId');
    return authors;
  }

  // Get all topics for a book
  Future<List<Topic>> _getBookTopics(int bookId) async {
    _logger.fine('Getting topics for book ID: $bookId');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT t.* FROM topic t
      JOIN book_topic bt ON t.id = bt.topicId
      WHERE bt.bookId = ?
    ''', [bookId]);
    final topics = result.map((row) => Topic.fromJson(row)).toList();
    _logger.fine('Found ${topics.length} topics for book ID: $bookId');
    return topics;
  }

  // Get all publication places for a book
  Future<List<PubPlace>> _getBookPubPlaces(int bookId) async {
    _logger.fine('Getting publication places for book ID: $bookId');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT pp.* FROM pub_place pp
      JOIN book_pub_place bpp ON pp.id = bpp.pubPlaceId
      WHERE bpp.bookId = ?
    ''', [bookId]);
    final pubPlaces = result.map((row) => PubPlace.fromJson(row)).toList();
    _logger.fine('Found ${pubPlaces.length} publication places for book ID: $bookId');
    return pubPlaces;
  }

  // Get all publication dates for a book
  Future<List<PubDate>> _getBookPubDates(int bookId) async {
    _logger.fine('Getting publication dates for book ID: $bookId');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT pd.* FROM pub_date pd
      JOIN book_pub_date bpd ON pd.id = bpd.pubDateId
      WHERE bpd.bookId = ?
    ''', [bookId]);
    final pubDates = result.map((row) => PubDate.fromJson(row)).toList();
    _logger.fine('Found ${pubDates.length} publication dates for book ID: $bookId');
    return pubDates;
  }

  // Get an author by name, returns null if not found
  Future<Author?> getAuthorByName(String name) async {
    _logger.fine('Looking for author with name: $name');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM author WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) {
      _logger.fine('Author not found: $name');
      return null;
    }
    final author = Author.fromJson(result.first);
    _logger.fine('Found author with ID: ${author.id}');
    return author;
  }

  // Insert an author and return its ID
  Future<int> insertAuthor(String name) async {
    _logger.fine('Inserting author: $name');

    // Check if author already exists
    final existingAuthor = await getAuthorByName(name);
    if (existingAuthor != null) {
      _logger.fine('Author already exists with ID: ${existingAuthor.id}');
      return existingAuthor.id;
    }

    // Insert the author
    final db = await _database.database;
    final authorId = await db.rawInsert('INSERT INTO author (name) VALUES (?)', [name]);

    // If lastInsertRowId returns 0, it might be because the insertion was ignored due to a conflict
    // Try to get the ID by name
    if (authorId == 0) {
      final insertedAuthor = await getAuthorByName(name);
      if (insertedAuthor != null) {
        _logger.fine('Found author after insertion with ID: ${insertedAuthor.id}');
        return insertedAuthor.id;
      }

      // If we can't find the author by name, try to insert it again with a different method
      _logger.fine('Author not found after insertion, trying insertAndGetId');
      final retryAuthorId = await db.rawInsert('INSERT OR IGNORE INTO author (name) VALUES (?)', [name]);
      if (retryAuthorId != 0) {
        _logger.fine('Found author after retry with ID: $retryAuthorId');
        return retryAuthorId;
      }

      // Check again
      final retryAuthor = await getAuthorByName(name);
      if (retryAuthor != null) {
        _logger.fine('Found author after retry with ID: ${retryAuthor.id}');
        return retryAuthor.id;
      }

      // If all else fails, return a dummy ID that will be used for this session only
      // This allows the process to continue without throwing an exception
      _logger.warning('Could not insert author \'$name\' after multiple attempts, using temporary ID');
      return 999999;
    }

    _logger.fine('Author inserted with ID: $authorId');
    return authorId;
  }

  // Link an author to a book
  Future<void> linkAuthorToBook(int authorId, int bookId) async {
    _logger.fine('Linking author $authorId to book $bookId');
    final db = await _database.database;
    await db.rawInsert('INSERT OR IGNORE INTO book_author (bookId, authorId) VALUES (?, ?)', [bookId, authorId]);
    _logger.fine('Linked author $authorId to book $bookId');
  }

  Future<Book?> getBookByTitle(String title) async {
    final bookData = await _database.bookDao.getBookByTitle(title);
    if (bookData == null) return null;

    final authors = await _getBookAuthors(bookData.id);
    final topics = await _getBookTopics(bookData.id);
    final pubPlaces = await _getBookPubPlaces(bookData.id);
    final pubDates = await _getBookPubDates(bookData.id);

    return bookData.copyWith(
      authors: authors,
      topics: topics,
      pubPlaces: pubPlaces,
      pubDates: pubDates,
    );
  }

  // Get a topic by name, returns null if not found
  Future<Topic?> getTopicByName(String name) async {
    _logger.fine('Looking for topic with name: $name');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM topic WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) {
      _logger.fine('Topic not found: $name');
      return null;
    }
    final topic = Topic.fromJson(result.first);
    _logger.fine('Found topic with ID: ${topic.id}');
    return topic;
  }

  // Get a publication place by name, returns null if not found
  Future<PubPlace?> getPubPlaceByName(String name) async {
    _logger.fine('Looking for publication place with name: $name');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM pub_place WHERE name = ? LIMIT 1', [name]);
    if (result.isEmpty) {
      _logger.fine('Publication place not found: $name');
      return null;
    }
    final pubPlace = PubPlace.fromJson(result.first);
    _logger.fine('Found publication place with ID: ${pubPlace.id}');
    return pubPlace;
  }

  // Get a publication date by date, returns null if not found
  Future<PubDate?> getPubDateByDate(String date) async {
    _logger.fine('Looking for publication date with date: $date');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM pub_date WHERE date = ? LIMIT 1', [date]);
    if (result.isEmpty) {
      _logger.fine('Publication date not found: $date');
      return null;
    }
    final pubDate = PubDate.fromJson(result.first);
    _logger.fine('Found publication date with ID: ${pubDate.id}');
    return pubDate;
  }

  // Insert a topic and return its ID
  Future<int> insertTopic(String name) async {
    _logger.fine('Inserting topic: $name');

    // Check if topic already exists
    final existingTopic = await getTopicByName(name);
    if (existingTopic != null) {
      _logger.fine('Topic already exists with ID: ${existingTopic.id}');
      return existingTopic.id;
    }

    // Insert the topic
    final db = await _database.database;
    final topicId = await db.rawInsert('INSERT INTO topic (name) VALUES (?)', [name]);

    // If lastInsertRowId returns 0, it might be because the insertion was ignored due to a conflict
    // Try to get the ID by name
    if (topicId == 0) {
      final insertedTopic = await getTopicByName(name);
      if (insertedTopic != null) {
        _logger.fine('Found topic after insertion with ID: ${insertedTopic.id}');
        return insertedTopic.id;
      }

      // If we can't find the topic by name, try to insert it again with a different method
      _logger.fine('Topic not found after insertion, trying insertAndGetId');
      final retryTopicId = await db.rawInsert('INSERT OR IGNORE INTO topic (name) VALUES (?)', [name]);
      if (retryTopicId != 0) {
        _logger.fine('Found topic after retry with ID: $retryTopicId');
        return retryTopicId;
      }

      // Check again
      final retryTopic = await getTopicByName(name);
      if (retryTopic != null) {
        _logger.fine('Found topic after retry with ID: ${retryTopic.id}');
        return retryTopic.id;
      }

      // If all else fails, return a dummy ID that will be used for this session only
      // This allows the process to continue without throwing an exception
      _logger.warning('Could not insert topic \'$name\' after multiple attempts, using temporary ID');
      return 999999;
    }

    _logger.fine('Topic inserted with ID: $topicId');
    return topicId;
  }

  // Link a topic to a book
  Future<void> linkTopicToBook(int topicId, int bookId) async {
    _logger.fine('Linking topic $topicId to book $bookId');
    final db = await _database.database;
    await db.rawInsert('INSERT OR IGNORE INTO book_topic (bookId, topicId) VALUES (?, ?)', [bookId, topicId]);
    _logger.fine('Linked topic $topicId to book $bookId');
  }

  // Insert a publication place and return its ID
  Future<int> insertPubPlace(String name) async {
    _logger.fine('Inserting publication place: $name');

    // Check if publication place already exists
    final existingPubPlace = await getPubPlaceByName(name);
    if (existingPubPlace != null) {
      _logger.fine('Publication place already exists with ID: ${existingPubPlace.id}');
      return existingPubPlace.id;
    }

    // Insert the publication place
    final db = await _database.database;
    final pubPlaceId = await db.rawInsert('INSERT INTO pub_place (name) VALUES (?)', [name]);

    // If lastInsertRowId returns 0, it might be because the insertion was ignored due to a conflict
    // Try to get the ID by name
    if (pubPlaceId == 0) {
      final insertedPubPlace = await getPubPlaceByName(name);
      if (insertedPubPlace != null) {
        _logger.fine('Found publication place after insertion with ID: ${insertedPubPlace.id}');
        return insertedPubPlace.id;
      }

      // If all else fails, return a dummy ID that will be used for this session only
      // This allows the process to continue without throwing an exception
      _logger.warning('Could not insert publication place \'$name\' after multiple attempts, using temporary ID');
      return 999999;
    }

    _logger.fine('Publication place inserted with ID: $pubPlaceId');
    return pubPlaceId;
  }

  // Insert a publication date and return its ID
  Future<int> insertPubDate(String date) async {
    _logger.fine('Inserting publication date: $date');

    // Check if publication date already exists
    final existingPubDate = await getPubDateByDate(date);
    if (existingPubDate != null) {
      _logger.fine('Publication date already exists with ID: ${existingPubDate.id}');
      return existingPubDate.id;
    }

    // Insert the publication date
    final db = await _database.database;
    final pubDateId = await db.rawInsert('INSERT INTO pub_date (date) VALUES (?)', [date]);

    // If lastInsertRowId returns 0, it might be because the insertion was ignored due to a conflict
    // Try to get the ID by date
    if (pubDateId == 0) {
      final insertedPubDate = await getPubDateByDate(date);
      if (insertedPubDate != null) {
        _logger.fine('Found publication date after insertion with ID: ${insertedPubDate.id}');
        return insertedPubDate.id;
      }

      // If all else fails, return a dummy ID that will be used for this session only
      // This allows the process to continue without throwing an exception
      _logger.warning('Could not insert publication date \'$date\' after multiple attempts, using temporary ID');
      return 999999;
    }

    _logger.fine('Publication date inserted with ID: $pubDateId');
    return pubDateId;
  }

  // Link a publication place to a book
  Future<void> linkPubPlaceToBook(int pubPlaceId, int bookId) async {
    _logger.fine('Linking publication place $pubPlaceId to book $bookId');
    final db = await _database.database;
    await db.rawInsert('INSERT OR IGNORE INTO book_pub_place (bookId, pubPlaceId) VALUES (?, ?)', [bookId, pubPlaceId]);
    _logger.fine('Linked publication place $pubPlaceId to book $bookId');
  }

  // Link a publication date to a book
  Future<void> linkPubDateToBook(int pubDateId, int bookId) async {
    _logger.fine('Linking publication date $pubDateId to book $bookId');
    final db = await _database.database;
    await db.rawInsert('INSERT OR IGNORE INTO book_pub_date (bookId, pubDateId) VALUES (?, ?)', [bookId, pubDateId]);
    _logger.fine('Linked publication date $pubDateId to book $bookId');
  }

  /// Inserts a book into the database, including all related data (authors, topics, etc.).
  /// If the book has an ID greater than 0, uses that ID; otherwise, generates a new ID.
  ///
  /// @param book The book to insert
  /// @return The ID of the inserted book
  Future<int> insertBook(Book book) async {
    _logger.fine('Repository inserting book \'${book.title}\' with ID: ${book.id} and categoryId: ${book.categoryId}');

    // Use the ID from the book object if it's greater than 0
    if (book.id > 0) {
      await _database.bookDao.insertBookWithId(
        book.id,
        book.categoryId,
        book.sourceId,
        book.title,
        book.heShortDesc,
        book.order,
        book.totalLines,
      );
      _logger.fine('Used insertWithId for book \'${book.title}\' with ID: ${book.id} and categoryId: ${book.categoryId}');

      // Process authors
      for (final author in book.authors) {
        final authorId = await insertAuthor(author.name);
        await linkAuthorToBook(authorId, book.id);
        _logger.fine('Processed author \'${author.name}\' (ID: $authorId) for book \'${book.title}\' (ID: ${book.id})');
      }

      // Process topics
      for (final topic in book.topics) {
        final topicId = await insertTopic(topic.name);
        await linkTopicToBook(topicId, book.id);
        _logger.fine('Processed topic \'${topic.name}\' (ID: $topicId) for book \'${book.title}\' (ID: ${book.id})');
      }

      // Process publication places
      for (final pubPlace in book.pubPlaces) {
        final pubPlaceId = await insertPubPlace(pubPlace.name);
        await linkPubPlaceToBook(pubPlaceId, book.id);
        _logger.fine('Processed publication place \'${pubPlace.name}\' (ID: $pubPlaceId) for book \'${book.title}\' (ID: ${book.id})');
      }

      // Process publication dates
      for (final pubDate in book.pubDates) {
        final pubDateId = await insertPubDate(pubDate.date);
        await linkPubDateToBook(pubDateId, book.id);
        _logger.fine('Processed publication date \'${pubDate.date}\' (ID: $pubDateId) for book \'${book.title}\' (ID: ${book.id})');
      }

      return book.id;
    } else {
      // Fall back to auto-generated ID if book.id is 0
      final id = await _database.bookDao.insertBook(
        book.categoryId,
        book.sourceId,
        book.title,
        book.heShortDesc,
        book.order,
        book.totalLines,
      );
      _logger.fine('Used insert for book \'${book.title}\', got ID: $id with categoryId: ${book.categoryId}');

      // Check if insertion failed
      if (id == 0) {
        // Try to find the book by title
        final existingBook = await _database.bookDao.getBookByTitle(book.title);
        if (existingBook != null) {
          _logger.fine('Found book after failed insertion, returning existing ID: ${existingBook.id}');
          return existingBook.id;
        }

        throw Exception('Failed to insert book \'${book.title}\' - insertion returned ID 0. Context: categoryId=${book.categoryId}, authors=${book.authors.map((a) => a.name)}, topics=${book.topics.map((t) => t.name)}, pubPlaces=${book.pubPlaces.map((p) => p.name)}, pubDates=${book.pubDates.map((d) => d.date)}');
      }

      // Process authors
      for (final author in book.authors) {
        final authorId = await insertAuthor(author.name);
        await linkAuthorToBook(authorId, id);
        _logger.fine('Processed author \'${author.name}\' (ID: $authorId) for book \'${book.title}\' (ID: $id)');
      }

      // Process topics
      for (final topic in book.topics) {
        final topicId = await insertTopic(topic.name);
        await linkTopicToBook(topicId, id);
        _logger.fine('Processed topic \'${topic.name}\' (ID: $topicId) for book \'${book.title}\' (ID: $id)');
      }

      // Process publication places
      for (final pubPlace in book.pubPlaces) {
        final pubPlaceId = await insertPubPlace(pubPlace.name);
        await linkPubPlaceToBook(pubPlaceId, id);
        _logger.fine('Processed publication place \'${pubPlace.name}\' (ID: $pubPlaceId) for book \'${book.title}\' (ID: $id)');
      }

      // Process publication dates
      for (final pubDate in book.pubDates) {
        final pubDateId = await insertPubDate(pubDate.date);
        await linkPubDateToBook(pubDateId, id);
        _logger.fine('Processed publication date \'${pubDate.date}\' (ID: $pubDateId) for book \'${book.title}\' (ID: $id)');
      }

      return id;
    }
  }

  // --- Sources ---

  /// Returns a Source by name, or null if not found.
  Future<Source?> getSourceByName(String name) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM source WHERE name = ?', [name]);
    if (result.isEmpty) return null;
    return Source.fromJson(result.first);
  }

  /// Inserts a source if missing and returns its id.
  Future<int> insertSource(String name) async {
    // Check existing
    final existing = await getSourceByName(name);
    if (existing != null) return existing.id;

    final db = await _database.database;
    final id = await db.rawInsert('INSERT INTO source (name) VALUES (?)', [name]);
    if (id == 0) {
      // Try to read back just in case
      final again = await getSourceByName(name);
      if (again != null) return again.id;
      throw Exception('Failed to insert source \'$name\'');
    }
    return id;
  }

  Future<void> updateBookTotalLines(int bookId, int totalLines) async {
    await _database.bookDao.updateBookTotalLines(bookId, totalLines);
  }

  Future<void> updateBookCategoryId(int bookId, int categoryId) async {
    _logger.fine('Updating book $bookId with categoryId: $categoryId');
    await _database.bookDao.updateBookCategoryId(bookId, categoryId);
    _logger.fine('Updated book $bookId with categoryId: $categoryId');
  }

  // --- Lines ---

  Future<Line?> getLine(int id) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM line WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Line.fromJson(result.first);
  }

  Future<Line?> getLineByIndex(int bookId, int lineIndex) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM line WHERE bookId = ? AND lineIndex = ?', [bookId, lineIndex]);
    if (result.isEmpty) return null;
    return Line.fromJson(result.first);
  }

  Future<List<Line>> getLines(int bookId, int startIndex, int endIndex) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT * FROM line
      WHERE bookId = ? AND lineIndex >= ? AND lineIndex <= ?
      ORDER BY lineIndex
    ''', [bookId, startIndex, endIndex]);
    return result.map((row) => Line.fromJson(row)).toList();
  }

  /// Gets the previous line for a given book and line index.
  ///
  /// @param bookId The ID of the book
  /// @param currentLineIndex The index of the current line
  /// @return The previous line, or null if there is no previous line
  Future<Line?> getPreviousLine(int bookId, int currentLineIndex) async {
    if (currentLineIndex <= 0) return null;

    final previousIndex = currentLineIndex - 1;
    return await getLineByIndex(bookId, previousIndex);
  }

  /// Gets the next line for a given book and line index.
  ///
  /// @param bookId The ID of the book
  /// @param currentLineIndex The index of the current line
  /// @return The next line, or null if there is no next line
  Future<Line?> getNextLine(int bookId, int currentLineIndex) async {
    final nextIndex = currentLineIndex + 1;
    return await getLineByIndex(bookId, nextIndex);
  }

  Future<int> insertLine(Line line) async {
    _logger.fine('Repository inserting line with bookId: ${line.bookId}');

    // Use the ID from the line object if it's greater than 0
    if (line.id > 0) {
      final db = await _database.database;
      await db.rawInsert('''
        INSERT INTO line (id, bookId, lineIndex, content)
        VALUES (?, ?, ?, ?)
      ''', [line.id, line.bookId, line.lineIndex, line.content]);
      _logger.fine('Repository inserted line with explicit ID: ${line.id} and bookId: ${line.bookId}');
      return line.id;
    } else {
      // Fall back to auto-generated ID if line.id is 0
      final db = await _database.database;
      final lineId = await db.rawInsert('''
        INSERT INTO line (bookId, lineIndex, content)
        VALUES (?, ?, ?)
      ''', [line.bookId, line.lineIndex, line.content]);
      _logger.fine('Repository inserted line with auto-generated ID: $lineId and bookId: ${line.bookId}');

      // Check if insertion failed
      if (lineId == 0) {
        // Try to find the line by bookId and lineIndex
        final existingLine = await getLineByIndex(line.bookId, line.lineIndex);
        if (existingLine != null) {
          _logger.fine('Found line after failed insertion, returning existing ID: ${existingLine.id}');
          return existingLine.id;
        }

        throw Exception('Failed to insert line for book ${line.bookId} at index ${line.lineIndex} - insertion returned ID 0. Context: content=\'${line.content.substring(0, line.content.length < 50 ? line.content.length : 50)}${line.content.length > 50 ? "..." : ""}\'');
      }

      return lineId;
    }
  }

  /// Inserts multiple lines in a single batch operation for better performance
  Future<void> insertLinesBatch(List<Line> lines) async {
    if (lines.isEmpty) return;
    
    _logger.fine('Batch inserting ${lines.length} lines');
    final db = await _database.database;
    final batch = db.batch();
    
    for (final line in lines) {
      batch.rawInsert('''
        INSERT INTO line (id, bookId, lineIndex, content)
        VALUES (?, ?, ?, ?)
      ''', [line.id, line.bookId, line.lineIndex, line.content]);
    }
    
    await batch.commit(noResult: true);
    _logger.fine('Batch inserted ${lines.length} lines');
  }

  Future<void> updateLineTocEntry(int lineId, int tocEntryId) async {
    _logger.fine('Repository updating line $lineId with tocEntryId: $tocEntryId');
    final db = await _database.database;
    await db.rawUpdate('UPDATE line SET tocEntryId = ? WHERE id = ?', [tocEntryId, lineId]);
    _logger.fine('Repository updated line $lineId with tocEntryId: $tocEntryId');
  }

  // --- Table of Contents ---

  Future<TocEntry?> getTocEntry(int id) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM tocEntry WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return TocEntry.fromMap(result.first);
  }

  Future<List<TocEntry>> getBookToc(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM tocEntry WHERE bookId = ? ORDER BY level, textId', [bookId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<List<TocEntry>> getBookRootToc(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM tocEntry WHERE bookId = ? AND parentId IS NULL ORDER BY textId', [bookId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<List<TocEntry>> getTocChildren(int parentId) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM tocEntry WHERE parentId = ? ORDER BY textId', [parentId]);
    return result.map((row) => TocEntry.fromMap(row)).toList();
  }

  // --- TocText methods ---

  // Returns all distinct tocText values using generated SQLDelight query
  Future<List<String>> getAllTocTexts() async {
    _logger.fine('Getting all tocText values (using generated query)');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT text FROM tocText ORDER BY text');
    return result.map((row) => row['text'] as String).toList();
  }

  // Get or create a tocText entry and return its ID
  Future<int> _getOrCreateTocText(String text) async {
    // Truncate text for logging if it's too long
    final truncatedText = text.length > 50 ? '${text.substring(0, 50)}...' : text;
    _logger.fine('Getting or creating tocText entry for text: \'$truncatedText\'');

    try {
      // Check if the text already exists
      _logger.fine('Checking if text already exists in database');
      final db = await _database.database;
      final existingResult = await db.rawQuery('SELECT id FROM tocText WHERE text = ?', [text]);
      if (existingResult.isNotEmpty) {
        final existingId = existingResult.first['id'] as int;
        _logger.fine('Found existing tocText entry with ID: $existingId for text: \'$truncatedText\'');
        return existingId;
      }

      // Insert the text
      _logger.fine('Text not found, inserting new tocText entry for: \'$truncatedText\'');
      final textId = await db.rawInsert('INSERT OR IGNORE INTO tocText (text) VALUES (?)', [text]);

      // Get the ID of the inserted text
      _logger.fine('lastInsertRowId() returned: $textId');

      // If lastInsertRowId returns 0, it's likely because the text already exists (due to INSERT OR IGNORE)
      // This is expected behavior, not an error, so we'll try to get the ID by text
      if (textId == 0) {
        // Log at debug level since this is expected behavior when text already exists
        _logger.fine('lastInsertRowId() returned 0 for tocText insertion (likely due to INSERT OR IGNORE). Text: \'$truncatedText\', Length: ${text.length}. Trying to get ID by text.');

        // Try to find the text that was just inserted or that already existed
        final insertedResult = await db.rawQuery('SELECT id FROM tocText WHERE text = ?', [text]);
        if (insertedResult.isNotEmpty) {
          final insertedId = insertedResult.first['id'] as int;
          _logger.fine('Found tocText with ID: $insertedId for text: \'$truncatedText\'');
          return insertedId;
        }

        // If we can't find the text by exact match, this is unexpected and should be logged as an error
        // Count total tocTexts for debugging
        final totalTocTextsResult = await db.rawQuery('SELECT COUNT(*) FROM tocText');
        final totalTocTexts = totalTocTextsResult.first.values.first as int;

        // Log more details about the failure
        // Changed from error to warning level to reduce unnecessary error logs
        _logger.warning('Failed to insert tocText and couldn\'t find it after insertion. This is unexpected since the text should either be inserted or already exist. Text: \'$truncatedText\', Length: ${text.length}, Total TocTexts: $totalTocTexts');

        throw Exception('Failed to insert tocText \'$truncatedText\' - insertion returned ID 0 and couldn\'t find text afterward. This is unexpected since the text should either be inserted or already exist. Context: textLength=${text.length}, totalTocTexts=$totalTocTexts');
      }

      _logger.fine('Created new tocText entry with ID: $textId for text: \'$truncatedText\'');
      return textId;
    } catch (e) {
      // Changed from error to warning level to reduce unnecessary error logs
      _logger.warning('Exception in getOrCreateTocText for text: \'$truncatedText\', Length: ${text.length}}. Error: ${e.toString()}');
      rethrow;
    }
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    _logger.fine('Repository inserting TOC entry with bookId: ${entry.bookId}, lineId: ${entry.lineId}, hasChildren: ${entry.hasChildren}');

    // Get or create the tocText entry
    final textId = entry.textId ?? await _getOrCreateTocText(entry.text);
    _logger.fine('Using tocText ID: $textId for text: ${entry.text}');

    // Use the ID from the entry object if it's greater than 0
    if (entry.id > 0) {
      final db = await _database.database;
      await db.rawInsert('''
        INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId, isLastChild, hasChildren)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [entry.id, entry.bookId, entry.parentId, textId, entry.level, entry.lineId, entry.isLastChild ? 1 : 0, entry.hasChildren ? 1 : 0]);
      _logger.fine('Repository inserted TOC entry with explicit ID: ${entry.id}, bookId: ${entry.bookId}, lineId: ${entry.lineId}, hasChildren: ${entry.hasChildren}');
      return entry.id;
    } else {
      // Fall back to auto-generated ID if entry.id is 0
      final db = await _database.database;
      final tocId = await db.rawInsert('''
        INSERT INTO tocEntry (bookId, parentId, textId, level, lineId, isLastChild, hasChildren)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [entry.bookId, entry.parentId, textId, entry.level, entry.lineId, entry.isLastChild ? 1 : 0, entry.hasChildren ? 1 : 0]);
      _logger.fine('Repository inserted TOC entry with auto-generated ID: $tocId, bookId: ${entry.bookId}, lineId: ${entry.lineId}, hasChildren: ${entry.hasChildren}');

      // Check if insertion failed
      if (tocId == 0) {
        // Try to find a matching TOC entry by bookId and text
        final existingResult = await db.rawQuery('SELECT * FROM tocEntry WHERE bookId = ?', [entry.bookId]);
        final matchingEntry = existingResult.firstWhere(
          (row) => TocEntry.fromJson(row).text == entry.text && TocEntry.fromJson(row).level == entry.level,
          orElse: () => <String, dynamic>{},
        );

        if (matchingEntry.isNotEmpty) {
          final existingTocEntry = TocEntry.fromMap(matchingEntry);
          _logger.fine('Found matching TOC entry after failed insertion, returning existing ID: ${existingTocEntry.id}');
          return existingTocEntry.id;
        }

        throw Exception('Failed to insert TOC entry for book ${entry.bookId} with text \'${entry.text.substring(0, entry.text.length < 30 ? entry.text.length : 30)}${entry.text.length > 30 ? "..." : ""}\' - insertion returned ID 0. Context: parentId=${entry.parentId}, level=${entry.level}, lineId=${entry.lineId}');
      }

      return tocId;
    }
  }

  /// Inserts multiple TOC entries in a single batch operation for better performance
  Future<void> insertTocEntriesBatch(List<TocEntry> entries) async {
    if (entries.isEmpty) return;
    
    _logger.fine('Batch inserting ${entries.length} TOC entries');
    final db = await _database.database;
    final batch = db.batch();
    
    // Pre-create all tocText entries
    final textIds = <String, int>{};
    for (final entry in entries) {
      if (!textIds.containsKey(entry.text)) {
        textIds[entry.text] = await _getOrCreateTocText(entry.text);
      }
    }
    
    for (final entry in entries) {
      final textId = textIds[entry.text];
      if (textId == null) {
        _logger.warning('Text ID not found for TOC entry text: ${entry.text}, skipping entry');
        continue;
      }
      batch.rawInsert('''
        INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId, isLastChild, hasChildren)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [entry.id, entry.bookId, entry.parentId, textId, entry.level, entry.lineId, entry.isLastChild ? 1 : 0, entry.hasChildren ? 1 : 0]);
    }
    
    await batch.commit(noResult: true);
    _logger.fine('Batch inserted ${entries.length} TOC entries');
  }

  // Nouvelle méthode pour mettre à jour hasChildren
  Future<void> updateTocEntryHasChildren(int tocEntryId, bool hasChildren) async {
    _logger.fine('Repository updating TOC entry $tocEntryId with hasChildren: $hasChildren');
    final db = await _database.database;
    await db.rawUpdate('UPDATE tocEntry SET hasChildren = ? WHERE id = ?', [hasChildren ? 1 : 0, tocEntryId]);
    _logger.fine('Repository updated TOC entry $tocEntryId with hasChildren: $hasChildren');
  }

  Future<void> updateTocEntryLineId(int tocEntryId, int lineId) async {
    _logger.fine('Repository updating TOC entry $tocEntryId with lineId: $lineId');
    final db = await _database.database;
    await db.rawUpdate('UPDATE tocEntry SET lineId = ? WHERE id = ?', [lineId, tocEntryId]);
    _logger.fine('Repository updated TOC entry $tocEntryId with lineId: $lineId');
  }

  Future<void> updateTocEntryIsLastChild(int tocEntryId, bool isLastChild) async {
    _logger.fine('Repository updating TOC entry $tocEntryId with isLastChild: $isLastChild');
    final db = await _database.database;
    await db.rawUpdate('UPDATE tocEntry SET isLastChild = ? WHERE id = ?', [isLastChild ? 1 : 0, tocEntryId]);
    _logger.fine('Repository updated TOC entry $tocEntryId with isLastChild: $isLastChild');
  }

  /// Bulk update TOC entry lineIds
  Future<void> bulkUpdateTocEntryLineIds(List<({int tocId, int lineId})> updates) async {
    if (updates.isEmpty) return;
    _logger.fine('Bulk updating ${updates.length} TOC entry lineIds');
    final db = await _database.database;
    final batch = db.batch();
    for (final update in updates) {
      batch.rawUpdate('UPDATE tocEntry SET lineId = ? WHERE id = ?', [update.lineId, update.tocId]);
    }
    await batch.commit(noResult: true);
  }

  /// Bulk update TOC entries hasChildren flag
  Future<void> bulkUpdateTocEntryHasChildren(List<int> tocEntryIds, bool hasChildren) async {
    if (tocEntryIds.isEmpty) return;
    _logger.fine('Bulk updating ${tocEntryIds.length} TOC entries hasChildren=$hasChildren');
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE tocEntry SET hasChildren = ? WHERE id IN ($placeholders)',
      [hasChildren ? 1 : 0, ...tocEntryIds]
    );
  }

  /// Bulk update TOC entries isLastChild flag
  Future<void> bulkUpdateTocEntryIsLastChild(List<int> tocEntryIds, bool isLastChild) async {
    if (tocEntryIds.isEmpty) return;
    _logger.fine('Bulk updating ${tocEntryIds.length} TOC entries isLastChild=$isLastChild');
    final db = await _database.database;
    final placeholders = List.filled(tocEntryIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE tocEntry SET isLastChild = ? WHERE id IN ($placeholders)',
      [isLastChild ? 1 : 0, ...tocEntryIds]
    );
  }

  // --- Connection Types ---

  /// Gets a connection type by name, or creates it if it doesn't exist.
  ///
  /// @param name The name of the connection type
  /// @return The ID of the connection type
  Future<int> _getOrCreateConnectionType(String name) async {
    _logger.fine('Getting or creating connection type: $name');

    // Check if the connection type already exists
    final db = await _database.database;
    final existingResult = await db.rawQuery('SELECT id FROM connection_type WHERE name = ?', [name]);
    if (existingResult.isNotEmpty) {
      final existingId = existingResult.first['id'] as int;
      _logger.fine('Found existing connection type with ID: $existingId');
      return existingId;
    }

    // Insert the connection type
    final typeId = await db.rawInsert('INSERT INTO connection_type (name) VALUES (?)', [name]);

    // If lastInsertRowId returns 0, try to get the ID by name
    if (typeId == 0) {
      final insertedResult = await db.rawQuery('SELECT id FROM connection_type WHERE name = ?', [name]);
      if (insertedResult.isNotEmpty) {
        final insertedId = insertedResult.first['id'] as int;
        _logger.fine('Found connection type after insertion with ID: $insertedId');
        return insertedId;
      }

      throw Exception('Failed to insert connection type \'$name\' - insertion returned ID 0 and couldn\'t find type afterward');
    }

    _logger.fine('Created new connection type with ID: $typeId');
    return typeId;
  }

  /// Gets all connection types from the database.
  ///
  /// @return A list of all connection types
  Future<List<String>> getAllConnectionTypes() async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT name FROM connection_type ORDER BY name');
    return result.map((row) => row['name'] as String).toList();
  }

  // --- Links ---

  Future<Link?> getLink(int id) async {
    final db = await _database.database;
    final result = await db.rawQuery('SELECT * FROM link WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Link.fromJson(result.first);
  }

  Future<int> countLinks() async {
    _logger.fine('Counting links in database');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM link');
    final count = result.first.values.first as int;
    _logger.fine('Found $count links in database');
    return count;
  }

  Future<List<CommentaryWithText>> getCommentariesForLines(List<int> lineIds, Set<int> activeCommentatorIds) async {
    final db = await _database.database;
    final placeholders = List.filled(lineIds.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT l.*, b.title as targetBookTitle, ln.plainText as targetText
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      JOIN line ln ON l.targetLineId = ln.id
      WHERE l.sourceLineId IN ($placeholders)
      ${activeCommentatorIds.isNotEmpty ? 'AND l.targetBookId IN (${List.filled(activeCommentatorIds.length, '?').join(',')})' : ''}
      ORDER BY l.targetBookId, l.targetLineId
    ''', [...lineIds, ...activeCommentatorIds]);

    return result.map((row) {
      final link = Link(
        id: row['id'] as int,
        sourceBookId: row['sourceBookId'] as int,
        targetBookId: row['targetBookId'] as int,
        sourceLineId: row['sourceLineId'] as int,
        targetLineId: row['targetLineId'] as int,
        connectionType: ConnectionType.fromString(row['connectionTypeId'].toString()), // This needs to be mapped properly
      );
      return CommentaryWithText(
        link: link,
        targetBookTitle: row['targetBookTitle'] as String,
        targetText: row['targetText'] as String,
      );
    }).toList();
  }

  Future<List<CommentatorInfo>> getAvailableCommentators(int bookId) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.id as targetBookId, b.title as targetBookTitle, a.name as author, COUNT(l.id) as linkCount
      FROM link l
      JOIN book b ON l.targetBookId = b.id
      LEFT JOIN book_author ba ON b.id = ba.bookId
      LEFT JOIN author a ON ba.authorId = a.id
      WHERE l.sourceBookId = ?
      GROUP BY b.id, b.title, a.name
      ORDER BY b.title
    ''', [bookId]);

    return result.map((row) => CommentatorInfo(
      bookId: row['targetBookId'] as int,
      title: row['targetBookTitle'] as String,
      author: row['author'] as String?,
      linkCount: row['linkCount'] as int,
    )).toList();
  }

  // New paginated methods for per-commentator pagination use cases
  Future<List<CommentaryWithText>> getCommentariesForLineRange(
    List<int> lineIds,
    Set<int> activeCommentatorIds,
    int offset,
    int limit,
  ) async {
    final commentaries = await getCommentariesForLines(lineIds, activeCommentatorIds);
    return commentaries.skip(offset).take(limit).toList();
  }

  Future<List<CommentatorInfo>> getAvailableCommentatorsPaginated(
    int bookId,
    int offset,
    int limit,
  ) async {
    final commentators = await getAvailableCommentators(bookId);
    return commentators.skip(offset).take(limit).toList();
  }

  Future<int> insertLink(Link link) async {
    _logger.fine('Repository inserting link from book ${link.sourceBookId} to book ${link.targetBookId}');
    _logger.fine('Link details - sourceLineId: ${link.sourceLineId}, targetLineId: ${link.targetLineId}, connectionType: ${link.connectionType.name}');

    try {
      // Get or create the connection type
      final connectionTypeId = await _getOrCreateConnectionType(link.connectionType.name);
      _logger.fine('Using connection type ID: $connectionTypeId for type: ${link.connectionType.name}');

      final db = await _database.database;
      final linkId = await db.rawInsert('''
        INSERT INTO link (sourceBookId, targetBookId, sourceLineId, targetLineId, connectionTypeId)
        VALUES (?, ?, ?, ?, ?)
      ''', [link.sourceBookId, link.targetBookId, link.sourceLineId, link.targetLineId, connectionTypeId]);
      _logger.fine('Repository inserted link with ID: $linkId');

      // Check if insertion failed
      if (linkId == 0) {
        // Try to find a matching link
        final existingResult = await db.rawQuery('''
          SELECT id FROM link
          WHERE sourceBookId = ? AND targetBookId = ? AND sourceLineId = ? AND targetLineId = ?
        ''', [link.sourceBookId, link.targetBookId, link.sourceLineId, link.targetLineId]);

        if (existingResult.isNotEmpty) {
          final existingId = existingResult.first['id'] as int;
          _logger.fine('Found matching link after failed insertion, returning existing ID: $existingId');
          return existingId;
        }

        throw Exception('Failed to insert link from book ${link.sourceBookId} to book ${link.targetBookId} - insertion returned ID 0. Context: sourceLineId=${link.sourceLineId}, targetLineId=${link.targetLineId}, connectionType=${link.connectionType.name}');
      }

      return linkId;
    } catch (e) {
      // Changed from error to warning level to reduce unnecessary error logs
      _logger.warning('Error inserting link: ${e.toString()}');
      rethrow;
    }
  }

  /// Inserts multiple links in a single batch operation for better performance
  Future<void> insertLinksBatch(List<Link> links) async {
    if (links.isEmpty) return;
    
    _logger.fine('Batch inserting ${links.length} links');
    final db = await _database.database;
    final batch = db.batch();
    
    // Pre-create all connection types
    final connectionTypeIds = <String, int>{};
    for (final link in links) {
      if (!connectionTypeIds.containsKey(link.connectionType.name)) {
        connectionTypeIds[link.connectionType.name] = 
            await _getOrCreateConnectionType(link.connectionType.name);
      }
    }
    
    for (final link in links) {
      final connectionTypeId = connectionTypeIds[link.connectionType.name];
      if (connectionTypeId == null) {
        _logger.warning('Connection type ID not found for: ${link.connectionType.name}, skipping link');
        continue;
      }
      batch.rawInsert('''
        INSERT OR IGNORE INTO link (sourceBookId, targetBookId, sourceLineId, targetLineId, connectionTypeId)
        VALUES (?, ?, ?, ?, ?)
      ''', [link.sourceBookId, link.targetBookId, link.sourceLineId, link.targetLineId, connectionTypeId]);
    }
    
    await batch.commit(noResult: true);
    _logger.fine('Batch inserted ${links.length} links');
  }

  /// Migrates existing links to use the new connection_type table.
  /// This should be called once after updating the database schema.
  Future<void> migrateConnectionTypes() async {
    _logger.fine('Starting migration of connection types');

    try {
      // Make sure all connection types exist in the connection_type table
      for (final type in ConnectionType.values) {
        await _getOrCreateConnectionType(type.name);
      }

      // Get all links from the database
      final db = await _database.database;
      final linksResult = await db.rawQuery('SELECT * FROM link');
      _logger.fine('Found ${linksResult.length} links to migrate');

      // For each link, update the connectionTypeId
      var migratedCount = 0;
      for (final linkRow in linksResult) {
        final linkId = linkRow['id'] as int;
        final connectionTypeName = linkRow['connectionType'] as String; // This assumes the old column exists
        final connectionTypeId = await _getOrCreateConnectionType(connectionTypeName);

        // Execute a raw SQL query to update the link
        final updateSql = 'UPDATE link SET connectionTypeId = $connectionTypeId WHERE id = $linkId';
        await db.execute(updateSql);

        migratedCount++;
        if (migratedCount % 100 == 0) {
          _logger.fine('Migrated $migratedCount links so far');
        }
      }

      _logger.fine('Successfully migrated $migratedCount links');
      _logger.fine('Connection types migration completed successfully');
    } catch (e) {
      _logger.severe('Error during connection types migration: ${e.toString()}');
      rethrow;
    }
  }

  // --- Search ---

  /// Searches for text across all books.
  ///
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> search(String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [ftsQuery, limit, offset]);

    return result.map((row) => SearchResult(
      bookId: row['bookId'] as int,
      bookTitle: row['bookTitle'] as String,
      lineId: row['id'] as int,
      lineIndex: row['lineIndex'] as int,
      snippet: row['snippet'] as String? ?? '',
      rank: 1.0, // Default rank since FTS doesn't provide it directly
    )).toList();
  }

  /// Searches for text within a specific book.
  ///
  /// @param bookId The ID of the book to search in
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> searchInBook(int bookId, String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      WHERE line_search.bookId = ? AND line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', [bookId, ftsQuery, limit, offset]);

    return result.map((row) => SearchResult(
      bookId: row['bookId'] as int,
      bookTitle: row['bookTitle'] as String,
      lineId: row['id'] as int,
      lineIndex: row['lineIndex'] as int,
      snippet: row['snippet'] as String? ?? '',
      rank: 1.0, // Default rank since FTS doesn't provide it directly
    )).toList();
  }

  /// Searches for text in books by a specific author.
  ///
  /// @param author The author name to filter by
  /// @param query The search query
  /// @param limit Maximum number of results to return
  /// @param offset Number of results to skip (for pagination)
  /// @return A list of search results
  Future<List<SearchResult>> searchByAuthor(String author, String query, int limit, int offset) async {
    final ftsQuery = _prepareFtsQuery(query);
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT l.id, l.bookId, l.lineIndex, b.title as bookTitle, l.plainText,
             snippet(line_search, 4, '<b>', '</b>', '...', 50) as snippet
      FROM line_search
      JOIN line l ON line_search.id = l.id
      JOIN book b ON line_search.bookId = b.id
      JOIN book_author ba ON b.id = ba.bookId
      JOIN author a ON ba.authorId = a.id
      WHERE a.name LIKE ? AND line_search.plainText MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''', ['%$author%', ftsQuery, limit, offset]);

    return result.map((row) => SearchResult(
      bookId: row['bookId'] as int,
      bookTitle: row['bookTitle'] as String,
      lineId: row['id'] as int,
      lineIndex: row['lineIndex'] as int,
      snippet: row['snippet'] as String? ?? '',
      rank: 1.0, // Default rank since FTS doesn't provide it directly
    )).toList();
  }

  // --- Helpers ---

  /// Prepares a search query for full-text search.
  /// Adds wildcards and quotes to improve search results.
  ///
  /// @param query The raw search query
  /// @return The formatted query for FTS
  String _prepareFtsQuery(String query) {
    return query.trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '"$word"*')
        .join(' ');
  }

  /// Executes a raw SQL query.
  /// This is useful for operations that are not covered by the generated queries,
  /// such as enabling or disabling foreign key constraints.
  ///
  /// @param sql The SQL query to execute
  Future<void> executeRawQuery(String sql) async {
    _logger.fine('Executing raw SQL query: $sql');
    final db = await _database.database;
    await db.execute(sql);
    _logger.fine('Raw SQL query executed successfully');
  }

  // FTS5 removed - rebuildFts5Index function no longer needed
  // Future<void> rebuildFts5Index() async {
  //   _logger.fine('Rebuilding FTS5 index for line_search table');
  //   await executeRawQuery('INSERT INTO line_search(line_search) VALUES(\'rebuild\')');
  //   _logger.fine('FTS5 index rebuilt successfully');
  // }

  /// Updates the book_has_links table to indicate whether a book has source links, target links, or both.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasSourceLinks Whether the book has source links (true) or not (false)
  /// @param hasTargetLinks Whether the book has target links (true) or not (false)
  Future<void> updateBookHasLinks(int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    _logger.fine('Updating book_has_links for book $bookId: hasSourceLinks=$hasSourceLinks, hasTargetLinks=$hasTargetLinks');
    final db = await _database.database;
    await db.rawInsert('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      VALUES (?, ?, ?)
    ''', [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);

    _logger.fine('Updated book_has_links for book $bookId: hasSourceLinks=$hasSourceLinks, hasTargetLinks=$hasTargetLinks');
  }

  /// Updates only the source links status for a book.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasSourceLinks Whether the book has source links (true) or not (false)
  Future<void> updateBookSourceLinks(int bookId, bool hasSourceLinks) async {
    _logger.fine('Updating source links for book $bookId: hasSourceLinks=$hasSourceLinks');
    final db = await _database.database;
    await db.rawUpdate('UPDATE book_has_links SET hasSourceLinks = ? WHERE bookId = ?', [hasSourceLinks ? 1 : 0, bookId]);
    _logger.fine('Updated source links for book $bookId: hasSourceLinks=$hasSourceLinks');
  }

  /// Updates only the target links status for a book.
  ///
  /// @param bookId The ID of the book to update
  /// @param hasTargetLinks Whether the book has target links (true) or not (false)
  Future<void> updateBookTargetLinks(int bookId, bool hasTargetLinks) async {
    _logger.fine('Updating target links for book $bookId: hasTargetLinks=$hasTargetLinks');
    final db = await _database.database;
    await db.rawUpdate('UPDATE book_has_links SET hasTargetLinks = ? WHERE bookId = ?', [hasTargetLinks ? 1 : 0, bookId]);
    _logger.fine('Updated target links for book $bookId: hasTargetLinks=$hasTargetLinks');
  }

  // --- Connection type specific helpers ---

  Future<int> countLinksBySourceBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.sourceBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  Future<int> countLinksByTargetBookAndType(int bookId, String typeName) async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM link l
      JOIN connection_type ct ON l.connectionTypeId = ct.id
      WHERE l.targetBookId = ? AND ct.name = ?
    ''', [bookId, typeName]);
    return result.first.values.first as int;
  }

  Future<void> updateBookConnectionFlags(int bookId, bool hasTargum, bool hasReference, bool hasCommentary, bool hasOther) async {
    await _database.bookDao.updateBookConnectionFlags(bookId, hasTargum, hasReference, hasCommentary, hasOther);
  }

  /// Optimized version that updates all book connection flags in a single query
  /// This is MUCH faster than looping through books individually
  Future<void> updateAllBookConnectionFlagsOptimized() async {
    _logger.info('Updating all book connection flags with optimized query...');
    final db = await _database.database;
    
    // First, ensure connection_type table has all types
    final types = ['TARGUM', 'REFERENCE', 'COMMENTARY', 'OTHER'];
    for (final type in types) {
      await _getOrCreateConnectionType(type);
    }
    
    // Get connection type IDs
    final typeIds = <String, int>{};
    for (final type in types) {
      final result = await db.rawQuery('SELECT id FROM connection_type WHERE name = ?', [type]);
      if (result.isNotEmpty) {
        typeIds[type] = result.first['id'] as int;
      }
    }
    
    // Update book_has_links table with a single query
    await db.execute('''
      INSERT OR REPLACE INTO book_has_links (bookId, hasSourceLinks, hasTargetLinks)
      SELECT b.id,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE sourceBookId = b.id) THEN 1 ELSE 0 END,
             CASE WHEN EXISTS(SELECT 1 FROM link WHERE targetBookId = b.id) THEN 1 ELSE 0 END
      FROM book b
    ''');
    
    // Update connection flags in book table with optimized queries
    if (typeIds.containsKey('TARGUM')) {
      await db.execute('''
        UPDATE book SET hasTargumConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['TARGUM']}
          ) THEN 1 ELSE 0 END
      ''');
    }
    
    if (typeIds.containsKey('REFERENCE')) {
      await db.execute('''
        UPDATE book SET hasReferenceConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['REFERENCE']}
          ) THEN 1 ELSE 0 END
      ''');
    }
    
    if (typeIds.containsKey('COMMENTARY')) {
      await db.execute('''
        UPDATE book SET hasCommentaryConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['COMMENTARY']}
          ) THEN 1 ELSE 0 END
      ''');
    }
    
    if (typeIds.containsKey('OTHER')) {
      await db.execute('''
        UPDATE book SET hasOtherConnection = 
          CASE WHEN EXISTS(
            SELECT 1 FROM link 
            WHERE (sourceBookId = book.id OR targetBookId = book.id) 
            AND connectionTypeId = ${typeIds['OTHER']}
          ) THEN 1 ELSE 0 END
      ''');
    }
    
    _logger.info('All book connection flags updated successfully');
  }

  /// Checks if a book has any links (source or target).
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has any links, false otherwise
  Future<bool> bookHasAnyLinks(int bookId) async {
    _logger.fine('Checking if book $bookId has any links');

    // Check if the book has any links as source or target
    final hasSourceLinks = await bookHasSourceLinks(bookId);
    final hasTargetLinks = await bookHasTargetLinks(bookId);
    final result = hasSourceLinks || hasTargetLinks;

    _logger.fine('Book $bookId has any links: $result');
    return result;
  }

  /// Checks if a book has source links.
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has source links, false otherwise
  Future<bool> bookHasSourceLinks(int bookId) async {
    _logger.fine('Checking if book $bookId has source links');
    final count = await countLinksBySourceBook(bookId);
    final result = count > 0;
    _logger.fine('Book $bookId has source links: $result');
    return result;
  }

  /// Checks if a book has target links.
  ///
  /// @param bookId The ID of the book to check
  /// @return True if the book has target links, false otherwise
  Future<bool> bookHasTargetLinks(int bookId) async {
    _logger.fine('Checking if book $bookId has target links');
    final count = await countLinksByTargetBook(bookId);
    final result = count > 0;
    _logger.fine('Book $bookId has target links: $result');
    return result;
  }

  /// Checks if a book has OTHER type comments.
  Future<bool> bookHasOtherComments(int bookId) async {
    _logger.fine('Checking if book $bookId has OTHER comments');
    final book = await _database.bookDao.getBookById(bookId);
    final result = book?.hasOtherConnection ?? false;
    _logger.fine('Book $bookId has OTHER comments: $result');
    return result;
  }

  /// Checks if a book has COMMENTARY type comments.
  Future<bool> bookHasCommentaryComments(int bookId) async {
    _logger.fine('Checking if book $bookId has COMMENTARY comments');
    final book = await _database.bookDao.getBookById(bookId);
    final result = book?.hasCommentaryConnection ?? false;
    _logger.fine('Book $bookId has COMMENTARY comments: $result');
    return result;
  }

  /// Checks if a book has REFERENCE type comments.
  Future<bool> bookHasReferenceComments(int bookId) async {
    _logger.fine('Checking if book $bookId has REFERENCE comments');
    final book = await _database.bookDao.getBookById(bookId);
    final result = book?.hasReferenceConnection ?? false;
    _logger.fine('Book $bookId has REFERENCE comments: $result');
    return result;
  }

  /// Checks if a book has TARGUM type comments.
  Future<bool> bookHasTargumComments(int bookId) async {
    _logger.fine('Checking if book $bookId has TARGUM comments');
    final book = await _database.bookDao.getBookById(bookId);
    final result = book?.hasTargumConnection ?? false;
    _logger.fine('Book $bookId has TARGUM comments: $result');
    return result;
  }

  /// Gets all books that have any links (source or target).
  ///
  /// @return A list of books that have any links
  Future<List<Book>> getBooksWithAnyLinks() async {
    _logger.fine('Getting all books with any links');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1 OR bhl.hasTargetLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');
    _logger.fine('Found ${result.length} books with any links');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Gets all books that have source links.
  ///
  /// @return A list of books that have source links
  Future<List<Book>> getBooksWithSourceLinks() async {
    _logger.fine('Getting all books with source links');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasSourceLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');
    _logger.fine('Found ${result.length} books with source links');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Gets all books that have target links.
  ///
  /// @return A list of books that have target links
  Future<List<Book>> getBooksWithTargetLinks() async {
    _logger.fine('Getting all books with target links');
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT b.* FROM book b
      JOIN book_has_links bhl ON b.id = bhl.bookId
      WHERE bhl.hasTargetLinks = 1
      ORDER BY b.orderIndex, b.title
    ''');
    _logger.fine('Found ${result.length} books with target links');

    // Convert the database books to model books
    return Future.wait(result.map((row) async {
      final bookData = Book.fromJson(row);
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Counts the number of books that have any links (source or target).
  ///
  /// @return The number of books that have any links
  Future<int> countBooksWithAnyLinks() async {
    _logger.fine('Counting books with any links');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1 OR hasTargetLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with any links');
    return count;
  }

  /// Counts the number of books that have source links.
  ///
  /// @return The number of books that have source links
  Future<int> countBooksWithSourceLinks() async {
    _logger.fine('Counting books with source links');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasSourceLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with source links');
    return count;
  }

  /// Counts the number of books that have target links.
  ///
  /// @return The number of books that have target links
  Future<int> countBooksWithTargetLinks() async {
    _logger.fine('Counting books with target links');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM book_has_links WHERE hasTargetLinks = 1');
    final count = result.first.values.first as int;
    _logger.fine('Found $count books with target links');
    return count;
  }

  /// Gets all books from the database.
  ///
  /// @return A list of all books
  Future<List<Book>> getAllBooks() async {
    _logger.fine('Getting all books');
    final books = await _database.bookDao.getAllBooks();
    _logger.fine('Found ${books.length} books');

    // Convert the database books to model books
    return Future.wait(books.map((bookData) async {
      final authors = await _getBookAuthors(bookData.id);
      final topics = await _getBookTopics(bookData.id);
      final pubPlaces = await _getBookPubPlaces(bookData.id);
      final pubDates = await _getBookPubDates(bookData.id);
      return bookData.copyWith(
        authors: authors,
        topics: topics,
        pubPlaces: pubPlaces,
        pubDates: pubDates,
      );
    }));
  }

  /// Counts the total number of books in the database.
  ///
  /// @return The total number of books
  Future<int> countAllBooks() async {
    _logger.fine('Counting all books');
    final count = await _database.bookDao.countAllBooks();
    _logger.fine('Found $count books');
    return count;
  }

  /// Counts the number of links where the given book is the source.
  ///
  /// @param bookId The ID of the book to count links for
  /// @return The number of links where the book is the source
  Future<int> countLinksBySourceBook(int bookId) async {
    _logger.fine('Counting links where book $bookId is the source');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM link WHERE sourceBookId = ?', [bookId]);
    final count = result.first.values.first as int;
    _logger.fine('Found $count links where book $bookId is the source');
    return count;
  }

  /// Counts the number of links where the given book is the target.
  ///
  /// @param bookId The ID of the book to count links for
  /// @return The number of links where the book is the target
  Future<int> countLinksByTargetBook(int bookId) async {
    _logger.fine('Counting links where book $bookId is the target');
    final db = await _database.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM link WHERE targetBookId = ?', [bookId]);
    final count = result.first.values.first as int;
    _logger.fine('Found $count links where book $bookId is the target');
    return count;
  }

  /// Finalizes database settings after bulk operations
  Future<void> finalizeDatabase() async {
    _logger.info('Finalizing database settings...');
    await _executeRawQuery('PRAGMA synchronous=FULL');
    await _executeRawQuery('PRAGMA locking_mode=NORMAL');
    _logger.info('Database finalized');
  }

  /// Creates optimization indexes for faster queries
  Future<void> createOptimizationIndexes() async {
    _logger.info('Creating optimization indexes...');
    
    final db = await _database.database;
    
    // Indexes for book searches
    await db.execute('CREATE INDEX IF NOT EXISTS idx_book_title ON book(title)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_book_category ON book(categoryId)');
    
    // Indexes for lines
    await db.execute('CREATE INDEX IF NOT EXISTS idx_line_book_index ON line(bookId, lineIndex)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_line_toc ON line(tocEntryId)');
    
    // Indexes for links - CRITICAL for performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_link_source ON link(sourceBookId, sourceLineId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_link_target ON link(targetBookId, targetLineId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_link_type ON link(connectionTypeId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_link_source_type ON link(sourceBookId, connectionTypeId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_link_target_type ON link(targetBookId, connectionTypeId)');
    
    // Indexes for authors and topics
    await db.execute('CREATE INDEX IF NOT EXISTS idx_author_name ON author(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_topic_name ON topic(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_book_author ON book_author(bookId, authorId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_book_topic ON book_topic(bookId, topicId)');
    
    // Index for line_toc mapping table
    await db.execute('CREATE INDEX IF NOT EXISTS idx_line_toc_line ON line_toc(lineId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_line_toc_entry ON line_toc(tocEntryId)');
    
    _logger.info('Optimization indexes created');
  }

  /// Closes the database connection.
  /// Should be called when the repository is no longer needed.
  Future<void> close() async {
    await _database.close();
  }

  /// Executes a raw SQL query.
  /// This is useful for operations that are not covered by the generated queries,
  /// such as enabling or disabling foreign key constraints.
  ///
  /// @param sql The SQL query to execute
  Future<void> _executeRawQuery(String sql) async {
    _logger.fine('Executing raw SQL query: $sql');
    final db = await _database.database;
    await db.execute(sql);
    _logger.fine('Raw SQL query executed successfully');
  }

  /// Disables foreign key constraints.
  Future<void> disableForeignKeys() async {
    await _executeRawQuery('PRAGMA foreign_keys = OFF');
  }

  /// Enables foreign key constraints.
  Future<void> enableForeignKeys() async {
    await _executeRawQuery('PRAGMA foreign_keys = ON');
  }

  /// Checks if a book with the given title already exists in the database.
  /// Returns the book if found, null otherwise.
  Future<Book?> checkBookExists(String title) async {
    _logger.fine('Checking if book exists: $title');
    return await _database.bookDao.getBookByTitle(title);
  }

  /// Deletes a book and all its related data (lines, TOC entries, links, etc.)
  /// This is useful when replacing an existing book.
  Future<void> deleteBookCompletely(int bookId) async {
    _logger.info('Deleting book completely: $bookId');
    
    // Delete all related data first (due to foreign key constraints)
    final db = await _database.database;
    
    // Delete links where this book is source or target
    await db.rawDelete('DELETE FROM link WHERE sourceBookId = ? OR targetBookId = ?', [bookId, bookId]);
    
    // Delete book_has_links
    await db.rawDelete('DELETE FROM book_has_links WHERE bookId = ?', [bookId]);
    
    // Delete TOC entries
    await db.rawDelete('DELETE FROM tocEntry WHERE bookId = ?', [bookId]);
    
    // Delete lines
    await db.rawDelete('DELETE FROM line WHERE bookId = ?', [bookId]);
    
    // Delete junction tables
    await db.rawDelete('DELETE FROM book_author WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_topic WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_pub_place WHERE bookId = ?', [bookId]);
    await db.rawDelete('DELETE FROM book_pub_date WHERE bookId = ?', [bookId]);
    
    // Finally delete the book itself
    await _database.bookDao.deleteBook(bookId);
    
    _logger.info('Book $bookId deleted completely');
  }
}

// Data classes for enriched results

/// Information about a commentator (author who comments on other books).
///
/// @property bookId The ID of the commentator's book
/// @property title The title of the commentator's book
/// @property author The name of the commentator
/// @property linkCount The number of links (comments) by this commentator
class CommentatorInfo {
  final int bookId;
  final String title;
  final String? author;
  final int linkCount;

  const CommentatorInfo({
    required this.bookId,
    required this.title,
    this.author,
    required this.linkCount,
  });
}

/// A commentary with its text content.
///
/// @property link The link connecting the source text to the commentary
/// @property targetBookTitle The title of the book containing the commentary
/// @property targetText The text of the commentary
class CommentaryWithText {
  final Link link;
  final String targetBookTitle;
  final String targetText;

  const CommentaryWithText({
    required this.link,
    required this.targetBookTitle,
    required this.targetText,
  });
}

/// Mapping between a line and its TOC entry
class LineTocMapping {
  final int lineId;
  final int tocEntryId;

  const LineTocMapping({
    required this.lineId,
    required this.tocEntryId,
  });
}
