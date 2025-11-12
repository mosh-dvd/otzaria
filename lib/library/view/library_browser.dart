import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/daf_yomi/daf_yomi_helper.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/file_sync/file_sync_state.dart';
import 'package:otzaria/daf_yomi/daf_yomi.dart';
import 'package:otzaria/file_sync/file_sync_widget.dart';
import 'package:otzaria/widgets/filter_list/src/filter_list_dialog.dart';
import 'package:otzaria/navigation/main_window_screen.dart';
import 'package:otzaria/widgets/filter_list/src/theme/filter_list_theme.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/resizable_preview_panel.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:otzaria/widgets/workspace_icon_button.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/settings/library_settings_dialog.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({super.key});

  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

enum ViewMode { grid, list }

class _LibraryBrowserState extends State<LibraryBrowser>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _depth = 0;
  bool _showPreview = true; // האם להציג את התצוגה המקדימה
  ViewMode _viewMode = ViewMode.grid; // מצב תצוגה: רשת או רשימה
  final Set<String> _expandedCategories = {}; // קטגוריות שנפתחו בתצוגת רשימה

  @override
  void initState() {
    super.initState();
    context.read<LibraryBloc>().add(LoadLibrary());
    _loadViewPreferences();
  }

  void _loadViewPreferences() {
    final settingsState = context.read<SettingsBloc>().state;
    setState(() {
      _showPreview = settingsState.libraryShowPreview;
      _viewMode = settingsState.libraryViewMode == 'list'
          ? ViewMode.list
          : ViewMode.grid;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocBuilder<LibraryBloc, LibraryState>(
          buildWhen: (previous, current) {
            // אל תבנה מחדש אם רק previewBook השתנה
            // נבנה מחדש רק אם שדות אחרים השתנו
            return previous.isLoading != current.isLoading ||
                previous.error != current.error ||
                previous.library != current.library ||
                previous.currentCategory != current.currentCategory ||
                previous.searchResults != current.searchResults ||
                previous.searchQuery != current.searchQuery ||
                previous.selectedTopics != current.selectedTopics;
          },
          builder: (context, state) {
            if (state.error != null) {
              return Center(child: Text('Error: ${state.error}'));
            }

            // אם אין ספרייה ולא בטעינה - הצג שגיאה
            if (state.library == null && !state.isLoading) {
              return const Center(child: Text('No library data available'));
            }

            // גם אם אין ספרייה אבל בטעינה - הצג את המסך עם שכבת טעינה
            return Stack(
              children: [
                // תוכן הספרייה - תמיד מוצג (גם אם הספרייה null)
                Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  appBar: AppBar(
                    title: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DafYomi(
                            onDafYomiTap: (tractate, daf) {
                              openDafYomiBook(context, tractate, ' $daf.');
                            },
                            onCalendarTap: () {
                              // Reset to calendar BEFORE navigation using GlobalKey
                              (moreScreenKey.currentState as dynamic)
                                  ?.resetToCalendar();
                              // Then navigate
                              context.read<NavigationBloc>().add(
                                    const NavigateToScreen(Screen.more),
                                  );
                            },
                          ),
                        ),
                        Text(
                          state.currentCategory?.title ?? '',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _buildLibraryActions(
                              context, state, settingsState),
                        ),
                      ],
                    ),
                  ),
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      // ברירת מחדל: שליש ברשת, שני שליש ברשימה
                      final previewWidth = _viewMode == ViewMode.list
                          ? (screenWidth * 2 / 3)
                          : (screenWidth / 3);

                      return Row(
                        children: [
                          // תוכן הספרייה - עכשיו בצד ימין
                          Expanded(
                            child: Column(
                              children: [
                                // שורת חיפוש והגדרות
                                _buildSearchBar(state),
                                if (context
                                        .read<FocusRepository>()
                                        .librarySearchController
                                        .text
                                        .length >
                                    2)
                                  _buildTopicsSelection(
                                      context, state, settingsState),
                                // תוכן הספרייה
                                Expanded(child: _buildContent(state)),
                              ],
                            ),
                          ),
                          // פאנל תצוגה מקדימה בצד שמאל עם מסגרת ואפשרות שינוי גודל
                          if (_showPreview)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: ResizablePreviewPanel(
                                key: ValueKey(
                                    screenWidth), // מפתח שמשתנה עם רוחב המסך
                                initialWidth: previewWidth,
                                minWidth: 300,
                                maxWidth: screenWidth -
                                    350, // השאר לפחות 350px לרשימה
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.3),
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7.0),
                                    child:
                                        BlocBuilder<LibraryBloc, LibraryState>(
                                      buildWhen: (previous, current) {
                                        // רק אם previewBook השתנה
                                        return previous.previewBook !=
                                            current.previewBook;
                                      },
                                      builder: (context, previewState) {
                                        return GestureDetector(
                                          onDoubleTap: () {
                                            if (previewState.previewBook !=
                                                null) {
                                              _openBookInReader(
                                                  previewState.previewBook!, 0);
                                            }
                                          },
                                          child: BookPreviewPanel(
                                            book: previewState.previewBook,
                                            onOpenInReader: (index) {
                                              if (previewState.previewBook !=
                                                  null) {
                                                _openBookInReader(
                                                    previewState.previewBook!,
                                                    index);
                                              }
                                            },
                                            onClose: () {
                                              setState(() {
                                                _showPreview = false;
                                              });
                                              context.read<SettingsBloc>().add(
                                                    const UpdateLibraryShowPreview(
                                                        false),
                                                  );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                // שכבת חסימה בזמן טעינה
                if (state.isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.3),
                      child: Center(
                        child: Container(
                          width: 200,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: _LoadingDotsText(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar(LibraryState state) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          final focusRepository = context.read<FocusRepository>();
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: focusRepository.librarySearchController,
                  focusNode:
                      context.read<FocusRepository>().librarySearchFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    constraints: const BoxConstraints(maxWidth: 400),
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: IconButton(
                      onPressed: () {
                        focusRepository.librarySearchController.clear();
                        _update(context, state, settingsState);
                        _refocusSearchBar();
                      },
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8.0)),
                    ),
                    hintText:
                        'איתור ספר ב${state.currentCategory?.title ?? ""}',
                  ),
                  onChanged: (value) {
                    context.read<LibraryBloc>().add(UpdateSearchQuery(value));
                    context.read<LibraryBloc>().add(const SelectTopics([]));
                    _update(context, state, settingsState);
                  },
                ),
              ),
              // כפתור מעבר בין תצוגת רשת לרשימה
              Padding(
                padding: const EdgeInsets.only(left: 2.0, right: 8.0),
                child: IconButton(
                  icon: Icon(_viewMode == ViewMode.grid
                      ? FluentIcons.list_24_regular
                      : FluentIcons.grid_24_regular),
                  tooltip: _viewMode == ViewMode.grid
                      ? 'תצוגת רשימה (עץ מתרחב)'
                      : 'תצוגת רשת',
                  onPressed: () {
                    final newViewMode = _viewMode == ViewMode.grid
                        ? ViewMode.list
                        : ViewMode.grid;
                    setState(() {
                      _viewMode = newViewMode;
                    });
                    context.read<SettingsBloc>().add(
                          UpdateLibraryViewMode(
                              newViewMode == ViewMode.list ? 'list' : 'grid'),
                        );
                  },
                  style: IconButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (!_showPreview)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: IconButton(
                    icon: const Icon(FluentIcons.eye_24_regular),
                    tooltip: 'הצג תצוגה מקדימה',
                    onPressed: () {
                      setState(() {
                        _showPreview = true;
                      });
                      context.read<SettingsBloc>().add(
                            const UpdateLibraryShowPreview(true),
                          );
                    },
                    style: IconButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              _buildSettingsButton(context, settingsState, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsButton(
      BuildContext context, SettingsState settingsState, LibraryState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: IconButton(
        icon: const Icon(FluentIcons.settings_24_regular),
        tooltip: 'הגדרות',
        onPressed: () => showLibrarySettingsDialog(context),
        style: IconButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildTopicsSelection(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (state.searchResults == null) {
      return const SizedBox.shrink();
    }

    final categoryTopics = [
      "תנך",
      "מדרש",
      "משנה",
      "תלמוד בבלי",
      "תלמוד ירושלמי",
      "הלכה",
      "משנה תורה",
      "שולחן ערוך",
      "חסידות",
      "קבלה",
      "ספרי מוסר",
      "שות",
      "ראשונים",
      "אחרונים",
      "מחברי זמננו",
    ];

    final allTopics = _getAllTopics(state.searchResults!);

    final relevantTopics =
        categoryTopics.where((element) => allTopics.contains(element)).toList();

    return FilterListWidget<String>(
      hideSearchField: true,
      controlButtons: const [],
      themeData: FilterListThemeData(
        context,
        wrapAlignment: WrapAlignment.center,
      ),
      onApplyButtonClick: (list) {
        context.read<LibraryBloc>().add(SelectTopics(list ?? []));
        _update(context, state, settingsState);
        _refocusSearchBar();
      },
      validateSelectedItem: (list, item) => list != null && list.contains(item),
      onItemSearch: (item, query) => item == query,
      listData: relevantTopics,
      selectedListData: state.selectedTopics ?? [],
      choiceChipLabel: (p0) => p0,
      hideSelectedTextCount: true,
      choiceChipBuilder: (context, item, isSelected) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Chip(
          label: Text(item),
          backgroundColor:
              isSelected! ? Theme.of(context).colorScheme.secondary : null,
          labelStyle: TextStyle(
            color:
                isSelected ? Theme.of(context).colorScheme.onSecondary : null,
            fontSize: 11,
          ),
          labelPadding: const EdgeInsets.all(0),
        ),
      ),
    );
  }

  Widget _buildContent(LibraryState state) {
    // אם אין ספרייה - הצג מסך ריק (שכבת הטעינה תכסה אותו)
    if (state.library == null || state.currentCategory == null) {
      return const Center(child: SizedBox.shrink());
    }

    // במצב תצוגת רשת - תמיד רשת
    if (_viewMode == ViewMode.grid) {
      final items = state.searchResults != null
          ? _buildSearchResults(state.searchResults!)
          : _buildCategoryContent(state.currentCategory!);

      return FutureBuilder<List<Widget>>(
        future: items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.hasData && snapshot.data!.isEmpty) {
            final focusRepository = context.read<FocusRepository>();
            return Center(
              child: Text(
                focusRepository.librarySearchController.text.isNotEmpty
                    ? 'אין תוצאות עבור "${focusRepository.librarySearchController.text}"'
                    : 'אין פריטים להצגה בתיקייה זו',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            key: PageStorageKey(state.currentCategory),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => snapshot.data![index],
          );
        },
      );
    }

    // תצוגת רשימה - גם בחיפוש וגם בלי
    if (state.searchResults != null) {
      // במצב חיפוש ברשימה - הצג רק את הספרים
      return _buildSearchListView(state.searchResults!);
    }

    // תצוגת רשימה עם עץ מתרחב
    return _buildListView(state.currentCategory!);
  }

  Future<List<Widget>> _buildSearchResults(List<Book> books) async {
    return [
      Column(
        children: [
          MyGridView(
            items: Future.value(
              books
                  .take(100)
                  .map((book) => _buildBookItem(book, showTopics: true))
                  .toList(),
            ),
          ),
        ],
      ),
    ];
  }

  Future<List<Widget>> _buildCategoryContent(Category category) async {
    List<Widget> items = [];

    // Sort and log for debugging
    category.books.sort((a, b) => a.order.compareTo(b.order));
    category.subCategories.sort((a, b) => a.order.compareTo(b.order));
    
    if (category.books.isNotEmpty && category.books.length <= 10) {
      debugPrint('🎨 Displaying "${category.title}": ${category.books.map((b) => "${b.title}(${b.order})").join(", ")}');
    }

    if (_depth != 0) {
      // Add books
      items.add(
        MyGridView(
          items: Future.value(
            category.books.map((book) => _buildBookItem(book)).toList(),
          ),
        ),
      );

      // Add subcategories
      for (Category subCategory in category.subCategories) {
        subCategory.books.sort((a, b) => a.order.compareTo(b.order));
        subCategory.subCategories.sort((a, b) => a.order.compareTo(b.order));

        items.add(Center(child: HeaderItem(category: subCategory)));
        items.add(
          MyGridView(
            items: Future.value([
              ...subCategory.books.map((book) => _buildBookItem(book)),
              ...subCategory.subCategories.map(
                (cat) => CategoryGridItem(
                  category: cat,
                  onCategoryClickCallback: () => _openCategory(cat),
                ),
              ),
            ]),
          ),
        );
      }
    } else {
      items.add(
        MyGridView(
          items: Future.value([
            ...category.books.map((book) => _buildBookItem(book)),
            ...category.subCategories.map(
              (cat) => CategoryGridItem(
                category: cat,
                onCategoryClickCallback: () => _openCategory(cat),
              ),
            ),
          ]),
        ),
      );
    }

    return items;
  }

  Widget _buildBookItem(Book book, {bool showTopics = false}) {
    if (book is ExternalBook) {
      return BookGridItem(
        book: book,
        onBookClickCallback: () => _openOtzarBook(book),
        showTopics: showTopics,
      );
    }

    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) {
        // רק אם הספר שנבחר השתנה ואחד מהם הוא הספר הנוכחי
        return (previous.previewBook != current.previewBook) &&
            (previous.previewBook == book || current.previewBook == book);
      },
      builder: (context, state) {
        final isSelected = state.previewBook == book;

        return GestureDetector(
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: BookGridItem(
              book: book,
              showTopics: showTopics,
              onBookClickCallback: () {
                // אם תצוגה מקדימה מוצגת - הצג את הספר בתצוגה
                // אחרת - פתח את הספר בעיון
                if (_showPreview) {
                  _showBookPreview(book);
                } else {
                  final index = book is PdfBook ? 1 : 0;
                  _openBookInReader(book, index);
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showBookPreview(Book book) {
    context.read<LibraryBloc>().add(SelectBookForPreview(book));
  }

  /// בניית תצוגת רשימה לתוצאות חיפוש
  Widget _buildSearchListView(List<Book> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        return _buildListBookItem(books[index], 0);
      },
    );
  }

  /// בניית תצוגת רשימה עם עץ מתרחב
  Widget _buildListView(Category category) {
    return ListView(
      children: _buildCategoryTree(category, 0),
    );
  }

  /// בניית עץ קטגוריות ברקורסיבית
  List<Widget> _buildCategoryTree(Category category, int level) {
    List<Widget> widgets = [];

    // מיון תיקיות לפני קבצים
    category.subCategories.sort((a, b) => a.order.compareTo(b.order));
    
    // מיון ספרים לפי order (שכבר מעודכן לפי דורות)
    category.books.sort((a, b) {
      final orderCompare = a.order.compareTo(b.order);
      if (orderCompare != 0) return orderCompare;
      return a.title.compareTo(b.title);
    });
    
    // Debug logging for first few books
    if (category.books.isNotEmpty && category.books.length <= 10 && level == 0) {
      debugPrint('🎨 Tree view "${category.title}": ${category.books.map((b) => "${b.title}(${b.order})").join(", ")}');
    }

    // הוספת תת-קטגוריות לפני הספרים
    for (final subCategory in category.subCategories) {
      final isExpanded = _expandedCategories.contains(subCategory.path);

      widgets.add(_buildListCategoryItem(subCategory, level, isExpanded));

      // אם הקטגוריה פתוחה, הוסף את התוכן שלה
      if (isExpanded) {
        widgets.addAll(_buildCategoryTree(subCategory, level + 1));
      }
    }

    // הוספת ספרים בקטגוריה הנוכחית אחרי התיקיות
    for (final book in category.books) {
      widgets.add(_buildListBookItem(book, level));
    }

    return widgets;
  }

  /// פריט קטגוריה בתצוגת רשימה
  Widget _buildListCategoryItem(Category category, int level, bool isExpanded) {
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedCategories.remove(category.path);
          } else {
            _expandedCategories.add(category.path);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0),
          left: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        decoration: BoxDecoration(
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
                  ? FluentIcons.folder_open_24_filled
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
            Icon(
              isExpanded
                  ? FluentIcons.chevron_up_24_regular
                  : FluentIcons.chevron_down_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// פריט ספר בתצוגת רשימה
  Widget _buildListBookItem(Book book, int level) {
    if (book is ExternalBook) {
      return _buildExternalBookListItem(book, level);
    }

    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) {
        return (previous.previewBook != current.previewBook) &&
            (previous.previewBook == book || current.previewBook == book);
      },
      builder: (context, state) {
        final isSelected = state.previewBook == book;

        return InkWell(
          onTap: () {
            // אם תצוגה מקדימה מוצגת - הצג את הספר בתצוגה
            // אחרת - פתח את הספר בעיון
            if (_showPreview) {
              _showBookPreview(book);
            } else {
              final index = book is PdfBook ? 1 : 0;
              _openBookInReader(book, index);
            }
          },
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0), // אותה הזחה כמו תיקיות
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
                  book is PdfBook
                      ? FluentIcons.document_pdf_24_regular
                      : FluentIcons.document_text_24_regular,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (book.author != null && book.author!.isNotEmpty)
                        Text(
                          book.author!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// פריט ספר חיצוני בתצוגת רשימה
  Widget _buildExternalBookListItem(ExternalBook book, int level) {
    return InkWell(
      onTap: () => _openOtzarBook(book),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0) + 32.0,
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              book.link.toString().contains('tablet.otzar.org')
                  ? 'assets/logos/otzar.ico'
                  : 'assets/logos/hebrew_books.png',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 14,
                    ),
                  ),
                  if (book.author != null && book.author!.isNotEmpty)
                    Text(
                      book.author!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              FluentIcons.open_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _openBookInReader(Book book, int index) {
    openBook(context, book, index, '');
  }

  void _openCategory(Category category) {
    setState(() => _depth++);
    context.read<LibraryBloc>().add(NavigateToCategory(category));
    _refocusSearchBar();
  }

  void _openOtzarBook(ExternalBook book) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return OtzarBookDialog(book: book);
      },
    );
    _refocusSearchBar();
  }

  void _showSwitchWorkspaceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const WorkspaceSwitcherDialog(),
    );
  }

  List<String> _getAllTopics(List<Book> books) {
    final Set<String> topics = {};
    for (final book in books) {
      topics.addAll(book.topics.split(', '));
    }
    return topics.toList();
  }

  void _update(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    // Remove all quotation marks from the search query
    final cleanSearchText = searchText.replaceAll('"', '');

    context.read<LibraryBloc>().add(
          UpdateSearchQuery(cleanSearchText),
        );
    context.read<LibraryBloc>().add(
          SearchBooks(
            showHebrewBooks: settingsState.showHebrewBooks,
            showOtzarHachochma: settingsState.showOtzarHachochma,
          ),
        );
    setState(() {});
    _refocusSearchBar();
  }

  void _refocusSearchBar({bool selectAll = false}) {
    final focusRepository = context.read<FocusRepository>();
    focusRepository.requestLibrarySearchFocus(selectAll: selectAll);
  }

  void _showHistoryDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(
      context: context,
      builder: (context) => const HistoryDialog(),
    );
  }

  void _showBookmarksDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const BookmarksDialog(),
    );
  }

  /// בניית כפתורי הפעולה של הספרייה עם רכיב רספונסיבי
  Widget _buildLibraryActions(
      BuildContext context, LibraryState state, SettingsState settingsState) {
    final screenWidth = MediaQuery.of(context).size.width;
    int maxButtons;

    if (screenWidth < 400) {
      maxButtons = 1; // כפתור אחד + "..." במסכים קטנים מאוד
    } else if (screenWidth < 500) {
      maxButtons = 2; // 2 כפתורים + "..." במסכים קטנים
    } else if (screenWidth < 600) {
      maxButtons = 3; // 3 כפתורים + "..." במסכים בינוניים קטנים
    } else if (screenWidth < 700) {
      maxButtons = 4; // 4 כפתורים + "..." במסכים בינוניים
    } else if (screenWidth < 900) {
      maxButtons = 5; // 5 כפתורים + "..." במסכים גדולים
    } else {
      maxButtons = 6; // כל הכפתורים במסכים רחבים
    }

    return ResponsiveActionBar(
      actions: _buildPrioritizedLibraryActions(context, state, settingsState),
      originalOrder:
          _buildOriginalOrderLibraryActions(context, state, settingsState),
      maxVisibleButtons: maxButtons,
      overflowOnRight: true, // כפתור "..." ימני במסך הספרייה
    );
  }

  /// בניית רשימת כפתורים בסדר המקורי (כמו במסך הרחב)
  List<ActionButtonData> _buildOriginalOrderLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return [
      // חזור לתיקיה קודמת (ראשון במסך הרחב)
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_up_24_regular),
          tooltip: 'חזרה לתיקיה הקודמת',
          onPressed: () {
            // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
            if (_viewMode == ViewMode.list && _expandedCategories.isNotEmpty) {
              setState(() {
                _expandedCategories.remove(_expandedCategories.last);
              });
            }
            // בתצוגת רשת - חזור לקטגוריה הקודמת
            else if (state.currentCategory?.parent != null) {
              setState(() {
                _depth = _depth > 0 ? _depth - 1 : 0;
              });
              context.read<LibraryBloc>().add(NavigateUp());
              context.read<LibraryBloc>().add(const SearchBooks());
              _refocusSearchBar(selectAll: true);
            }
          },
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () {
          // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
          if (_viewMode == ViewMode.list && _expandedCategories.isNotEmpty) {
            setState(() {
              _expandedCategories.remove(_expandedCategories.last);
            });
          }
          // בתצוגת רשת - חזור לקטגוריה הקודמת
          else if (state.currentCategory?.parent != null) {
            setState(() {
              _depth = _depth > 0 ? _depth - 1 : 0;
            });
            context.read<LibraryBloc>().add(NavigateUp());
            context.read<LibraryBloc>().add(const SearchBooks());
            _refocusSearchBar(selectAll: true);
          }
        },
      ),

      // חזרה לתיקיה ראשית
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.home_24_regular),
          tooltip: 'חזרה לתיקיה הראשית',
          onPressed: () {
            setState(() {
              _depth = 0;
              _expandedCategories.clear(); // נקה את העץ הפתוח
            });
            context.read<LibraryBloc>().add(LoadLibrary());
            context.read<FocusRepository>().librarySearchController.clear();
            _update(context, state, settingsState);
            _refocusSearchBar(selectAll: true);
          },
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () {
          setState(() {
            _depth = 0;
            _expandedCategories.clear(); // נקה את העץ הפתוח
          });
          context.read<LibraryBloc>().add(LoadLibrary());
          context.read<FocusRepository>().librarySearchController.clear();
          _update(context, state, settingsState);
          _refocusSearchBar(selectAll: true);
        },
      ),

      // סינכרון
      ActionButtonData(
        widget: BlocProvider(
          create: (context) => FileSyncBloc(
            repository: FileSyncRepository(
              githubOwner: "Y-PLONI",
              repositoryName: "otzaria-library",
              branch: "main",
            ),
          ),
          child: BlocListener<FileSyncBloc, FileSyncState>(
            listener: (context, syncState) {
              if ((syncState.status == FileSyncStatus.completed ||
                      syncState.status == FileSyncStatus.error) &&
                  syncState.hasNewSync) {
                context.read<LibraryBloc>().add(RefreshLibrary());
              }
            },
            child: const SyncIconButton(),
          ),
        ),
        icon: FluentIcons.arrow_sync_24_regular,
        tooltip: 'סינכרון',
        onPressed: () {
          // הפעולה מטופלת ב-SyncIconButton
        },
      ),

      // טעינה מחדש
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          tooltip: 'טעינה מחדש של רשימת הספרים',
          onPressed: () {
            context.read<LibraryBloc>().add(RefreshLibrary());
          },
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () {
          context.read<LibraryBloc>().add(RefreshLibrary());
        },
      ),

      // היסטוריה
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.history_24_regular),
          tooltip:
              'הצג היסטוריה (${(Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h').toUpperCase()})',
          onPressed: () => _showHistoryDialog(context),
        ),
        icon: FluentIcons.history_24_regular,
        tooltip:
            'הצג היסטוריה (${(Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h').toUpperCase()})',
        onPressed: () => _showHistoryDialog(context),
      ),

      // סימניות
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.bookmark_24_regular),
          tooltip:
              'הצג סימניות (${(Settings.getValue<String>('key-shortcut-open-bookmarks') ?? 'ctrl+shift+b').toUpperCase()})',
          onPressed: () => _showBookmarksDialog(context),
        ),
        icon: FluentIcons.bookmark_24_regular,
        tooltip:
            'הצג סימניות (${(Settings.getValue<String>('key-shortcut-open-bookmarks') ?? 'ctrl+shift+b').toUpperCase()})',
        onPressed: () => _showBookmarksDialog(context),
      ),

      // החלף שולחן עבודה
      ActionButtonData(
        widget: SizedBox(
          width: 180,
          child: WorkspaceIconButton(
            onPressed: () => _showSwitchWorkspaceDialog(context),
          ),
        ),
        icon: FluentIcons.grid_24_regular,
        tooltip: 'החלף שולחן עבודה',
        onPressed: () => _showSwitchWorkspaceDialog(context),
      ),
    ];
  }

  /// בניית רשימת כפתורים לפי סדר עדיפות (החשוב ביותר ראשון)
  List<ActionButtonData> _buildPrioritizedLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return [
      // 1) חזור לתיקיה קודמת, חזרה לתיקיה ראשית (החשובים ביותר)
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_up_24_regular),
          tooltip: 'חזרה לתיקיה הקודמת',
          onPressed: () {
            // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
            if (_viewMode == ViewMode.list && _expandedCategories.isNotEmpty) {
              setState(() {
                _expandedCategories.remove(_expandedCategories.last);
              });
            }
            // בתצוגת רשת - חזור לקטגוריה הקודמת
            else if (state.currentCategory?.parent != null) {
              setState(() {
                _depth = _depth > 0 ? _depth - 1 : 0;
              });
              context.read<LibraryBloc>().add(NavigateUp());
              context.read<LibraryBloc>().add(const SearchBooks());
              _refocusSearchBar(selectAll: true);
            }
          },
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () {
          // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
          if (_viewMode == ViewMode.list && _expandedCategories.isNotEmpty) {
            setState(() {
              _expandedCategories.remove(_expandedCategories.last);
            });
          }
          // בתצוגת רשת - חזור לקטגוריה הקודמת
          else if (state.currentCategory?.parent != null) {
            setState(() {
              _depth = _depth > 0 ? _depth - 1 : 0;
            });
            context.read<LibraryBloc>().add(NavigateUp());
            context.read<LibraryBloc>().add(const SearchBooks());
            _refocusSearchBar(selectAll: true);
          }
        },
      ),

      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.home_24_regular),
          tooltip: 'חזרה לתיקיה הראשית',
          onPressed: () {
            setState(() {
              _depth = 0;
              _expandedCategories.clear(); // נקה את העץ הפתוח
            });
            context.read<LibraryBloc>().add(LoadLibrary());
            context.read<FocusRepository>().librarySearchController.clear();
            _update(context, state, settingsState);
            _refocusSearchBar(selectAll: true);
          },
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () {
          setState(() {
            _depth = 0;
            _expandedCategories.clear(); // נקה את העץ הפתוח
          });
          context.read<LibraryBloc>().add(LoadLibrary());
          context.read<FocusRepository>().librarySearchController.clear();
          _update(context, state, settingsState);
          _refocusSearchBar(selectAll: true);
        },
      ),

      // 2) הצג היסטוריה, הצג סימניות
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.history_24_regular),
          tooltip:
              'הצג היסטוריה (${(Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h').toUpperCase()})',
          onPressed: () => _showHistoryDialog(context),
        ),
        icon: FluentIcons.history_24_regular,
        tooltip:
            'הצג היסטוריה (${(Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h').toUpperCase()})',
        onPressed: () => _showHistoryDialog(context),
      ),

      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.bookmark_24_regular),
          tooltip:
              'הצג סימניות (${(Settings.getValue<String>('key-shortcut-open-bookmarks') ?? 'ctrl+shift+b').toUpperCase()})',
          onPressed: () => _showBookmarksDialog(context),
        ),
        icon: FluentIcons.bookmark_24_regular,
        tooltip:
            'הצג סימניות (${(Settings.getValue<String>('key-shortcut-open-bookmarks') ?? 'ctrl+shift+b').toUpperCase()})',
        onPressed: () => _showBookmarksDialog(context),
      ),

      // 3) החלף שולחן עבודה
      ActionButtonData(
        widget: SizedBox(
          width: 180,
          child: WorkspaceIconButton(
            onPressed: () => _showSwitchWorkspaceDialog(context),
          ),
        ),
        icon: FluentIcons.grid_24_regular,
        tooltip: 'החלף שולחן עבודה',
        onPressed: () => _showSwitchWorkspaceDialog(context),
      ),

      // 4) סינכרון
      ActionButtonData(
        widget: BlocProvider(
          create: (context) => FileSyncBloc(
            repository: FileSyncRepository(
              githubOwner: "Y-PLONI",
              repositoryName: "otzaria-library",
              branch: "main",
            ),
          ),
          child: BlocListener<FileSyncBloc, FileSyncState>(
            listener: (context, syncState) {
              if ((syncState.status == FileSyncStatus.completed ||
                      syncState.status == FileSyncStatus.error) &&
                  syncState.hasNewSync) {
                context.read<LibraryBloc>().add(RefreshLibrary());
              }
            },
            child: const SyncIconButton(),
          ),
        ),
        icon: FluentIcons.arrow_sync_24_regular,
        tooltip: 'סינכרון',
        onPressed: () {
          // הפעולה מטופלת ב-SyncIconButton
        },
      ),

      // 5) טעינה מחדש של רשימת הספרים
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          tooltip: 'טעינה מחדש של רשימת הספרים',
          onPressed: () {
            context.read<LibraryBloc>().add(RefreshLibrary());
          },
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () {
          context.read<LibraryBloc>().add(RefreshLibrary());
        },
      ),
    ];
  }
}

/// Widget שמציג טקסט "טוען ספרייה" עם שלוש נקודות מתחלפות
class _LoadingDotsText extends StatefulWidget {
  const _LoadingDotsText();

  @override
  State<_LoadingDotsText> createState() => _LoadingDotsTextState();
}

class _LoadingDotsTextState extends State<_LoadingDotsText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // חישוב כמה נקודות להציג (0-3)
        final progress = _controller.value;
        int dots;
        if (progress < 0.25) {
          dots = 0;
        } else if (progress < 0.5) {
          dots = 1;
        } else if (progress < 0.75) {
          dots = 2;
        } else {
          dots = 3;
        }

        // יצירת מחרוזת עם 3 תווים: נקודות + רווחים
        final dotsString = '.' * dots + ' ' * (3 - dots);

        return Text(
          'טוען ספרייה$dotsString',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }
}
