import 'dart:io';
import 'package:path/path.dart' as p;

/// Utility class to load and parse SQL query files (.sq)
class QueryLoader {
  static final Map<String, Map<String, String>> _queryCache = {};

  /// Get the base directory for SQL query files
  static String _getBaseDirectory() {
    // Get the current working directory and navigate to the sqflite directory
    final currentDir = Directory.current.path;
    // Assuming the script is run from the project root, navigate to lib/migration/dao/sqflite
    return p.join(currentDir, 'lib', 'migration', 'dao', 'sqflite');
  }

  /// Load queries from a .sq file
  static Map<String, String> loadQueries(String fileName) {
    final fullPath = p.join(_getBaseDirectory(), fileName);

    if (_queryCache.containsKey(fullPath)) {
      return _queryCache[fullPath]!;
    }

    final file = File(fullPath);
    if (!file.existsSync()) {
      throw FileSystemException('Query file not found: $fullPath');
    }

    final content = file.readAsStringSync();
    final queries = _parseQueries(content);
    _queryCache[fullPath] = queries;
    return queries;
  }

  /// Parse the content of a .sq file into a map of query names to SQL
  static Map<String, String> _parseQueries(String content) {
    final queries = <String, String>{};
    final lines = content.split('\n');

    String? currentQueryName;
    final queryBuffer = StringBuffer();

    for (final line in lines) {
      final trimmedLine = line.trim();

      // Skip empty lines and comments
      if (trimmedLine.isEmpty || trimmedLine.startsWith('--')) {
        continue;
      }

      // Check if this is a query name (ends with ':')
      if (trimmedLine.endsWith(':')) {
        // Save previous query if exists
        if (currentQueryName != null && queryBuffer.isNotEmpty) {
          queries[currentQueryName] = queryBuffer.toString().trim();
          queryBuffer.clear();
        }

        // Start new query
        currentQueryName = trimmedLine.substring(0, trimmedLine.length - 1);
      } else if (currentQueryName != null) {
        // Add line to current query
        if (queryBuffer.isNotEmpty) {
          queryBuffer.write('\n');
        }
        queryBuffer.write(line);
      }
    }

    // Save the last query
    if (currentQueryName != null && queryBuffer.isNotEmpty) {
      queries[currentQueryName] = queryBuffer.toString().trim();
    }

    return queries;
  }

  /// Get a specific query by name from a .sq file
  static String getQuery(String fileName, String queryName) {
    final queries = loadQueries(fileName);
    final query = queries[queryName];
    if (query == null) {
      throw ArgumentError('Query "$queryName" not found in $fileName');
    }
    return query;
  }
}
