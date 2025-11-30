import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
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

  /// SQLite data provider for database operations
  final SqliteDataProvider _sqliteProvider = SqliteDataProvider.instance;

  /// Cache for tracking which books are in the database
  final Map<String, bool> _bookInDbCache = {};

  /// Creates a new instance of [FileSystemData] and initializes the title to path mapping
  /// and metadata
  FileSystemData() {
    libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    _initializeSqlite();
  }

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Initializes the SQLite provider
  Future<void> _initializeSqlite() async {
    try {
      await _sqliteProvider.initialize();
      debugPrint('SQLite provider initialized in FileSystemData');
    } catch (e) {
      debugPrint('SQLite provider initialization failed (will use files only): $e');
    }
  }

  /// Checks if a book is stored in the database
  Future<bool> isBookInDatabase(String title) async {
    // Check cache first
    if (_bookInDbCache.containsKey(title)) {
      return _bookInDbCache[title]!;
    }

    // Check database
    final isInDb = await _sqliteProvider.isBookInDatabase(title);
    _bookInDbCache[title] = isInDb;
    return isInDb;
  }

  /// Gets the data source for a book (DB, File, or Personal)
  /// Returns: 'DB' for database, 'ק' for file, 'א' for personal
  Future<String> getBookDataSource(String title) async {
    // Check if personal first
    final isPersonal = await isPersonalBook(title);
    if (isPersonal) return 'א';
    
    // Then check if in database
    final isInDb = await isBookInDatabase(title);
    return isInDb ? 'DB' : 'ק';
  }

  /// Clears the book-in-database cache
  void clearBookCache() {
    _bookInDbCache.clear();
    debugPrint('Book cache cleared');
  }

  /// Gets statistics about database usage
  Future<Map<String, dynamic>> getDatabaseStats() async {
    if (!_sqliteProvider.isInitialized) {
      return {
        'enabled': false,
        'books': 0,
        'links': 0,
      };
    }

    final stats = await _sqliteProvider.getDatabaseStats();
    return {
      'enabled': true,
      ...stats,
    };
  }

  /// Gets the SQLite provider for advanced operations
  SqliteDataProvider get sqliteProvider => _sqliteProvider;

  /// Checks if a book is in the personal folder
  Future<bool> isPersonalBook(String title) async {
    try {
      final titleToPathMap = await titleToPath;
      final bookPath = titleToPathMap[title];
      if (bookPath == null) return false;
      
      // Check if path contains the personal folder
      return bookPath.contains('${Platform.pathSeparator}אישי${Platform.pathSeparator}');
    } catch (e) {
      debugPrint('Error checking if book is personal: $e');
      return false;
    }
  }

  /// Gets the path to the personal books folder
  String getPersonalBooksPath() {
    return '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אישי';
  }

  /// Ensures the personal books folder exists
  Future<void> ensurePersonalFolderExists() async {
    final personalPath = getPersonalBooksPath();
    final personalDir = Directory(personalPath);
    
    if (!await personalDir.exists()) {
      await personalDir.create(recursive: true);
      debugPrint('📁 Created personal books folder: $personalPath');
      
      // Create a README file to explain the folder
      final readmePath = '$personalPath${Platform.pathSeparator}קרא אותי.txt';
      final readmeFile = File(readmePath);
      await readmeFile.writeAsString('''
תיקייה זו מיועדת לספרים אישיים

ספרים שנמצאים בתיקייה זו:
• לא יועברו למסד הנתונים
• לא יסונכרנו עם השרת
• נשארים תמיד כקבצים
• ניתנים לעריכה ישירה

איך להוסיף ספר אישי:
1. העתק קובץ TXT או DOCX לתיקייה זו
2. או השתמש בכפתור "הוסף ספר אישי" בתוכנה

הספרים יופיעו בספרייה עם סימון מיוחד (א)
''', encoding: utf8);
      debugPrint('📝 Created README in personal folder');
    }
  }

  /// Retrieves the complete library structure from the file system.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  Future<Library> getLibrary() async {
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    return _getLibraryFromDirectory(
        '$libraryPath${Platform.pathSeparator}אוצריא', await metadata);
  }

  /// Recursively builds the library structure from a directory.
  ///
  /// Creates a hierarchical structure of categories and books by traversing
  /// the file system directory structure.
  Future<Library> _getLibraryFromDirectory(
      String path, Map<String, dynamic> metadata) async {
    // First, get all books from the database
    final Set<String> dbBookTitles = {};
    final Map<String, List<Map<String, dynamic>>> dbBookDataByCategory = {};
    
    try {
      if (_sqliteProvider.isInitialized && _sqliteProvider.repository != null) {
        final dbBooks = await _sqliteProvider.repository!.getAllBooks();
        debugPrint('📚 Found ${dbBooks.length} books in database');
        
        // Group book data by category (we'll create TextBook objects later with proper category reference)
        for (final dbBook in dbBooks) {
          dbBookTitles.add(dbBook.title);
          
          // Get category name for this book
          final categoryName = dbBook.topics.isNotEmpty 
              ? dbBook.topics.first.name 
              : 'ללא קטגוריה';
          
          // Store book data to create TextBook later
          final bookData = {
            'title': dbBook.title,
            'author': dbBook.authors.isNotEmpty ? dbBook.authors.first.name : null,
            'heShortDesc': dbBook.heShortDesc,
            'pubDate': dbBook.pubDates.isNotEmpty ? dbBook.pubDates.first.date : null,
            'pubPlace': dbBook.pubPlaces.isNotEmpty ? dbBook.pubPlaces.first.name : null,
            'order': dbBook.order.toInt(),
            'topics': dbBook.topics.map((t) => t.name).join(', '),
          };
          
          if (!dbBookDataByCategory.containsKey(categoryName)) {
            dbBookDataByCategory[categoryName] = [];
          }
          dbBookDataByCategory[categoryName]!.add(bookData);
        }
        
        debugPrint('📚 Grouped ${dbBooks.length} books into ${dbBookDataByCategory.length} categories from database');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading books from database: $e');
    }
    
    /// Recursive helper function to process directories and build category structure
    Future<Category> getAllCategoriesAndBooksFromDirectory(
        Directory dir, Category? parent) async {
      final title = getTitleFromPath(dir.path);
      Category category = Category(
          title: title,
          description: metadata[title]?['heDesc'] ?? '',
          shortDescription: metadata[title]?['heShortDesc'] ?? '',
          order: metadata[title]?['order'] ?? 999,
          subCategories: [],
          books: [],
          parent: parent);

      // Process each entity in the directory
      await for (FileSystemEntity entity in dir.list()) {
        // Check if entity is accessible before processing
        try {
          // Verify we can access the entity
          await entity.stat();

          if (entity is Directory) {
            // Recursively process subdirectories as categories
            category.subCategories.add(
                await getAllCategoriesAndBooksFromDirectory(
                    Directory(entity.path), category));
          } else if (entity is File) {
            // Only process actual files, not directories mistaken as files
            // Extract topics from the file path
            var topics = entity.path
                .split('אוצריא${Platform.pathSeparator}')
                .last
                .split(Platform.pathSeparator)
                .toList();
            topics = topics.sublist(0, topics.length - 1);

            // Handle special case where title contains " על "
            if (getTitleFromPath(entity.path).contains(' על ')) {
              topics.add(getTitleFromPath(entity.path).split(' על ')[1]);
            }

            // Process PDF files
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              final title = getTitleFromPath(entity.path);
              
              // Skip if already in DB
              if (dbBookTitles.contains(title)) {
                debugPrint('⏭️ Skipping "$title" - already in database');
                continue;
              }
              
              category.books.add(
                PdfBook(
                  title: title,
                  category: category,
                  path: entity.path,
                  author: metadata[title]?['author'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                ),
              );
            }

            // Process text and docx files
            if (entity.path.toLowerCase().endsWith('.txt') ||
                entity.path.toLowerCase().endsWith('.docx')) {
              final title = getTitleFromPath(entity.path);
              
              // Skip if already in DB
              if (dbBookTitles.contains(title)) {
                debugPrint('⏭️ Skipping "$title" - already in database');
                continue;
              }
              
              category.books.add(TextBook(
                  title: title,
                  category: category,
                  author: metadata[title]?['author'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                  extraTitles: metadata[title]?['extraTitles']));
            }
          }
        } catch (e) {
          // Skip entities that can't be accessed (like directories mistaken as files)
          debugPrint('Skipping inaccessible entity: ${entity.path} - $e');
          continue;
        }
      }

      // Sort categories and books by their order
      category.subCategories.sort((a, b) => a.order.compareTo(b.order));
      category.books.sort((a, b) => a.order.compareTo(b.order));
      return category;
    }

    // Initialize empty library
    Library library = Library(categories: []);

    // Process top-level directories from file system
    await for (FileSystemEntity entity in Directory(path).list()) {
      if (entity is Directory) {
        // Skip "אודות התוכנה" directory
        final dirName = entity.path.split(Platform.pathSeparator).last;
        if (dirName == 'אודות התוכנה') {
          continue;
        }

        library.subCategories.add(await getAllCategoriesAndBooksFromDirectory(
            Directory(entity.path), library));
      }
    }
    
    // Now add DB books to existing categories or create new ones
    for (final entry in dbBookDataByCategory.entries) {
      final categoryName = entry.key;
      final booksData = entry.value;
      
      // Try to find existing category with this name
      Category? existingCategory;
      try {
        existingCategory = library.subCategories.firstWhere(
          (cat) => cat.title == categoryName
        );
        debugPrint('📁 Found existing category "$categoryName" for DB books');
      } catch (e) {
        // Category doesn't exist, create it
        existingCategory = Category(
          title: categoryName,
          description: metadata[categoryName]?['heDesc'] ?? '',
          shortDescription: metadata[categoryName]?['heShortDesc'] ?? '',
          order: metadata[categoryName]?['order'] ?? 999,
          subCategories: [],
          books: [],
          parent: library,
        );
        library.subCategories.add(existingCategory);
        debugPrint('📁 Created new category "$categoryName" for DB books');
      }
      
      // Create TextBook objects with proper category reference and add them
      for (final bookData in booksData) {
        final book = TextBook(
          title: bookData['title'],
          category: existingCategory,
          author: bookData['author'],
          heShortDesc: bookData['heShortDesc'],
          pubDate: bookData['pubDate'],
          pubPlace: bookData['pubPlace'],
          order: bookData['order'],
          topics: bookData['topics'],
        );
        existingCategory.books.add(book);
      }
      
      debugPrint('📚 Added ${booksData.length} DB books to category "$categoryName"');
    }
    
    library.subCategories.sort((a, b) => a.order.compareTo(b.order));
    debugPrint('✅ Library loaded with ${library.subCategories.length} top-level categories');
    return library;
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
  /// First checks if the book is in the database. If found, retrieves from DB.
  /// Otherwise, falls back to reading from file system.
  /// Supports both plain text and DOCX formats. DOCX files are processed
  /// using a special converter to extract their content.
  Future<String> getBookText(String title) async {
    // Check cache first
    bool? isInDb = _bookInDbCache[title];
    
    // If not in cache, check database
    if (isInDb == null) {
      isInDb = await _sqliteProvider.isBookInDatabase(title);
      _bookInDbCache[title] = isInDb;
    }

    // If book is in database, get it from there
    if (isInDb) {
      debugPrint('📚 Loading book "$title" from DATABASE');
      final text = await _sqliteProvider.getBookTextFromDb(title);
      if (text != null) {
        return text;
      }
      // If failed to get from DB, fall back to file
      debugPrint('⚠️ Failed to load from DB, falling back to file for "$title"');
      _bookInDbCache[title] = false; // Update cache
    }

    // Fall back to file system
    debugPrint('📄 Loading book "$title" from FILE');
    final path = await _getBookPath(title);
    final file = File(path);

    if (path.endsWith('.docx')) {
      final bytes = await file.readAsBytes();
      return Isolate.run(() => docxToText(bytes, title));
    } else {
      return file.readAsString();
    }
  }

  /// Saves text content to a book file.
  ///
  /// Only supports plain text files (.txt). DOCX files cannot be edited.
  /// Creates a backup of the original file before saving.
  Future<void> saveBookText(String title, String content) async {
    final path = await _getBookPath(title);
    final file = File(path);

    // Only allow saving to text files, not DOCX
    if (path.endsWith('.docx')) {
      throw Exception(
          'Cannot save to DOCX files. Only text files are supported.');
    }

    // Create backup of original file
    final backupPath = '$path.backup.${DateTime.now().millisecondsSinceEpoch}';
    await file.copy(backupPath);

    try {
      // Save the new content
      await file.writeAsString(content, encoding: utf8);

      // Clean up old backups after successful save
      await _cleanupOldBackups(path);
    } catch (e) {
      // If save fails, restore from backup
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.copy(path);
      }
      rethrow;
    }
  }

  /// Cleans up old backup files for a given file path.
  /// Keeps only the most recent 3 backups, deletes older ones.
  Future<void> _cleanupOldBackups(String originalPath) async {
    try {
      final directory = Directory(originalPath).parent;
      final baseName = originalPath.split(Platform.pathSeparator).last;

      // Find all backup files for this document
      final backupFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('$baseName.backup.')) {
            backupFiles.add(entity);
          }
        }
      }

      // Sort by timestamp (newest first)
      backupFiles.sort((a, b) {
        final aTime = _getBackupTimestamp(a.path);
        final bTime = _getBackupTimestamp(b.path);
        return bTime.compareTo(aTime); // Descending order
      });

      // Keep only the first 3 (most recent)
      for (int i = 3; i < backupFiles.length; i++) {
        try {
          await backupFiles[i].delete();
          debugPrint('Deleted old backup: ${backupFiles[i].path}');
        } catch (e) {
          debugPrint('Failed to delete backup ${backupFiles[i].path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during backup cleanup: $e');
    }
  }

  /// Extracts timestamp from backup filename
  int _getBackupTimestamp(String backupPath) {
    try {
      final fileName = backupPath.split(Platform.pathSeparator).last;
      final timestampStr = fileName.split('.backup.').last;
      return int.parse(timestampStr);
    } catch (e) {
      return 0; // Return 0 for files that can't be parsed
    }
  }

  /// Manual cleanup of old backup files across the entire library
  Future<int> cleanupAllOldBackups() async {
    int deletedCount = 0;
    try {
      final libraryDir =
          Directory('$libraryPath${Platform.pathSeparator}אוצריא');

      await for (final entity in libraryDir.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.contains('.backup.')) {
            // Check if this backup is old (older than 7 days)
            final timestamp = _getBackupTimestamp(entity.path);
            final backupDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final daysOld = DateTime.now().difference(backupDate).inDays;

            if (daysOld > 7) {
              try {
                await entity.delete();
                deletedCount++;
              } catch (e) {
                debugPrint('Failed to delete backup ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error during global backup cleanup: $e');
    }

    return deletedCount;
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
  /// Parses the book content to extract headings and create a hierarchical
  /// table of contents structure.
  /// 
  /// First checks if the book is in the database. If found, retrieves TOC from DB.
  /// Otherwise, falls back to parsing the file content.
  Future<List<TocEntry>> getBookToc(String title) async {
    // Check cache first
    bool? isInDb = _bookInDbCache[title];
    
    // If not in cache, check database
    if (isInDb == null) {
      isInDb = await _sqliteProvider.isBookInDatabase(title);
      _bookInDbCache[title] = isInDb;
    }

    // If book is in database, get TOC from there
    if (isInDb) {
      debugPrint('📑 Loading TOC for "$title" from DATABASE');
      final toc = await _sqliteProvider.getBookTocFromDb(title);
      if (toc != null && toc.isNotEmpty) {
        return toc;
      }
      // If failed to get from DB or empty, fall back to parsing file
      debugPrint('⚠️ Failed to load TOC from DB or empty, falling back to file parsing for "$title"');
    }

    // Fall back to parsing file content
    debugPrint('📄 Parsing TOC for "$title" from FILE');
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
          )
          .toList();
      
      if (lines.isEmpty) {
        debugPrint('⚠️ No lines found in file: $path');
        return 'שגיאה: הקובץ ריק';
      }
      
      if (lines.length < index) {
        debugPrint('⚠️ Line index $index exceeds file length ${lines.length} in: $path');
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
        'heDesc': row['heDesc'] ?? '',
        'heShortDesc': row['heShortDesc'] ?? '',
        'pubDate': row['pubDate'] ?? '',
        'pubPlace': row['pubPlace'] ?? '',
        'extraTitles': row['extraTitles'] == null
            ? [row['title'].toString()]
            : row['extraTitles'].map<String>((e) => e.toString()).toList()
                as List<String>,
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
