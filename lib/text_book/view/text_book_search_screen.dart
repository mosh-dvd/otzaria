import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:search_engine/search_engine.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/models/books.dart';

enum SearchScope {
  currentSection,
  wholeBook,
}

class _GroupedResultItem {
  final String? header;
  final TextSearchResult? result;
  const _GroupedResultItem.header(this.header) : result = null;
  const _GroupedResultItem.result(this.result) : header = null;
  bool get isHeader => header != null;
}

class TextBookSearchView extends StatefulWidget {
  final String data;
  final ItemScrollController scrollControler;
  final FocusNode focusNode;
  final void Function() closeLeftPaneCallback;
  final String initialQuery;
  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;

  const TextBookSearchView({
    super.key,
    required this.data,
    required this.scrollControler,
    required this.focusNode,
    required this.closeLeftPaneCallback,
    required this.initialQuery,
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
  });

  @override
  TextBookSearchViewState createState() => TextBookSearchViewState();
}

class TextBookSearchViewState extends State<TextBookSearchView>
    with AutomaticKeepAliveClientMixin<TextBookSearchView> {
  TextEditingController searchTextController = TextEditingController();
  final SearchRepository _searchRepository = SearchRepository();
  List<TextSearchResult> searchResults = [];
  late ItemScrollController scrollControler;
  bool _isSearching = false;
  List<String> _content = [];
  String? _bookPath;
  String? _bookTitle;
  bool _forceSearchEngine = false;
  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;
  
  // היקף החיפוש - כל הספר או כותרת נוכחית
  SearchScope _searchScope = SearchScope.wholeBook;

  bool get _isSimpleSearch =>
      !_forceSearchEngine &&
      _searchOptions.isEmpty &&
      _alternativeWords.isEmpty &&
      _spacingValues.isEmpty &&
      _searchMode == SearchMode.exact;

  static const int _maxResultSnippetChars = 220;

  @override
  void initState() {
    super.initState();
    _content = widget.data.split('\n');

    searchTextController.text = widget.initialQuery;
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = widget.initialSearchMode;
    _forceSearchEngine = _searchMode != SearchMode.exact ||
        _searchOptions.isNotEmpty ||
        _alternativeWords.isNotEmpty ||
        _spacingValues.isNotEmpty;

    scrollControler = widget.scrollControler;
    widget.focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBookPath();
    });
  }

  Future<void> _initializeBookPath() async {
    if (!mounted) return;
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final bookTitle = state.book.title;
      debugPrint('📚 TextBookSearch: book.title = $bookTitle');

      _bookTitle = bookTitle;

      final topics = await BookFacet.resolveTopics(
        title: bookTitle,
        initialTopics: state.book.topics,
        type: TextBook,
      );

      if (!mounted) return;

      debugPrint('📚 TextBookSearch: final topics = "$topics"');
      _bookPath = BookFacet.buildFacetPath(title: bookTitle, topics: topics);
      debugPrint('📚 TextBookSearch: _bookPath = $_bookPath');
      if (searchTextController.text.isNotEmpty) {
        _runInitialSearch();
      }
    }
  }

  void _runInitialSearch() {
    _searchTextUpdated();
  }

  Future<void> _searchTextUpdated() async {
    final query = searchTextController.text.trim();
    if (query.isEmpty ||
        (!_isSimpleSearch && (_bookPath == null || _bookTitle == null))) {
      setState(() {
        searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    if (_isSimpleSearch) {
      // Simple search implementation
      final results = await Future(() {
        final List<SearchResult> matches = [];
        final List<String> address = [];
        
        // קביעת טווח החיפוש
        int startIndex = 0;
        int endIndex = _content.length;
        
        if (_searchScope == SearchScope.currentSection) {
          // מציאת הכותרת הנוכחית
          final state = context.read<TextBookBloc>().state;
          if (state is TextBookLoaded) {
            final currentIndex = state.positionsListener.itemPositions.value.isNotEmpty
                ? state.positionsListener.itemPositions.value.first.index
                : 0;
            
            // מציאת תחילת הכותרת הנוכחית
            startIndex = currentIndex;
            while (startIndex > 0 && !_content[startIndex].startsWith('<h')) {
              startIndex--;
            }
            
            // מציאת סוף הכותרת הנוכחית (תחילת הכותרת הבאה)
            endIndex = currentIndex + 1;
            while (endIndex < _content.length && !_content[endIndex].startsWith('<h')) {
              endIndex++;
            }
          }
        }

        for (int i = startIndex; i < endIndex; i++) {
          final line = _content[i];

          // Update address based on headers
          if (line.startsWith('<h')) {
            if (address.isNotEmpty &&
                address.any((element) =>
                    element.substring(0, 4) == line.substring(0, 4))) {
              address.removeRange(
                  address.indexWhere((element) =>
                      element.substring(0, 4) == line.substring(0, 4)),
                  address.length);
            }
            address.add(line);
          }

          // Clean text for search
          final cleanLine = utils.removeVolwels(utils.stripHtmlIfNeeded(line));
          if (cleanLine.contains(query)) {
            // Build reference string from address (excluding h1 which is usually book title)
            final filteredAddress =
                address.where((h) => !h.startsWith('<h1')).toList();
            final reference = utils.removeVolwels(
                utils.stripHtmlIfNeeded(filteredAddress.join(', ')));

            matches.add(SearchResult(
              id: BigInt.zero,
              title: _bookTitle ?? '',
              reference: reference,
              text: cleanLine, // Use cleaned text for snippet generation
              segment: BigInt.from(i),
              isPdf: false,
              filePath: '',
            ));
            if (matches.length >= 1000) break;
          }
        }
        return matches;
      });

      if (mounted) {
        setState(() {
          searchResults = _convertSearchResults(results);
          _isSearching = false;
        });
      }
      return;
    }

    try {
      // The facet filter is a prefix filter in the underlying engine, so when a
      // book is a parent facet (e.g. /.../ספר הזהר) it may also match child
      // facets like commentaries. We therefore post-filter by exact title.
      //
      // Use a higher raw limit to avoid losing relevant results that would have
      // been returned after filtering.
      const rawLimit = 5000;
      const displayLimit = 1000;

      final rawResults = await _searchRepository.searchTexts(
        query,
        [_bookPath!],
        rawLimit,
        searchOptions: _searchOptions,
        alternativeWords: _alternativeWords,
        customSpacing: _spacingValues,
        fuzzy: _searchMode == SearchMode.fuzzy,
      );

      final expectedTitle = _bookTitle!.trim();

      final filtered = rawResults
          .where((r) => !r.isPdf && r.title.trim() == expectedTitle)
          .toList(growable: false);

      // In-book search should be presented in reading order (by segment/line),
      // not by relevance.
      final sorted = filtered.toList(growable: true)
        ..sort((a, b) {
          final sa = a.segment.toInt();
          final sb = b.segment.toInt();
          if (sa != sb) return sa.compareTo(sb);

          final ra = a.reference;
          final rb = b.reference;
          final rc = ra.compareTo(rb);
          if (rc != 0) return rc;

          return a.text.compareTo(b.text);
        });

      final results = sorted.take(displayLimit).toList(growable: false);

      debugPrint(
        '📚 TextBookSearch: rawResults=${rawResults.length}, '
        'filteredResults=${results.length}, title="$expectedTitle"',
      );

      if (mounted) {
        setState(() {
          searchResults = _convertSearchResults(results);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() {
          searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  List<TextSearchResult> _convertSearchResults(List<SearchResult> results) {
    final List<TextSearchResult> converted = [];
    for (final result in results) {
      try {
        final lineNumber = result.segment.toInt();
        if (lineNumber >= 0 && lineNumber < _content.length) {
          converted.add(TextSearchResult(
            index: lineNumber,
            snippet: result.text,
            address: result.reference,
            query: searchTextController.text,
          ));
        }
      } catch (e) {
        debugPrint('Error converting result: $e');
      }
    }
    return converted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // יצירת רשימה מקובצת - כותרת מופיעה רק כשהיא משתנה
    final List<_GroupedResultItem> items = [];
    String? lastAddress;
    for (final r in searchResults) {
      if (lastAddress != r.address) {
        items.add(_GroupedResultItem.header(r.address));
        lastAddress = r.address;
      }
      items.add(_GroupedResultItem.result(r));
    }

    return Column(
      children: [
        // שורת החיפוש
        if (_isSearching) const LinearProgressIndicator(minHeight: 4),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: RtlTextField(
            autofocus: true,
            focusNode: widget.focusNode,
            controller: searchTextController,
            textAlign: TextAlign.right,
            onChanged: (value) => _searchTextUpdated(),
            onSubmitted: (_) {
              widget.focusNode.requestFocus();
            },
            decoration: InputDecoration(
              hintText: 'חפש בספר...',
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // כפתורי בחירת היקף החיפוש
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _searchScope = SearchScope.currentSection;
                            });
                            if (searchTextController.text.isNotEmpty) {
                              _searchTextUpdated();
                            }
                          },
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _searchScope == SearchScope.currentSection
                                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  FluentIcons.document_24_regular,
                                  size: 16,
                                  color: _searchScope == SearchScope.currentSection
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'כותרת',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _searchScope == SearchScope.currentSection
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _searchScope = SearchScope.wholeBook;
                            });
                            if (searchTextController.text.isNotEmpty) {
                              _searchTextUpdated();
                            }
                          },
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _searchScope == SearchScope.wholeBook
                                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  FluentIcons.book_24_regular,
                                  size: 16,
                                  color: _searchScope == SearchScope.wholeBook
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'כל הספר',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _searchScope == SearchScope.wholeBook
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (searchTextController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'נקה',
                      onPressed: () {
                        searchTextController.clear();
                        setState(() {
                          searchResults = [];
                        });
                        widget.focusNode.requestFocus();
                      },
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                    ),
                ],
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            textInputAction: TextInputAction.search,
          ),
        ),
        if (searchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'נמצאו ${searchResults.length} תוצאות',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.grey[700],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: searchResults.isEmpty && searchTextController.text.isNotEmpty && !_isSearching
              ? const Center(child: Text('אין תוצאות'))
              : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          // אם זו כותרת קבוצה
          if (item.isHeader) {
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String text = item.header!;
                if (settingsState.replaceHolyNames) {
                  text = utils.replaceHolyNames(text);
                }
                return Padding(
                  padding: const EdgeInsets.only(
                    top: 8.0,
                    bottom: 8.0,
                    right: 4.0,
                    left: 4.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.text_align_right_24_regular,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }

          // אם זו תוצאה רגילה
          final result = item.result!;
          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              String snippet = result.snippet;

              if (settingsState.replaceHolyNames) {
                snippet = utils.replaceHolyNames(snippet);
              }

              snippet = _buildSearchExcerpt(
                fullText: snippet,
                query: result.query,
                maxChars: _maxResultSnippetChars,
              );

              // יצירת TextSpans עם הדגשה של מילות החיפוש
              final highlightedSnippet = _buildHighlightedText(
                snippet,
                result.query,
                settingsState,
                context,
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () {
                    // תמיד השתמש ב-scrollController - זה עובד גם בצורת הדף
                    widget.scrollControler.scrollTo(
                      index: result.index,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.ease,
                    );
                    if (Platform.isAndroid) {
                      widget.closeLeftPaneCallback();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3),
                  splashColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: RichText(
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.justify,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: settingsState.fontFamily,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.5,
                        ),
                        children: highlightedSnippet,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
        ),
      ],
    );
  }

  // פונקציה ליצירת טקסט מודגש
  List<InlineSpan> _buildHighlightedText(
    String text,
    String query,
    SettingsState settingsState,
    BuildContext context,
  ) {
    if (query.isEmpty) {
      return [TextSpan(text: text)];
    }

    final List<InlineSpan> spans = [];
    final searchTerms = query.trim().split(RegExp(r'\s+'));

    final highlightRegex = RegExp(
      searchTerms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    int currentPosition = 0;

    for (final match in highlightRegex.allMatches(text)) {
      // טקסט רגיל לפני ההדגשה
      if (match.start > currentPosition) {
        spans.add(TextSpan(
          text: text.substring(currentPosition, match.start),
        ));
      }
      // הטקסט המודגש
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Color(0xFFD32F2F), // צבע אדום חזק למילות החיפוש
        ),
      ));
      currentPosition = match.end;
    }

    // טקסט רגיל אחרי ההדגשה האחרונה
    if (currentPosition < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentPosition),
      ));
    }

    return spans;
  }

  String _buildSearchExcerpt({
    required String fullText,
    required String query,
    required int maxChars,
  }) {
    var text = fullText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxChars) return text;

    // Helper to find word end
    int findWordEnd(int fromIndex) {
      if (fromIndex >= text.length) return text.length;
      final nextSpace = text.indexOf(' ', fromIndex);
      return nextSpace != -1 ? nextSpace : text.length;
    }

    // Helper to find word start
    int findWordStart(int fromIndex) {
      if (fromIndex <= 0) return 0;
      final lastSpace = text.lastIndexOf(' ', fromIndex);
      return lastSpace != -1 ? lastSpace + 1 : 0;
    }

    final q = query.trim();
    if (q.isEmpty) {
      var end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) {
      var end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    final highlightRegex = RegExp(
      terms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    final matches = highlightRegex.allMatches(text);
    if (matches.isEmpty) {
      var end = findWordEnd(maxChars);
      final suffix = end < text.length ? ' ...' : '';
      return '${text.substring(0, end)}$suffix';
    }

    Match? bestMatch;
    Match? firstMatch;

    // Try to find a whole word match
    // We define a word char as alphanumeric or Hebrew
    final wordCharRegex = RegExp(r'[a-zA-Z0-9\u0590-\u05FF]');

    for (final match in matches) {
      firstMatch ??= match;

      final start = match.start;
      final end = match.end;

      bool startOk = start == 0 || !wordCharRegex.hasMatch(text[start - 1]);
      bool endOk = end == text.length || !wordCharRegex.hasMatch(text[end]);

      if (startOk && endOk) {
        bestMatch = match;
        break;
      }
    }

    bestMatch ??= firstMatch;

    final len = text.length;
    var start = (bestMatch!.start - (maxChars ~/ 2)).clamp(0, len);
    var end = (start + maxChars).clamp(0, len);

    // If we're at the end and didn't get enough chars, shift the window left.
    if (end - start < maxChars) {
      start = (end - maxChars).clamp(0, len);
    }

    start = findWordStart(start);
    end = findWordEnd(end);

    final prefix = start > 0 ? '... ' : '';
    final suffix = end < len ? ' ...' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  @override
  bool get wantKeepAlive => true;
}
