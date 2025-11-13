import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

// Constants
const double _kMinQueryLength = 2;

/// A reusable divider widget that creates a line with a consistent height,
/// color, and margin to match other dividers in the UI.
class ThinDivider extends StatelessWidget {
  const ThinDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1, // 1 logical pixel is sufficient here
      color: Colors.grey.shade300,
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
    );
  }
}

class SearchFacetFiltering extends StatefulWidget {
  final SearchingTab tab;

  const SearchFacetFiltering({
    super.key,
    required this.tab,
  });

  @override
  State<SearchFacetFiltering> createState() => _SearchFacetFilteringState();
}

class _SearchFacetFilteringState extends State<SearchFacetFiltering>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _filterQuery = TextEditingController();
  
  // Use a static map to preserve expansion state across rebuilds
  static final Map<String, Map<String, bool>> _expansionStateByTab = {};
  
  Map<String, bool> get _expansionState {
    final tabKey = widget.tab.hashCode.toString();
    _expansionStateByTab[tabKey] ??= {};
    return _expansionStateByTab[tabKey]!;
  }

  @override
  void dispose() {
    _filterQuery.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterQuery.clear();
    context.read<SearchBloc>().add(ClearFilter());
  }

  @override
  void initState() {
    super.initState();
    _filterQuery.text = context.read<SearchBloc>().state.filterQuery ?? '';
    // Initialize expansion state - level 0 is always expanded
    _initializeExpansionState();
  }
  
  void _initializeExpansionState() {
    // This will be called once to set initial state
    // Level 0 categories should be expanded by default
  }

  void _onQueryChanged(String query) {
    if (query.length >= _kMinQueryLength) {
      context.read<SearchBloc>().add(UpdateFilterQuery(query));
    } else if (query.isEmpty) {
      context.read<SearchBloc>().add(ClearFilter());
    }
  }

  void _handleFacetToggle(BuildContext context, String facet) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    if (state.currentFacets.contains(facet)) {
      searchBloc.add(RemoveFacet(facet));
    } else {
      searchBloc.add(AddFacet(facet));
    }
  }

  void _setFacet(BuildContext context, String facet) {
    debugPrint('🔍 [FACET] Setting facet to: "$facet"');
    context.read<SearchBloc>().add(SetFacet(facet));
  }

  Widget _buildSearchField() {
    return Container(
      height: 60, // Same height as the container on the right
      alignment: Alignment.center, // Vertically centers the TextField
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: TextField(
        controller: _filterQuery,
        decoration: InputDecoration(
          hintText: 'איתור ספר…',
          prefixIcon: const Icon(FluentIcons.filter_24_regular),
          suffixIcon: IconButton(
            onPressed: _clearFilter,
            icon: const Icon(FluentIcons.dismiss_24_regular),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  Widget _buildBookTile(Book book, int count, int level,
      {String? categoryPath}) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    // בניית facet נכון על בסיס נתיב הקטגוריה
    final facet =
        categoryPath != null ? "$categoryPath/${book.title}" : "/${book.title}";
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        final isSelected = state.currentFacets.contains(facet);
        return InkWell(
          onTap: () => HardwareKeyboard.instance.isControlPressed
              ? _handleFacetToggle(context, facet)
              : _setFacet(context, facet),
          onDoubleTap: () => _handleFacetToggle(context, facet),
          onLongPress: () => _handleFacetToggle(context, facet),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0) + 32.0, // הזחה נוספת לספרים
              left: 16.0,
              top: 10.0,
              bottom: 10.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.book_24_regular,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    book.title,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                // מספר התוצאות
                if (count != -1)
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (count == -1)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }



  Widget _buildCategoryTile(Category category, int count, int level) {
    if (count == 0) return const SizedBox.shrink();

    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        final isSelected = state.currentFacets.contains(category.path);
        
        // Initialize expansion state for this category if not set
        if (!_expansionState.containsKey(category.path)) {
          _expansionState[category.path] = level == 0;
        }
        final isExpanded = _expansionState[category.path]!;

        void toggle() {
          setState(() {
            _expansionState[category.path] = !isExpanded;
          });
        }

        return Column(
          children: [
            // שורת הקטגוריה - סגנון ספרייה
            InkWell(
              onTap: () {
                // Ctrl+לחיצה = toggle, לחיצה רגילה = set
                if (HardwareKeyboard.instance.isControlPressed) {
                  _handleFacetToggle(context, category.path);
                } else {
                  _setFacet(context, category.path);
                }
              },
              onLongPress: () => _handleFacetToggle(context, category.path),
              child: Container(
                padding: EdgeInsets.only(
                  right: 16.0 + (level * 24.0),
                  left: 16.0,
                  top: 12.0,
                  bottom: 12.0,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? FluentIcons.folder_open_24_regular
                          : FluentIcons.folder_24_regular,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    // מספר התוצאות
                    if (count != -1)
                      Text(
                        '($count)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (count == -1)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    const SizedBox(width: 8),
                    // כפתור החץ - מרחיב/מכווץ בלבד
                    InkWell(
                      onTap: toggle,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          isExpanded
                              ? FluentIcons.chevron_up_24_regular
                              : FluentIcons.chevron_down_24_regular,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ילדים
            if (isExpanded)
              Column(children: _buildCategoryChildren(category, level)),
          ],
        );
      },
    );
  }

  // Helper to count results in category by checking book titles
  int _countResultsInCategory(Category category, SearchState state) {
    if (state.results.isEmpty) return 0;
    
    final allBooks = category.getAllBooks();
    final bookTitles = allBooks.map((b) => b.title).toSet();
    
    // Count how many results have a title that belongs to this category
    return state.results.where((r) => bookTitles.contains(r.title)).length;
  }


  // Find all matching categories and books for filter
  List<Widget> _findMatches(Category root, SearchState searchState) {
    final matches = <Widget>[];
    final query = _filterQuery.text.toLowerCase();
    
    void searchInCategory(Category category, int level) {
      // Check if category name matches
      if (category.title.toLowerCase().contains(query)) {
        final count = _countResultsInCategory(category, searchState);
        if (count > 0) {
          matches.add(_buildCategoryTile(category, count, 0));
        }
      }
      
      // Check books in this category
      for (final book in category.books) {
        if (book.title.toLowerCase().contains(query)) {
          final count = searchState.results.where((r) => r.title == book.title).length;
          if (count > 0) {
            matches.add(_buildBookTile(book, count, 0, categoryPath: category.path));
          }
        }
      }
      
      // Search in subcategories
      for (final sub in category.subCategories) {
        searchInCategory(sub, level + 1);
      }
    }
    
    searchInCategory(root, 0);
    return matches;
  }

  List<Widget> _buildCategoryChildren(Category category, int level) {
    final List<Widget> children = [];

    // הוספת תת-קטגוריות
    for (final subCategory in category.subCategories) {
      children.add(BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          // Count results in this subcategory from current search results
          final count = _countResultsInCategory(subCategory, state);
          
          // מציגים את הקטגוריה רק אם יש בה תוצאות
          if (count > 0) {
            return _buildCategoryTile(subCategory, count, level + 1);
          }
          return const SizedBox.shrink();
        },
      ));
    }

    // הוספת ספרים - כל ספר מוצג פעם אחת עם ספירה כוללת
    for (final book in category.books) {
      children.add(BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          // Count ALL results for this book (not just one per result)
          final count = state.results.where((r) => r.title == book.title).length;
          
          if (count > 0) {
            return _buildBookTile(book, count, level + 1,
                categoryPath: category.path);
          }
          return const SizedBox.shrink();
        },
      ));
    }

    return children;
  }



  Widget _buildFacetTree() {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (libraryState.error != null) {
          return Center(child: Text('Error: ${libraryState.error}'));
        }

        // אם יש סינון טקסט, הצג רשימה שטוחה
        if (_filterQuery.text.length >= _kMinQueryLength) {
          return BlocBuilder<SearchBloc, SearchState>(
            builder: (context, searchState) {
              if (libraryState.library == null) {
                return const Center(child: Text('No library data available'));
              }

              // מצא את כל הקטגוריות והספרים המתאימים
              final matches = _findMatches(libraryState.library!, searchState);
              
              if (matches.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('לא נמצאו תוצאות'),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: matches.length,
                itemBuilder: (context, index) => matches[index],
              );
            },
          );
        }

        // אחרת, הצג את העץ המלא
        return BlocBuilder<SearchBloc, SearchState>(
          builder: (context, searchState) {

            if (libraryState.library == null) {
              return const Center(child: Text('No library data available'));
            }

            final rootCategory = libraryState.library!;
            
            // Count total results
            final totalCount = searchState.results.length;
            
            return SingleChildScrollView(
              key: PageStorageKey(widget.tab),
              child: _buildCategoryTile(rootCategory, totalCount, 0),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildSearchField(),
        const ThinDivider(), // Now perfectly aligned
        Expanded(
          child: _buildFacetTree(),
        ),
      ],
    );
  }
}
