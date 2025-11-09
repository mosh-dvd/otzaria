import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text_manipulation.dart';

class TextBookRepository {
  final FileSystemData _fileSystem;

  TextBookRepository({
    required FileSystemData fileSystem,
  }) : _fileSystem = fileSystem;

  Future<String> getBookContent(TextBook book) async {
    return await book.text;
  }

  Future<List<Link>> getBookLinks(TextBook book) async {
    return await book.links;
  }

  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return await book.tableOfContents;
  }

  Future<List<String>> getAvailableCommentators(List<Link> links) async {
    List<Link> filteredLinks = links
        .where((link) =>
            link.connectionType == 'commentary' ||
            link.connectionType == 'targum')
        .toList();

    List<String> paths = filteredLinks.map((e) => e.path2).toList();
    List<String> uniquePaths = paths.toSet().toList();
    List<String> commentatorTitles = uniquePaths
        .map(
          (e) => getTitleFromPath(e),
        )
        .toList();

    // Filter commentators asynchronously
    List<String> availableCommentators = [];
    for (String title in commentatorTitles) {
      if (await _fileSystem.bookExists(title)) {
        availableCommentators.add(title);
      }
    }

    // Sort by generation order using splitByEra
    final sortedList = await _sortByGenerationOrder(availableCommentators);
    return sortedList;
  }

  /// Sort commentators by generation order (תורה שבכתב, חז"ל, ראשונים, אחרונים, מחברי זמננו)
  Future<List<String>> _sortByGenerationOrder(List<String> commentators) async {
    debugPrint('🔄 Sorting ${commentators.length} commentators by generation...');
    
    // Use splitByEra to categorize commentators
    final byEra = await splitByEra(commentators);
    
    debugPrint('📊 Split results:');
    debugPrint('   תורה שבכתב: ${byEra['תורה שבכתב']?.length ?? 0}');
    debugPrint('   חז"ל: ${byEra['חז"ל']?.length ?? 0}');
    debugPrint('   ראשונים: ${byEra['ראשונים']?.length ?? 0}');
    debugPrint('   אחרונים: ${byEra['אחרונים']?.length ?? 0}');
    debugPrint('   מחברי זמננו: ${byEra['מחברי זמננו']?.length ?? 0}');
    debugPrint('   מפרשים נוספים: ${byEra['מפרשים נוספים']?.length ?? 0}');
    
    // Build sorted list in generation order
    final sorted = <String>[];
    
    // Add each generation in order, with alphabetical sorting within each generation
    final torahShebichtav = byEra['תורה שבכתב'] ?? [];
    torahShebichtav.sort();
    sorted.addAll(torahShebichtav);
    
    final chazal = byEra['חז"ל'] ?? [];
    chazal.sort();
    sorted.addAll(chazal);
    
    final rishonim = byEra['ראשונים'] ?? [];
    rishonim.sort();
    sorted.addAll(rishonim);
    
    final acharonim = byEra['אחרונים'] ?? [];
    acharonim.sort();
    sorted.addAll(acharonim);
    
    final modern = byEra['מחברי זמננו'] ?? [];
    modern.sort();
    sorted.addAll(modern);
    
    final others = byEra['מפרשים נוספים'] ?? [];
    others.sort();
    sorted.addAll(others);
    
    debugPrint('✅ Sorted list has ${sorted.length} commentators');
    if (sorted.length <= 10) {
      debugPrint('   Order: ${sorted.join(", ")}');
    } else {
      debugPrint('   First 5: ${sorted.take(5).join(", ")}');
      debugPrint('   Last 5: ${sorted.skip(sorted.length - 5).join(", ")}');
    }
    
    return sorted;
  }

  Future<bool> bookExists(String title) async {
    return await _fileSystem.bookExists(title);
  }

  Future<void> saveBookContent(TextBook book, String content) async {
    await _fileSystem.saveBookText(book.title, content);
  }
}
