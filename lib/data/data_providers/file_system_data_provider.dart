import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/toc_parser.dart';

/// A data provider that manages file system operations for the library.
///
/// This class handles all file system related operations including:
/// - Reading and parsing book content from various file formats (txt, docx, pdf)
/// - Managing the library structure (categories and books)
/// - Handling external book data from CSV files
/// - Managing book links and metadata
/// - Providing table of contents functionality
class FileSystemData {
  /// Future that resolves to a mapping of book titles to their file system paths
  late Future<Map<String, String>> titleToPath;

  late String libraryPath;

  /// Future that resolves to metadata for all books and categories
  late Future<Map<String, Map<String, dynamic>>> metadata;

  /// Library provider manager for coordinating multiple data sources
  final LibraryProviderManager _providerManager =
      LibraryProviderManager.instance;

  /// Creates a new instance of [FileSystemData] and initializes the title to path mapping
  /// and metadata
  FileSystemData() {
    libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    _initializeProviders();
  }

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Initializes the library providers
  Future<void> _initializeProviders() async {
    try {
      await _providerManager.initialize();
      debugPrint('Library providers initialized in FileSystemData');
    } catch (e) {
      debugPrint('Provider initialization failed: $e');
    }
  }

  /// Checks if a book is stored in the database
  Future<bool> isBookInDatabase(String title) async {
    return await _providerManager.databaseProvider.hasBook(title);
  }

  /// Gets the data source for a book (DB, File, or Personal)
  /// Returns: 'DB' for database, 'ק' for file, 'א' for personal
  Future<String> getBookDataSource(String title) async {
    return await _providerManager.getBookDataSource(title);
  }

  /// Clears the book-in-database cache
  void clearBookCache() {
    _providerManager.clearCaches();
    debugPrint('Book cache cleared');
  }

  /// Gets statistics about database usage
  Future<Map<String, dynamic>> getDatabaseStats() async {
    return await _providerManager.getStats();
  }

  /// Gets the library provider manager for advanced operations
  LibraryProviderManager get providerManager => _providerManager;

  /// Gets the file system provider
  FileSystemLibraryProvider get fileSystemProvider =>
      _providerManager.fileSystemProvider;

  /// Gets the database provider
  DatabaseLibraryProvider get databaseProvider =>
      _providerManager.databaseProvider;

  /// Checks if a book is in the personal folder
  Future<bool> isPersonalBook(String title) async {
    return await _providerManager.fileSystemProvider.isPersonalBook(title);
  }

  /// Gets the path to the personal books folder
  String getPersonalBooksPath() {
    return _providerManager.fileSystemProvider.getPersonalBooksPath();
  }

  /// Ensures the personal books folder exists
  Future<void> ensurePersonalFolderExists() async {
    await _providerManager.fileSystemProvider.ensurePersonalFolderExists();
  }

  /// Retrieves the complete library structure from the file system.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  /// Uses LibraryProviderManager for unified catalog building.
  Future<Library> getLibrary() async {
    // בדיקה שהתיקייה הראשית קיימת
    final rootDir = Directory(libraryPath);
    if (!rootDir.existsSync()) {
      debugPrint('Library root directory does not exist: $libraryPath');
      return Library(categories: []);
    }

    // בדיקה שתיקיית אוצריא קיימת
    final otzariaPath = '$libraryPath${Platform.pathSeparator}אוצריא';
    final otzariaDir = Directory(otzariaPath);
    if (!otzariaDir.existsSync()) {
      debugPrint('Otzaria directory does not exist: $otzariaPath');
      return Library(categories: []);
    }

    titleToPath = _getTitleToPath();
    metadata = _getMetadata();

    // Use the unified catalog builder from LibraryProviderManager
    return _providerManager.buildLibraryCatalog(
      await metadata,
      otzariaPath,
    );
  }

  /// Retrieves the list of books from Otzar HaChochma
  static Future<List<ExternalBook>> getOtzarBooks() {
    return _getOtzarBooks();
  }

  /// Retrieves the list of books from HebrewBooks
  static Future<List<Book>> getHebrewBooks() {
    return _getHebrewBooks();
  }

  /// Loads a CSV file from assets and parses it into a table using Isolate.
  static Future<List<List<dynamic>>> _loadCsvTable(String assetPath,
      {bool shouldParseNumbers = false}) async {
    final csvData = await rootBundle.loadString(assetPath);
    return await Isolate.run(() {
      // Normalize line endings for cross-platform compatibility
      final normalizedCsvData =
          csvData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      return CsvToListConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
        shouldParseNumbers: shouldParseNumbers,
      ).convert(normalizedCsvData);
    });
  }

  /// Internal implementation for loading Otzar HaChochma books from CSV
  static Future<List<ExternalBook>> _getOtzarBooks() async {
    try {
      final table = await _loadCsvTable('assets/otzar_books.csv',
          shouldParseNumbers: false);
      return table.skip(1).map((row) {
        return ExternalBook(
          title: row[1],
          id: int.tryParse(row[0]) ?? -1,
          author: row[2],
          pubPlace: row[3],
          pubDate: row[4],
          topics: row[5],
          link: row[7],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Internal implementation for loading HebrewBooks from CSV
  static Future<List<Book>> _getHebrewBooks() async {
    try {
      final hebrewBooksPath =
          Settings.getValue<String>('key-hebrew-books-path');

      final table = await _loadCsvTable('assets/hebrew_books.csv',
          shouldParseNumbers: true);

      final books = <Book>[];
      for (final row in table.skip(1)) {
        try {
          if (row[0] == null || row[0].toString().isEmpty) continue;

          // Check if the ID is numeric
          final bookId = row[0].toString().trim();
          if (!RegExp(r'^\d+$').hasMatch(bookId)) continue;
          String? localPath;

          if (hebrewBooksPath != null) {
            localPath =
                '$hebrewBooksPath${Platform.pathSeparator}Hebrewbooks_org_$bookId.pdf';
            if (!File(localPath).existsSync()) {
              localPath =
                  '$hebrewBooksPath${Platform.pathSeparator}$bookId.pdf';
              if (!File(localPath).existsSync()) {
                localPath = null;
              }
            }
          }

          if (localPath != null) {
            // If local file exists, add as PdfBook
            books.add(PdfBook(
              title: row[1].toString(),
              path: localPath,
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
            ));
          } else {
            // If no local file, add as ExternalBook
            books.add(ExternalBook(
              title: row[1].toString(),
              id: int.parse(bookId),
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
              link: 'https://beta.hebrewbooks.org/$bookId',
            ));
          }
        } catch (e) {
          debugPrint('Error loading book: $e');
        }
      }
      return books;
    } catch (e) {
      debugPrint('Error loading hebrewbooks: $e');
      return [];
    }
  }

  /// Retrieves all links associated with a specific book.
  ///
  /// Links are stored in JSON files named '[book_title]_links.json' in the links directory.
  Future<List<Link>> getAllLinksForBook(String title) async {
    try {
      File file = File(_getLinksPath(title));
      final jsonString = await file.readAsString();
      final jsonList =
          await Isolate.run(() async => jsonDecode(jsonString) as List);
      return jsonList.map((json) => Link.fromJson(json)).toList();
    } on Exception {
      return [];
    }
  }

  /// Retrieves the text content of a book.
  ///
  /// Uses LibraryProviderManager to get text from the appropriate provider.
  Future<String> getBookText(String title) async {
    final text = await _providerManager.getBookText(title);
    if (text != null) {
      return text;
    }

    // Fallback to direct file system access
    debugPrint(
        '⚠️ Provider manager failed, falling back to direct file access for "$title"');
    final path = await _getBookPath(title);
    if (path.startsWith('error:')) {
      throw Exception('Book not found: $title');
    }

    final file = File(path);
    return file.readAsString();
  }

  /// Saves text content to a book file.
  ///
  /// Only supports plain text files (.txt). DOCX files cannot be edited.
  /// Creates a backup of the original file before saving.
  Future<void> saveBookText(String title, String content) async {
    await _providerManager.fileSystemProvider.saveBookText(title, content);
  }

  /// Retrieves the content of a specific link within a book.
  ///
  /// Reads the file line by line and returns the content at the specified index.
  Future<String> getLinkContent(Link link) async {
    try {
      // Validate link data first
      if (link.path2.isEmpty) {
        debugPrint('⚠️ Empty path in link');
        return 'שגיאה: נתיב ריק';
      }

      if (link.index2 <= 0) {
        debugPrint('⚠️ Invalid index in link: ${link.index2}');
        return 'שגיאה: אינדקס לא תקין';
      }

      String path = await _getBookPath(getTitleFromPath(link.path2));
      if (path.startsWith('error:')) {
        debugPrint('⚠️ Book path not found for: ${link.path2}');
        return 'שגיאה בטעינת קובץ: ${link.path2}';
      }

      // Check if file exists before trying to read it
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('⚠️ File does not exist: $path');
        return 'שגיאה: הקובץ לא נמצא';
      }

      return await getLineFromFile(path, link.index2).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Timeout reading line from file: $path');
          return 'שגיאה: פג זמן קריאת הקובץ';
        },
      );
    } catch (e) {
      debugPrint('⚠️ Error loading link content: $e');
      return 'שגיאה בטעינת תוכן המפרש: $e';
    }
  }

  /// Returns a list of all book paths in the library directory.
  ///
  /// This operation is performed in an isolate to prevent blocking the main thread.
  static Future<List<String>> getAllBooksPathsFromDirecctory(
      String path) async {
    return Isolate.run(() async {
      List<String> paths = [];
      final files = await Directory(path).list(recursive: true).toList();
      for (var file in files) {
        paths.add(file.path);
      }
      return paths;
    });
  }

  /// Retrieves the table of contents for a book.
  ///
  /// Uses LibraryProviderManager to get TOC from the appropriate provider.
  Future<List<TocEntry>> getBookToc(String title) async {
    final toc = await _providerManager.getBookToc(title);
    if (toc != null && toc.isNotEmpty) {
      return toc;
    }

    // Fallback to parsing from text
    debugPrint(
        '⚠️ Provider manager failed, falling back to text parsing for "$title"');
    return _parseToc(getBookText(title));
  }

  /// Efficiently reads a specific line from a file.
  ///
  /// Uses a stream to read the file line by line until the desired index
  /// is reached, then closes the stream to conserve resources.
  Future<String> getLineFromFile(String path, int index) async {
    try {
      File file = File(path);

      // Validate that file exists
      if (!await file.exists()) {
        debugPrint('⚠️ File does not exist: $path');
        return 'שגיאה: הקובץ לא נמצא';
      }

      // Validate index is positive
      if (index <= 0) {
        debugPrint('⚠️ Invalid line index: $index for file: $path');
        return 'שגיאה: אינדקס שורה לא תקין';
      }

      // Add timeout to prevent hanging
      final lines = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(index)
          .timeout(
        const Duration(seconds: 5),
        onTimeout: (sink) {
          debugPrint('⚠️ Timeout reading file: $path');
          sink.close();
        },
      ).toList();

      if (lines.isEmpty) {
        debugPrint('⚠️ No lines found in file: $path');
        return 'שגיאה: הקובץ ריק';
      }

      if (lines.length < index) {
        debugPrint(
            '⚠️ Line index $index exceeds file length ${lines.length} in: $path');
        return 'שגיאה: אינדקס השורה חורג מגודל הקובץ';
      }

      return lines.last;
    } catch (e) {
      debugPrint('⚠️ Error reading line from file $path: $e');
      return 'שגיאה בקריאת הקובץ: $e';
    }
  }

  /// Updates the mapping of book titles to their file system paths.
  ///
  /// Creates a map where keys are book titles and values are their corresponding
  /// file system paths, excluding PDF files.
  Future<Map<String, String>> _getTitleToPath() async {
    Map<String, String> titleToPath = {};
    List<String> paths = await getAllBooksPathsFromDirecctory(libraryPath);
    for (var path in paths) {
      if (path.toLowerCase().endsWith('.pdf')) continue;
      titleToPath[getTitleFromPath(path)] = path;
    }
    return titleToPath;
  }

  /// Loads and parses the metadata for all books in the library.
  ///
  /// Reads metadata from a JSON file and creates a structured mapping of
  /// book titles to their metadata information.
  Future<Map<String, Map<String, dynamic>>> _getMetadata() async {
    if (!Settings.isInitialized) {
      await Settings.init(cacheProvider: HiveCache());
    }
    String metadataString = '';
    Map<String, Map<String, dynamic>> metadata = {};
    try {
      File file = File(
          '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}metadata.json');
      metadataString = await file.readAsString();
    } catch (e) {
      return {};
    }
    final tempMetadata =
        await Isolate.run(() => jsonDecode(metadataString) as List);

    for (int i = 0; i < tempMetadata.length; i++) {
      final row = tempMetadata[i] as Map<String, dynamic>;
      metadata[row['title'].replaceAll('"', '')] = {
        'author': row['author'] ?? '',
        'heCategories': row['heCategories'] is List
            ? (row['heCategories'] as List).join(', ')
            : row['heCategories'] ?? '',
        'heEra': row['heEra'] ?? '',
        'compDateStringHe': row['compDateStringHe'] ?? '',
        'compPlaceStringHe': row['compPlaceStringHe'] ?? '',
        'pubDateStringHe': row['pubDateStringHe'] ?? '',
        'pubPlaceStringHe': row['pubPlaceStringHe'] ?? '',
        'heDesc': row['heDesc'] ?? '',
        'heShortDesc': row['heShortDesc'] ?? '',
        'pubDate': row['pubDate'] ?? '',
        'pubPlace': row['pubPlace'] ?? '',
        'extraTitles': row['extraTitles'] == null
            ? [row['title'].toString()]
            : row['extraTitles'].map<String>((e) => e.toString()).toList()
                as List<String>,
        'extraTitlesHe': row['extraTitlesHe'] is List
            ? (row['extraTitlesHe'] as List)
                .map<String>((e) => e.toString())
                .toList()
            : [],
        'order': row['order'] == null || row['order'] == ''
            ? 999
            : row['order'].runtimeType == double
                ? row['order'].toInt()
                : row['order'] as int,
      };
    }
    return metadata;
  }

  /// Retrieves the file system path for a book with the given title.
  Future<String> _getBookPath(String title) async {
    final titleToPath = await this.titleToPath;
    return titleToPath[title] ?? 'error: book path not found: $title';
  }

  /// Parses the table of contents from book content.
  ///
  /// Creates a hierarchical structure based on HTML heading levels (h1, h2, etc.).
  /// Each entry contains the heading text, its level, and its position in the document.
  Future<List<TocEntry>> _parseToc(Future<String> bookContentFuture) async {
    final String bookContent = await bookContentFuture;

    // Build the hierarchy using the shared parser in an isolate
    return Isolate.run(() => TocParser.parseEntriesFromContent(bookContent));
  }

  /// Gets the path to the JSON file containing links for a specific book.
  String _getLinksPath(String title) {
    return '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}links${Platform.pathSeparator}${title}_links.json';
  }

  /// Checks if a book with the given title exists in the library.
  Future<bool> bookExists(String title) async {
    final titleToPath = await this.titleToPath;
    return titleToPath.keys.contains(title);
  }

  /// Returns true if the book belongs to Tanach (Torah, Neviim or Ketuvim).
  ///
  /// The check is performed by examining the book path and verifying that it
  /// resides under one of the Tanach directories.
  Future<bool> isTanachBook(String title) async {
    final path = await _getBookPath(title);
    final normalized = path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    final tanachBase =
        '${Platform.pathSeparator}אוצריא${Platform.pathSeparator}תנך${Platform.pathSeparator}';
    final torah = '$tanachBaseתורה';
    final neviim = '$tanachBaseנביאים';
    final ktuvim = '$tanachBaseכתובים';
    return normalized.contains(torah) ||
        normalized.contains(neviim) ||
        normalized.contains(ktuvim);
  }
}
