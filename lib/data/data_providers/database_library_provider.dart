import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/core/models/category.dart' as db_models;
import 'package:otzaria/migration/core/models/book.dart' as db_models;

/// Library provider that loads books from the SQLite database.
class DatabaseLibraryProvider implements LibraryProvider {
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;
  final Set<String> _cachedTitles = {};
  bool _titlesCached = false;

  /// Singleton instance
  static DatabaseLibraryProvider? _instance;

  DatabaseLibraryProvider._();

  static DatabaseLibraryProvider get instance {
    _instance ??= DatabaseLibraryProvider._();
    return _instance!;
  }

  @override
  String get providerId => 'database';

  @override
  String get displayName => 'מסד נתונים';

  @override
  String get sourceIndicator => 'DB';

  @override
  int get priority => 1; // Higher priority than file system

  @override
  bool get isInitialized => _sqliteProvider.isInitialized;

  @override
  Future<void> initialize() async {
    await _sqliteProvider.initialize();
    debugPrint('💾 DatabaseLibraryProvider initialized');
  }

  @override
  Future<Map<String, List<Book>>> loadBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    final Map<String, List<Book>> booksByCategory = {};

    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty');
      return booksByCategory;
    }

    try {
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
      debugPrint('💾 Database found ${dbBooks.length} books');

      // Cache titles for quick lookup
      _cachedTitles.clear();
      
      for (final dbBook in dbBooks) {
        _cachedTitles.add(dbBook.title);
        
        final categoryName = dbBook.topics.isNotEmpty
            ? dbBook.topics.first.name
            : 'ללא קטגוריה';

        final book = TextBook(
          title: dbBook.title,
          author: dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null,
          heShortDesc: dbBook.heShortDesc,
          pubDate: dbBook.pubDates.isNotEmpty ? dbBook.pubDates.first.date : null,
          pubPlace: dbBook.pubPlaces.isNotEmpty ? dbBook.pubPlaces.first.name : null,
          order: dbBook.order.toInt(),
          topics: dbBook.topics.map((t) => t.name).join(', '),
        );

        booksByCategory.putIfAbsent(categoryName, () => []);
        booksByCategory[categoryName]!.add(book);
      }
      
      _titlesCached = true;
      debugPrint('💾 Database loaded ${dbBooks.length} books into ${booksByCategory.length} categories');
    } catch (e) {
      debugPrint('⚠️ Error loading books from database: $e');
    }

    return booksByCategory;
  }

  @override
  Future<bool> hasBook(String title) async {
    // Use cached titles if available
    if (_titlesCached) {
      return _cachedTitles.contains(title);
    }
    return await _sqliteProvider.isBookInDatabase(title);
  }

  @override
  Future<String?> getBookText(String title) async {
    return await _sqliteProvider.getBookTextFromDb(title);
  }

  @override
  Future<List<TocEntry>?> getBookToc(String title) async {
    return await _sqliteProvider.getBookTocFromDb(title);
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    if (_titlesCached) {
      return Set.from(_cachedTitles);
    }

    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return {};
    }

    try {
      final dbBooks = await _sqliteProvider.repository!.getAllBooks();
      _cachedTitles.clear();
      for (final book in dbBooks) {
        _cachedTitles.add(book.title);
      }
      _titlesCached = true;
      return Set.from(_cachedTitles);
    } catch (e) {
      debugPrint('⚠️ Error getting book titles from database: $e');
      return {};
    }
  }

  /// Clears the cached titles (call when database changes)
  void clearCache() {
    _cachedTitles.clear();
    _titlesCached = false;
    debugPrint('💾 Database cache cleared');
  }

  /// Gets database statistics
  Future<Map<String, int>> getStats() async {
    return await _sqliteProvider.getDatabaseStats();
  }

  /// Gets the underlying SQLite provider for advanced operations
  SqliteDataProvider get sqliteProvider => _sqliteProvider;

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty library');
      return Library(categories: []);
    }

    debugPrint('💾 Building library catalog from database...');
    
    final repository = _sqliteProvider.repository!;
    
    // Get all books grouped by category
    final allDbBooks = await repository.database.bookDao.getAllBooks();
    final booksByCategory = <int, List<db_models.Book>>{};
    
    for (final book in allDbBooks) {
      booksByCategory.putIfAbsent(book.categoryId, () => []);
      booksByCategory[book.categoryId]!.add(book);
    }
    
    debugPrint('💾 Building catalog from ${allDbBooks.length} books');

    // Build catalog tree starting from root categories
    final rootCategories = await repository.getRootCategories();
    final Library library = Library(categories: []);
    
    int totalCategories = 0;
    for (final rootCategory in rootCategories) {
      final catalogCategory = await _buildCatalogCategoryRecursive(
        rootCategory,
        booksByCategory,
        repository,
        library,
        metadata,
      );
      library.subCategories.add(catalogCategory);
      totalCategories += _countCategories(catalogCategory);
    }

    // Sort all categories and books
    _sortLibraryRecursive(library);

    debugPrint('💾 Database catalog built with $totalCategories categories and ${allDbBooks.length} books');
    return library;
  }

  /// Recursively builds a catalog category with its subcategories and books.
  Future<Category> _buildCatalogCategoryRecursive(
    db_models.Category dbCategory,
    Map<int, List<db_models.Book>> booksByCategory,
    dynamic repository,
    Category parent,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    // Create the category
    final category = Category(
      title: dbCategory.title,
      description: metadata[dbCategory.title]?['heDesc'] ?? '',
      shortDescription: metadata[dbCategory.title]?['heShortDesc'] ?? '',
      order: metadata[dbCategory.title]?['order'] ?? 999,
      subCategories: [],
      books: [],
      parent: parent,
    );

    // Add books in this category
    final dbBooks = booksByCategory[dbCategory.id] ?? [];
    for (final dbBook in dbBooks) {
      final book = _convertDbBookToBook(dbBook, category, metadata);
      category.books.add(book);
      _cachedTitles.add(dbBook.title);
    }

    // Get subcategories and build them recursively
    final children = await repository.getCategoryChildren(dbCategory.id);
    for (final child in children) {
      final subCategory = await _buildCatalogCategoryRecursive(
        child,
        booksByCategory,
        repository,
        category,
        metadata,
      );
      category.subCategories.add(subCategory);
    }

    return category;
  }

  /// Converts a database book model to the app's Book model.
  Book _convertDbBookToBook(
    db_models.Book dbBook,
    Category category,
    Map<String, Map<String, dynamic>> metadata,
  ) {
    final bookMeta = metadata[dbBook.title];
    
    return TextBook(
      title: dbBook.title,
      category: category,
      author: dbBook.authors.isNotEmpty 
          ? dbBook.authors.first.name 
          : bookMeta?['author'],
      heShortDesc: dbBook.heShortDesc ?? bookMeta?['heShortDesc'],
      pubDate: dbBook.pubDates.isNotEmpty 
          ? dbBook.pubDates.first.date 
          : bookMeta?['pubDate'],
      pubPlace: dbBook.pubPlaces.isNotEmpty 
          ? dbBook.pubPlaces.first.name 
          : bookMeta?['pubPlace'],
      order: dbBook.order.toInt(),
      topics: dbBook.topics.map((t) => t.name).join(', '),
    );
  }

  /// Counts the total number of categories in the tree.
  int _countCategories(Category category) {
    return 1 + category.subCategories.fold(0, (sum, sub) => sum + _countCategories(sub));
  }

  /// Recursively sorts all categories and books in the library.
  void _sortLibraryRecursive(Category category) {
    category.subCategories.sort((a, b) => a.order.compareTo(b.order));
    category.books.sort((a, b) => a.order.compareTo(b.order));

    for (final subCat in category.subCategories) {
      _sortLibraryRecursive(subCat);
    }
  }

  @override
  Future<List<Link>> getAllLinksForBook(String title) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      debugPrint('💾 Database not initialized, returning empty links');
      return [];
    }

    try {
      final book = await _sqliteProvider.repository!.getBookByTitle(title);
      if (book == null) {
        debugPrint('💾 Book "$title" not found in database');
        return [];
      }

      final db = await _sqliteProvider.repository!.database.database;
      
      // Get all links where this book is the source
      final result = await db.rawQuery('''
        SELECT 
          l.sourceLineId,
          l.targetLineId,
          sl.lineIndex as sourceLineIndex,
          tl.lineIndex as targetLineIndex,
          tb.title as targetBookTitle,
          ct.name as connectionTypeName
        FROM link l
        JOIN line sl ON l.sourceLineId = sl.id
        JOIN line tl ON l.targetLineId = tl.id
        JOIN book tb ON l.targetBookId = tb.id
        LEFT JOIN connection_type ct ON l.connectionTypeId = ct.id
        WHERE l.sourceBookId = ?
        ORDER BY sl.lineIndex
      ''', [book.id]);

      final links = result.map((row) {
        final targetTitle = row['targetBookTitle'] as String;
        final connectionType = row['connectionTypeName'] as String? ?? 'reference';
        
        return Link(
          heRef: targetTitle,
          index1: (row['sourceLineIndex'] as int) + 1,
          path2: targetTitle,
          index2: (row['targetLineIndex'] as int) + 1,
          connectionType: connectionType,
        );
      }).toList();

      debugPrint('💾 Found ${links.length} links for book "$title"');
      return links;
    } catch (e) {
      debugPrint('⚠️ Error getting links for book "$title": $e');
      return [];
    }
  }

  @override
  Future<String> getLinkContent(Link link) async {
    if (!_sqliteProvider.isInitialized || _sqliteProvider.repository == null) {
      return 'שגיאה: מסד הנתונים לא מאותחל';
    }

    try {
      if (link.path2.isEmpty) {
        return 'שגיאה: נתיב ריק';
      }

      if (link.index2 <= 0) {
        return 'שגיאה: אינדקס לא תקין';
      }

      // Get the target book text and extract the specific line
      final targetTitle = link.path2.contains('/') 
          ? link.path2.split('/').last.replaceAll('.txt', '')
          : link.path2;
      
      final bookText = await _sqliteProvider.getBookTextFromDb(targetTitle);
      if (bookText == null) {
        return 'שגיאה: הספר לא נמצא במסד הנתונים';
      }

      final lines = bookText.split('\n');
      if (link.index2 < 1 || link.index2 > lines.length) {
        return 'שגיאה: אינדקס מחוץ לטווח';
      }

      return lines[link.index2 - 1];
    } catch (e) {
      debugPrint('⚠️ Error loading link content from database: $e');
      return 'שגיאה בטעינת תוכן המפרש: $e';
    }
  }
}
