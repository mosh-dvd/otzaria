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
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  int _itemCount = 0;
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  final Map<int, int> _searchResultsPerItem = {};
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון

  int _getItemSearchIndex(int itemIndex) {
    int cumulativeIndex = 0;
    for (int i = 0; i < itemIndex; i++) {
      cumulativeIndex += _searchResultsPerItem[i] ?? 0;
    }

    final itemResults = _searchResultsPerItem[itemIndex] ?? 0;
    if (itemResults == 0) return -1;

    final relativeIndex = _currentSearchIndex - cumulativeIndex;
    return (relativeIndex >= 0 && relativeIndex < itemResults)
        ? relativeIndex
        : -1;
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

  void _scrollToSearchResult() {
    if (_totalSearchResults == 0 ||
        _itemCount == 0 ||
        !_itemScrollController.isAttached) {
      return;
    }

    int cumulativeIndex = 0;
    int targetItemIndex = 0;

    for (int i = 0; i < _itemCount; i++) {
      final itemResults = _searchResultsPerItem[i] ?? 0;
      if (_currentSearchIndex < cumulativeIndex + itemResults) {
        targetItemIndex = i;
        break;
      }
      cumulativeIndex += itemResults;
    }

    targetItemIndex = targetItemIndex.clamp(0, _itemCount - 1);

    _itemScrollController.scrollTo(
      index: targetItemIndex,
      duration: const Duration(milliseconds: 300),
      alignment: 0.1,
    );
  }

  void _updateSearchResultsCount(int itemIndex, int count) {
    if (mounted) {
      setState(() {
        _searchResultsPerItem[itemIndex] = count;
        _totalSearchResults =
            _searchResultsPerItem.values.fold(0, (sum, count) => sum + count);
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = _totalSearchResults - 1;
        }
      });
    }
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
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_totalSearchResults > 1) ...[
                                    Text(
                                      '${_currentSearchIndex + 1}/$_totalSearchResults',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(FluentIcons.chevron_up_24_regular),
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      onPressed: _currentSearchIndex > 0
                                          ? () {
                                              setState(() {
                                                _currentSearchIndex--;
                                              });
                                              _scrollToSearchResult();
                                            }
                                          : null,
                                    ),
                                    IconButton(
                                      icon:
                                          const Icon(FluentIcons.chevron_down_24_regular),
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      onPressed: _currentSearchIndex <
                                              _totalSearchResults - 1
                                          ? () {
                                              setState(() {
                                                _currentSearchIndex++;
                                              });
                                              _scrollToSearchResult();
                                            }
                                          : null,
                                    ),
                                  ],
                                  IconButton(
                                    icon: const Icon(FluentIcons.dismiss_24_regular),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                        _currentSearchIndex = 0;
                                        _totalSearchResults = 0;
                                        _searchResultsPerItem.clear();
                                      });
                                    },
                                  ),
                                ],
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
                            _searchResultsPerItem.clear();
                          }
                        });
                      },
                    ),
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
          ],
          Flexible(
            fit: FlexFit.loose,
            child: FutureBuilder(
              future: getLinksforIndexs(
                  indexes: widget.indexes ??
                      (state.selectedIndex != null
                          ? [state.selectedIndex!]
                          : state.visibleIndices),
                  links: state.links,
                  commentatorsToShow: state.activeCommentators),
              builder: (context, thisLinksSnapshot) {
                if (!thisLinksSnapshot.hasData) {
                  return _buildSkeletonLoading();
                }
                if (thisLinksSnapshot.data!.isEmpty) {
                  // אם אין מפרשים, פשוט נציג מסך ריק
                  return const SizedBox.shrink();
                }
                final data = thisLinksSnapshot.data!;
                _itemCount = data.length;

                // יצירת מפתח ייחודי לאינדקסים הנוכחיים
                final currentIndexes = widget.indexes ??
                    (state.selectedIndex != null
                        ? [state.selectedIndex!]
                        : state.visibleIndices);
                final indexesKey = currentIndexes.join(',');

                return ProgressiveScroll(
                  scrollController: scrollController,
                  maxSpeed: 10000.0,
                  curve: 10.0,
                  accelerationFactor: 5,
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    initialScrollIndex: _lastScrollIndex.clamp(0, data.length - 1),
                    key: PageStorageKey(
                        'commentary_${indexesKey}_${state.activeCommentators.hashCode}'),
                    physics: const ClampingScrollPhysics(),
                    scrollOffsetController: scrollController,
                    shrinkWrap: true,
                    itemCount: data.length,
                    itemBuilder: (context, index1) => ListTile(
                      title: BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          String displayTitle =
                              thisLinksSnapshot.data![index1].heRef;
                          if (settingsState.replaceHolyNames) {
                            displayTitle = utils.replaceHolyNames(displayTitle);
                          }
                          return Text(displayTitle);
                        },
                      ),
                      subtitle: CommentaryContent(
                        key: ValueKey(
                            '${thisLinksSnapshot.data![index1].path2}_${thisLinksSnapshot.data![index1].index2}_$indexesKey'),
                        link: thisLinksSnapshot.data![index1],
                        fontSize: widget.fontSize,
                        openBookCallback: widget.openBookCallback,
                        removeNikud: state.removeNikud,
                        searchQuery: widget.showSearch ? _searchQuery : '',
                        currentSearchIndex:
                            widget.showSearch ? _getItemSearchIndex(index1) : 0,
                        onSearchResultsCountChanged: widget.showSearch
                            ? (count) =>
                                _updateSearchResultsCount(index1, count)
                            : null,
                      ),
                    ),
                  ),
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
