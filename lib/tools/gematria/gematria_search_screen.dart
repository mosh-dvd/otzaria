import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/gematria_settings_dialog.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/core/scaffold_messenger.dart';
import 'gematria_search.dart';
import 'package:otzaria/utils/open_book.dart';

class GematriaSearchScreen extends StatefulWidget {
  const GematriaSearchScreen({super.key});

  @override
  GematriaSearchScreenState createState() => GematriaSearchScreenState();
}

class GematriaSearchScreenState extends State<GematriaSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<GematriaSearchResult> _searchResults = [];
  bool _isSearching = false;
  int? _lastGematriaValue; // ערך הגימטריה האחרון שחיפשנו
  bool _hasMoreResults = false; // האם יש יותר תוצאות מהמקסימום
  bool _hasSearched = false; // האם בוצע חיפוש בפועל

  // סדר ספרי התנ"ך
  static const List<String> _tanachOrder = [
    // תורה
    'בראשית', 'שמות', 'ויקרא', 'במדבר', 'דברים',
    // נביאים ראשונים
    'יהושע', 'שופטים', 'שמואל א', 'שמואל ב', 'מלכים א', 'מלכים ב',
    // נביאים אחרונים
    'ישעיהו', 'ירמיהו', 'יחזקאל',
    'הושע', 'יואל', 'עמוס', 'עובדיה', 'יונה', 'מיכה', 'נחום', 'חבקוק', 'צפניה',
    'חגי', 'זכריה', 'מלאכי',
    // כתובים
    'תהלים', 'משלי', 'איוב',
    'שיר השירים', 'רות', 'איכה', 'קהלת', 'אסתר',
    'דניאל', 'עזרא', 'נחמיה', 'דברי הימים א', 'דברי הימים ב',
  ];

  int _getBookOrder(String fileName) {
    // חילוץ שם הספר מהנתיב
    final bookName = fileName.replaceAll('.txt', '').trim();
    final index = _tanachOrder.indexOf(bookName);
    return index >= 0 ? index : 999; // ספרים לא מוכרים בסוף
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    debugPrint('🔍 _performSearch called from: ${StackTrace.current.toString().split('\n')[1]}');
    
    final searchText = _searchController.text.trim();
    debugPrint('🔍 Search text: "$searchText"');
    
    if (searchText.isEmpty) {
      debugPrint('🔍 Search text is empty, returning');
      return;
    }

    // טעינת ההגדרות הבוקריות ישירות מה-Settings
    final useSmallGematria = Settings.getValue<bool>('key-gematria-use-small') ?? false;
    final useFinalLetters = Settings.getValue<bool>('key-gematria-use-final-letters') ?? false;
    final useWithKolel = Settings.getValue<bool>('key-gematria-use-with-kolel') ?? false;
    final maxResults = Settings.getValue<int>('key-gematria-max-results') ?? 100;
    final filterDuplicates = Settings.getValue<bool>('key-gematria-filter-duplicates') ?? false;
    final wholeVerseOnly = Settings.getValue<bool>('key-gematria-whole-verse-only') ?? false;
    final torahOnly = Settings.getValue<bool>('key-gematria-torah-only') ?? false;

    debugPrint('🔍 Settings loaded: maxResults=$maxResults, torahOnly=$torahOnly, wholeVerseOnly=$wholeVerseOnly');
    debugPrint('🔍 Gematria method: useSmall=$useSmallGematria, useFinal=$useFinalLetters, useKolel=$useWithKolel');

    int? targetGimatria;

    // קביעת שיטת החישוב
    String gematriaMethod = 'regular';
    if (useSmallGematria) {
      gematriaMethod = 'small';
    } else if (useFinalLetters) {
      gematriaMethod = 'finalLetters';
    }

    // Check if input is a number
    final numericValue = int.tryParse(searchText);
    if (numericValue != null) {
      targetGimatria = numericValue;
    } else {
      // Check for invalid characters (allow Hebrew letters, final forms, spaces, and numbers)
      final validChars = RegExp(r'^[א-תםןךףץ\s0-9]+$');
      if (!validChars.hasMatch(searchText)) {
        if (mounted) {
          UiSnack.showError(
            'קלט לא תקין. יש להזין אותיות עבריות או מספרים בלבד.',
          );
        }
        return;
      }

      targetGimatria = GimatriaSearch.gimatria(
        searchText,
        method: gematriaMethod,
      );

      // הוספת הכולל - מספר המילים
      if (useWithKolel) {
        final wordCount = searchText.trim().split(RegExp(r'\s+')).length;
        targetGimatria += wordCount;
      }
    }

    if (targetGimatria == 0) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _lastGematriaValue = targetGimatria;
      _hasSearched = true;
    });

    try {
      // קבלת נתיב הספרייה מההגדרות
      final libraryPath = Settings.getValue<String>('key-library-path') ?? '.';

      // חיפוש בתיקיות ספציפיות בלבד
      final searchPaths = torahOnly
          ? ['$libraryPath/אוצריא/תנך/תורה']
          : [
              '$libraryPath/אוצריא/תנך/תורה',
              '$libraryPath/אוצריא/תנך/נביאים',
              '$libraryPath/אוצריא/תנך/כתובים',
            ];

      final List<SearchResult> allResults = [];
      for (final path in searchPaths) {
        final results = await GimatriaSearch.searchInFiles(
          path,
          targetGimatria,
          maxPhraseWords: 8,
          fileLimit: maxResults + 1, // מבקשים אחד יותר כדי לדעת אם יש עוד
          wholeVerseOnly: wholeVerseOnly,
          gematriaMethod: gematriaMethod,
          useWithKolel: useWithKolel,
        );
        allResults.addAll(results);
        if (allResults.length > maxResults) break;
      }

      // בדיקה אם יש יותר תוצאות מהמקסימום
      _hasMoreResults = allResults.length > maxResults;
      var results = allResults.take(maxResults).toList();

      // סינון כפילויות אם נדרש
      if (filterDuplicates) {
        final seen = <String>{};
        results = results.where((result) {
          // הסרת ניקוד וטעמים לפני השוואה
          final key = utils.removeVolwels(result.text);
          if (seen.contains(key)) {
            return false;
          }
          seen.add(key);
          return true;
        }).toList();
      }

      // המרת התוצאות לפורמט של המסך
      setState(() {
        _searchResults = results.map((result) {
          // חילוץ שם הקובץ
          final relativePath =
              result.file.replaceFirst(libraryPath, '').replaceAll('\\', '/');
          final fileName = relativePath.split('/').last.replaceAll('.txt', '');

          // בניית הנתיב עם מספר הפסוק
          String displayPath = result.path.isNotEmpty ? result.path : fileName;

          if (result.verseNumber.isNotEmpty) {
            displayPath = '$displayPath, פסוק ${result.verseNumber}';
          } else if (result.path.isEmpty) {
            displayPath = '$displayPath, שורה ${result.line}';
          }

          return GematriaSearchResult(
            bookTitle: fileName,
            internalPath: displayPath,
            preview: result.text,
            data: result,
          );
        }).toList();

        // מיון התוצאות לפי סדר התנ"ך
        _searchResults.sort((a, b) {
          final aOrder = _getBookOrder(a.bookTitle);
          final bOrder = _getBookOrder(b.bookTitle);
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
          // אם אותו ספר, מיין לפי מספר השורה
          final aResult = a.data as SearchResult;
          final bResult = b.data as SearchResult;
          return aResult.line.compareTo(bResult.line);
        });

        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה בחיפוש: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildSearchBar(),
          if (_lastGematriaValue != null) _buildStatusBar(),
          Expanded(child: _buildResultsList()),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final resultsText = _hasMoreResults
        ? 'הוגבל ל-${_searchResults.length} תוצאות'
        : 'נמצאו ${_searchResults.length} תוצאות';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            resultsText,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
          Text(
            'ערך גימטריה: $_lastGematriaValue',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void showSettingsDialog() {
    debugPrint('🔧 Opening settings dialog');
    
    // ההמתנה לסגירת הדיאלוג
    showGematriaSettingsDialog(context).then((_) {
      debugPrint('🔧 Settings dialog closed - .then() executed!');
      debugPrint('🔧 Search controller text: "${_searchController.text}"');
      debugPrint('🔧 Has searched: $_hasSearched');
      debugPrint('🔧 Mounted: $mounted');
      
      // ווידוא שה-widget עדיין mounted
      if (!mounted) {
        debugPrint('🔧 Widget not mounted, skipping search');
        return;
      }
      
      // רצה בצע חיפוש מחדש אם יש טקסט חיפוש ובוצע חיפוש לפחות פעם אחת
      if (_searchController.text.trim().isNotEmpty && _hasSearched) {
        debugPrint('🔧 Performing automatic search after settings change');
        _performSearch();
      } else {
        debugPrint('🔧 No search performed yet or no text, skipping automatic search');
      }
    }).catchError((error) {
      debugPrint('🔧 ERROR in showSettingsDialog: $error');
    });
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'חפש גימטריה...',
                labelText: 'לחיפוש, הכנס אותיות או מספר של ערך החיפוש',
                prefixIcon: IconButton(
                  icon: const Icon(FluentIcons.search_24_regular),
                  onPressed: _performSearch,
                  color: Theme.of(context).colorScheme.primary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'נקה',
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _lastGematriaValue = null;
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _performSearch(),
              textInputAction: TextInputAction.search,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty && _hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.search_24_regular,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'לא נמצאו תוצאות',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.calculator_24_regular,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'הזן ערך לחיפוש גימטריה',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildResultCard(index + 1, _searchResults[index]);
      },
    );
  }

  Widget _buildResultCard(int number, GematriaSearchResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          final book = TextBook(title: result.bookTitle);
          final index = result.data.line - 1;
          final searchQuery = result.preview;
          openBook(context, book, index, searchQuery, ignoreHistory: true);
        },
        borderRadius: BorderRadius.circular(12),
        hoverColor: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        splashColor: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // מספר התוצאה
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // תוכן התוצאה
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // נתיב (כותרות) - אם קיים, אחרת שם הקובץ
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        String displayPath = result.internalPath.isNotEmpty
                            ? result.internalPath
                            : result.bookTitle;
                        if (settingsState.replaceHolyNames) {
                          displayPath = utils.replaceHolyNames(displayPath);
                        }
                        return Text(
                          displayPath,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // המילים שנמצאו עם הקשר
                    if (result.preview.isNotEmpty)
                      BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          String displayText = result.preview;
                          if (settingsState.replaceHolyNames) {
                            displayText = utils.replaceHolyNames(displayText);
                          }

                          // הוספת הקשר אם קיים
                          final searchResult = result.data as SearchResult;
                          String contextBefore = searchResult.contextBefore;
                          String contextAfter = searchResult.contextAfter;

                          if (settingsState.replaceHolyNames) {
                            contextBefore =
                                utils.replaceHolyNames(contextBefore);
                            contextAfter = utils.replaceHolyNames(contextAfter);
                          }

                          return RichText(
                            textAlign: TextAlign.right,
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: settingsState.fontSize,
                                fontFamily: settingsState.fontFamily,
                                color: Theme.of(context).colorScheme.onSurface,
                                height: 1.5,
                              ),
                              children: [
                                // הקשר לפני - אפור וחלש
                                if (contextBefore.isNotEmpty)
                                  TextSpan(
                                    text: '$contextBefore ',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4),
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                // הטקסט המרכזי - בולט
                                TextSpan(
                                  text: displayText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: settingsState.fontSize + 2,
                                  ),
                                ),
                                // הקשר אחרי - אפור וחלש
                                if (contextAfter.isNotEmpty)
                                  TextSpan(
                                    text: ' $contextAfter',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4),
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GematriaSearchResult {
  final String bookTitle;
  final String internalPath;
  final String preview;
  final dynamic data; // מידע נוסף שתרצה לשמור

  GematriaSearchResult({
    required this.bookTitle,
    required this.internalPath,
    this.preview = '',
    this.data,
  });
}
