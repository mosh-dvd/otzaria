import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_content.dart';
import 'package:otzaria/widgets/progressive_scrolling.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
class CommentaryGroup {
  final String bookTitle;
  final List<Link> links;

  CommentaryGroup({required this.bookTitle, required this.links});
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    final title = utils.getTitleFromPath(link.path2);

    if (currentTitle == null || currentTitle != title) {
      // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      // אותו ספר - מוסיף לקבוצה הנוכחית
      currentGroup.add(link);
    }
  }

  // מוסיף את הקבוצה האחרונה
  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}

class CommentaryListBase extends StatefulWidget {
  final Function(TextBookTab) openBookCallback;
  final double fontSize;
  final List<int>? indexes;
  final bool showSearch;
  final VoidCallback? onClosePane;

  const CommentaryListBase({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.indexes,
    required this.showSearch,
    this.onClosePane,
  });

  @override
  State<CommentaryListBase> createState() => _CommentaryListBaseState();
}

class _CommentaryListBaseState extends State<CommentaryListBase> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  final Map<String, int> _searchResultsPerLink = {}; // שונה למפתח String
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  bool _allExpanded = true; // מצב גלובלי של פתיחה/סגירה של כל המפרשים


  String _getLinkKey(Link link) => '${link.path2}_${link.index2}';

  int _getItemSearchIndex(Link link) {
    // פשוט מחזיר 0 - החיפוש יעבוד בתוך CommentaryContent
    return 0;
  }

  @override
  void initState() {
    super.initState();
    // האזנה לשינויים במיקום הגלילה כדי לשמור את המיקום האחרון
    _itemPositionsListener.itemPositions.addListener(_updateLastScrollIndex);
  }

  void _updateLastScrollIndex() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // שומר את האינדקס של הפריט הראשון הנראה
      _lastScrollIndex = positions.first.index;
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_updateLastScrollIndex);
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (mounted) {
      setState(() {
        _searchResultsPerLink[_getLinkKey(link)] = count;
        _totalSearchResults =
            _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = _totalSearchResults - 1;
        }
      });
    }
  }

  Widget _buildCommentaryGroupTile({
    required CommentaryGroup group,
    required TextBookLoaded state,
    required String indexesKey,
  }) {
    final groupKey = '${group.bookTitle}_${indexesKey}_$_allExpanded';

    return ExpansionTile(
      key: PageStorageKey(groupKey),
      maintainState: true,
      initiallyExpanded: _allExpanded, // נשלט על ידי המצב הגלובלי
      backgroundColor: Theme.of(context).colorScheme.surface,
      collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
      title: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          String displayTitle = group.bookTitle;
          if (settingsState.replaceHolyNames) {
            displayTitle = utils.replaceHolyNames(displayTitle);
          }
          return Text(
            displayTitle,
            style: TextStyle(
              fontSize: widget.fontSize * 0.85,
              fontWeight: FontWeight.bold,
              fontFamily: 'FrankRuhlCLM',
            ),
          );
        },
      ),
      children: group.links.map((link) {
        return ListTile(
          contentPadding: const EdgeInsets.only(right: 32.0, left: 16.0),
          title: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              String displayTitle = link.heRef;
              if (settingsState.replaceHolyNames) {
                displayTitle = utils.replaceHolyNames(displayTitle);
              }

              return Text(
                displayTitle,
                style: TextStyle(
                  fontSize: widget.fontSize * 0.75,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'FrankRuhlCLM',
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              );
            },
          ),
          subtitle: CommentaryContent(
            key: ValueKey('${link.path2}_${link.index2}_$indexesKey'),
            link: link,
            fontSize: widget.fontSize,
            openBookCallback: widget.openBookCallback,
            removeNikud: state.removeNikud,
            searchQuery: widget.showSearch ? _searchQuery : '',
            currentSearchIndex:
                widget.showSearch ? _getItemSearchIndex(link) : 0,
            onSearchResultsCountChanged: widget.showSearch
                ? (count) => _updateSearchResultsCount(link, count)
                : null,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(builder: (context, state) {
      if (state is! TextBookLoaded) return const Center();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSearch) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'חפש בתוך המפרשים המוצגים...',
                        prefixIcon: const Icon(FluentIcons.search_24_regular),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(FluentIcons.dismiss_24_regular),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _currentSearchIndex = 0;
                                    _totalSearchResults = 0;
                                    _searchResultsPerLink.clear();
                                  });
                                },
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _currentSearchIndex = 0;
                          if (value.isEmpty) {
                            _totalSearchResults = 0;
                            _searchResultsPerLink.clear();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // כפתור סגירה/פתיחה גלובלית של כל המפרשים - מוצג רק אם יש מפרשים פעילים
                  if (state.activeCommentators.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _allExpanded
                            ? FluentIcons.arrow_collapse_all_24_regular
                            : FluentIcons.arrow_expand_all_24_regular,
                      ),
                      tooltip: _allExpanded ? 'סגור את כל המפרשים' : 'פתח את כל המפרשים',
                      onPressed: () {
                        setState(() {
                          _allExpanded = !_allExpanded;
                        });
                      },
                    ),
                  // מציג את לחצן הסגירה רק אם יש callback
                  if (widget.onClosePane != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        iconSize: 18,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: widget.onClosePane,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // כפתור סגירה/פתיחה גלובלית כאשר אין תיבת חיפוש - מוצג רק אם יש מפרשים פעילים
            if (state.activeCommentators.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        _allExpanded
                            ? FluentIcons.arrow_collapse_all_24_regular
                            : FluentIcons.arrow_expand_all_24_regular,
                      ),
                      tooltip: _allExpanded ? 'סגור את כל המפרשים' : 'פתח את כל המפרשים',
                      onPressed: () {
                        setState(() {
                          _allExpanded = !_allExpanded;
                        });
                      },
                    ),
                  ],
                ),
              ),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Builder(
              builder: (context) {
                // בודק מראש אם יש קישורים רלוונטיים לאינדקסים הנוכחיים
                final currentIndexes = widget.indexes ??
                    (state.selectedIndex != null
                        ? [state.selectedIndex!]
                        : state.visibleIndices);
                
                // סינון מהיר של קישורים רלוונטיים
                final hasRelevantLinks = state.links.any((link) =>
                    currentIndexes.contains(link.index1 - 1) &&
                    state.activeCommentators.contains(
                        utils.getTitleFromPath(link.path2)));
                
                // אם אין קישורים רלוונטיים, לא מציג כלום
                if (!hasRelevantLinks) {
                  return const SizedBox.shrink();
                }
                
                return FutureBuilder(
                  future: getLinksforIndexs(
                      indexes: currentIndexes,
                      links: state.links,
                      commentatorsToShow: state.activeCommentators),
                  builder: (context, thisLinksSnapshot) {
                    if (!thisLinksSnapshot.hasData) {
                      // רק אם יש קישורים רלוונטיים, מציג אנימציית טעינה
                      return _buildSkeletonLoading();
                    }
                    if (thisLinksSnapshot.data!.isEmpty) {
                      // אם אין מפרשים, פשוט נציג מסך ריק
                      return const SizedBox.shrink();
                    }
                    final data = thisLinksSnapshot.data!;

                    // מקבץ את הקישורים לקבוצות רצופות
                    final groups = _groupConsecutiveLinks(data);

                    // יצירת מפתח ייחודי לאינדקסים הנוכחיים
                    final indexesKey = currentIndexes.join(',');

                    return ProgressiveScroll(
                      scrollController: scrollController,
                      maxSpeed: 10000.0,
                      curve: 10.0,
                      accelerationFactor: 5,
                      child: ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        initialScrollIndex:
                            _lastScrollIndex.clamp(0, groups.length - 1),
                        key: PageStorageKey(
                            'commentary_${indexesKey}_${state.activeCommentators.hashCode}'),
                        physics: const ClampingScrollPhysics(),
                        scrollOffsetController: scrollController,
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (context, groupIndex) {
                          final group = groups[groupIndex];
                          return _buildCommentaryGroupTile(
                            group: group,
                            state: state,
                            indexesKey: indexesKey,
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// בניית skeleton loading לפרשנות - מספר פרשנויות עם כותרת ושלוש שורות
  Widget _buildSkeletonLoading() {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4, // מציג 4 שלדים של פרשנויות
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // כותרת הפרשן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _SkeletonLine(width: 0.3, height: 20, color: baseColor),
              ),
            ),
            // שלוש שורות תוכן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.95, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.92, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.88, height: 16, color: baseColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget של שורה סטטית לשלד טעינה
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}


