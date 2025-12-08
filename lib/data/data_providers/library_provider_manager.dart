import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';

/// Manages multiple library providers and coordinates book loading.
/// 
/// This class is responsible for:
/// - Initializing all providers
/// - Loading books from all providers
/// - Resolving conflicts (same book in multiple providers)
/// - Providing unified access to book content
class LibraryProviderManager {
  final List<LibraryProvider> _providers = [];
  final Map<String, LibraryProvider> _bookToProvider = {};
  bool _isInitialized = false;

  /// Singleton instance
  static LibraryProviderManager? _instance;

  LibraryProviderManager._();

  static LibraryProviderManager get instance {
    _instance ??= LibraryProviderManager._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  /// Gets all registered providers
  List<LibraryProvider> get providers => List.unmodifiable(_providers);

  /// Gets the file system provider
  FileSystemLibraryProvider get fileSystemProvider =>
      FileSystemLibraryProvider.instance;

  /// Gets the database provider
  DatabaseLibraryProvider get databaseProvider =>
      DatabaseLibraryProvider.instance;

  /// Initializes all providers
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Register providers in priority order
    _providers.clear();
    _providers.add(DatabaseLibraryProvider.instance);
    _providers.add(FileSystemLibraryProvider.instance);

    // Sort by priority (lower = higher priority)
    _providers.sort((a, b) => a.priority.compareTo(b.priority));

    // Initialize all providers
    for (final provider in _providers) {
      try {
        await provider.initialize();
        debugPrint('✅ Initialized provider: ${provider.displayName}');
      } catch (e) {
        debugPrint('⚠️ Failed to initialize provider ${provider.displayName}: $e');
      }
    }

    _isInitialized = true;
    debugPrint('📚 LibraryProviderManager initialized with ${_providers.length} providers');
  }

  /// Loads all books from all providers.
  /// 
  /// Returns a map of category name -> list of books.
  /// Books from higher priority providers take precedence.
  Future<Map<String, List<Book>>> loadAllBooks(
      Map<String, Map<String, dynamic>> metadata) async {
    if (!_isInitialized) await initialize();

    final Map<String, List<Book>> allBooksByCategory = {};
    final Set<String> loadedTitles = {};
    _bookToProvider.clear();

    // Load from each provider in priority order
    for (final provider in _providers) {
      if (!provider.isInitialized) continue;

      try {
        final books = await provider.loadBooks(metadata);

        for (final entry in books.entries) {
          final categoryName = entry.key;
          final categoryBooks = entry.value;

          allBooksByCategory.putIfAbsent(categoryName, () => []);

          for (final book in categoryBooks) {
            // Skip if already loaded from higher priority provider
            if (loadedTitles.contains(book.title)) {
              debugPrint('⏭️ Skipping "${book.title}" - already loaded from ${_bookToProvider[book.title]?.displayName}');
              continue;
            }

            allBooksByCategory[categoryName]!.add(book);
            loadedTitles.add(book.title);
            _bookToProvider[book.title] = provider;
          }
        }

        debugPrint('📚 Loaded ${books.values.expand((b) => b).length} books from ${provider.displayName}');
      } catch (e) {
        debugPrint('⚠️ Error loading books from ${provider.displayName}: $e');
      }
    }

    debugPrint('📚 Total: ${loadedTitles.length} unique books loaded');
    return allBooksByCategory;
  }

  /// Gets the provider that owns a specific book
  LibraryProvider? getProviderForBook(String title) {
    return _bookToProvider[title];
  }

  /// Gets the data source indicator for a book
  Future<String> getBookDataSource(String title) async {
    // Check if it's a personal book first
    if (await fileSystemProvider.isPersonalBook(title)) {
      return 'א';
    }

    final provider = _bookToProvider[title];
    return provider?.sourceIndicator ?? 'ק';
  }

  /// Gets the text content of a book from the appropriate provider
  Future<String?> getBookText(String title) async {
    final provider = _bookToProvider[title];
    if (provider != null) {
      return await provider.getBookText(title);
    }

    // Fallback: try each provider
    for (final p in _providers) {
      if (await p.hasBook(title)) {
        final text = await p.getBookText(title);
        if (text != null) return text;
      }
    }

    return null;
  }

  /// Gets the table of contents for a book from the appropriate provider
  Future<List<TocEntry>?> getBookToc(String title) async {
    final provider = _bookToProvider[title];
    if (provider != null) {
      return await provider.getBookToc(title);
    }

    // Fallback: try each provider
    for (final p in _providers) {
      if (await p.hasBook(title)) {
        final toc = await p.getBookToc(title);
        if (toc != null && toc.isNotEmpty) return toc;
      }
    }

    return null;
  }

  /// Checks if a book exists in any provider
  Future<bool> bookExists(String title) async {
    for (final provider in _providers) {
      if (await provider.hasBook(title)) {
        return true;
      }
    }
    return false;
  }

  /// Clears all caches
  void clearCaches() {
    _bookToProvider.clear();
    databaseProvider.clearCache();
    fileSystemProvider.refresh();
    debugPrint('🔄 All provider caches cleared');
  }

  /// Gets the content of a specific link from the appropriate provider
  Future<String> getLinkContent(Link link) async {
    // Try to find the provider for the target book
    final targetTitle = link.path2.split('/').last.replaceAll('.txt', '');
    final provider = _bookToProvider[targetTitle];
    
    if (provider != null) {
      return await provider.getLinkContent(link);
    }

    // Fallback: try each provider
    for (final p in _providers) {
      try {
        final content = await p.getLinkContent(link);
        if (content.isNotEmpty && !content.startsWith('שגיאה')) {
          return content;
        }
      } catch (e) {
        continue;
      }
    }

    return 'שגיאה: לא נמצא תוכן';
  }

  /// Gets statistics from all providers
  Future<Map<String, dynamic>> getStats() async {
    final stats = <String, dynamic>{
      'providers': _providers.length,
      'totalBooks': _bookToProvider.length,
    };

    // Add database stats
    final dbStats = await databaseProvider.getStats();
    stats['database'] = dbStats;

    // Count books per provider
    final bookCounts = <String, int>{};
    for (final entry in _bookToProvider.entries) {
      final providerName = entry.value.displayName;
      bookCounts[providerName] = (bookCounts[providerName] ?? 0) + 1;
    }
    stats['booksByProvider'] = bookCounts;

    return stats;
  }

  /// Builds a unified library catalog from all providers.
  /// 
  /// This method delegates to the highest priority provider that is initialized.
  /// The database provider builds from the database structure,
  /// while the file system provider builds from the folder hierarchy.
  /// 
  /// [metadata] - Book metadata for enriching book information
  /// [rootPath] - The root path of the library (e.g., 'אוצריא' folder)
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    if (!_isInitialized) await initialize();

    // Use the highest priority provider that is initialized
    for (final provider in _providers) {
      if (provider.isInitialized) {
        debugPrint('📚 Building catalog from ${provider.displayName}');
        final library = await provider.buildLibraryCatalog(metadata, rootPath);
        
        // Update book to provider mapping
        _updateBookToProviderMapping(library, provider);
        
        debugPrint('✅ Library catalog built with ${library.subCategories.length} top-level categories');
        return library;
      }
    }

    debugPrint('⚠️ No initialized provider found, returning empty library');
    return Library(categories: []);
  }

  /// Updates the book to provider mapping from a library catalog.
  void _updateBookToProviderMapping(Library library, LibraryProvider provider) {
    _bookToProvider.clear();
    _mapBooksRecursive(library, provider);
  }

  /// Recursively maps all books in a category to their provider.
  void _mapBooksRecursive(Category category, LibraryProvider provider) {
    for (final book in category.books) {
      _bookToProvider[book.title] = provider;
    }
    for (final subCat in category.subCategories) {
      _mapBooksRecursive(subCat, provider);
    }
  }
}
