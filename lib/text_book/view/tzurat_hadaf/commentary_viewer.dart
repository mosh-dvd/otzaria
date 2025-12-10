import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/tzurat_hadaf/widgets/search_header.dart';
import 'package:otzaria/text_book/view/tzurat_hadaf/mixins/searchable_list_mixin.dart';

class CommentaryViewer extends StatefulWidget {
  final String? commentatorName;
  final int? selectedIndex;
  final TextBookLoaded textBookState;

  const CommentaryViewer({
    super.key,
    required this.commentatorName,
    required this.selectedIndex,
    required this.textBookState,
  });

  @override
  State<CommentaryViewer> createState() => _CommentaryViewerState();
}

class _CommentaryViewerState extends State<CommentaryViewer>
    with SearchableListMixin {
  final ItemScrollController _scrollController = ItemScrollController();
  List<Link> _relevantLinks = [];
  List<Link> _filteredLinks = [];
  final Map<String, List<String>> _loadedBooks =
      {}; // Cache for loaded book contents

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void updateFilteredItems() async {
    await _filterLinks();
  }

  Future<void> _filterLinks() async {
    if (searchQuery.isEmpty) {
      _filteredLinks = _relevantLinks;
    } else {
      final filtered = <Link>[];

      for (final link in _relevantLinks) {
        final content = await _getContentForLink(link);
        if (matchesSearch(content, searchQuery)) {
          filtered.add(link);
        }
      }

      _filteredLinks = filtered;
    }
  }

  Future<String> _getContentForLink(Link link) async {
    final bookPath = link.path2;

    // Load the entire book if not already loaded
    if (!_loadedBooks.containsKey(bookPath)) {
      final book = TextBook(title: utils.getTitleFromPath(bookPath));
      final bookContent = await book.text;
      final lines = bookContent.split('\n');
      _loadedBooks[bookPath] = lines;
    }

    // Get the specific line from the loaded book
    final lines = _loadedBooks[bookPath]!;
    final index = link.index2 - 1;

    if (index >= 0 && index < lines.length) {
      return lines[index];
    }

    return '';
  }

  @override
  void didUpdateWidget(CommentaryViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentatorName != widget.commentatorName) {
      _loadLinks();
    } else if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToSelected();
    }
  }

  void _loadLinks() {
    if (widget.commentatorName == null) {
      setState(() {
        _relevantLinks = [];
        _filteredLinks = [];
      });
      return;
    }

    // Get all links for this commentator
    final links = widget.textBookState.links.where((link) {
      return utils.getTitleFromPath(link.path2) == widget.commentatorName;
    }).toList();

    // Sort by index1 to maintain order
    links.sort((a, b) => a.index1.compareTo(b.index1));

    setState(() {
      _relevantLinks = links;
      _filterLinks();
    });

    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (widget.selectedIndex == null || _filteredLinks.isEmpty) return;

    // Find first link that matches the selected index
    final targetIndex = _filteredLinks.indexWhere(
      (link) => link.index1 - 1 == widget.selectedIndex,
    );

    if (targetIndex != -1 && _scrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.isAttached) {
          _scrollController.scrollTo(
            index: targetIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.commentatorName == null) {
      return const Center(
        child: Text(
          'בחר מפרש',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_relevantLinks.isEmpty) {
      return const Center(child: Text('אין מפרשים להצגה'));
    }

    return Column(
      children: [
        SearchHeader(
          title: widget.commentatorName!,
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          titleFontSize: 12,
        ),
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _filteredLinks.length,
            itemBuilder: (context, index) {
              final link = _filteredLinks[index];
              final lineIndex = link.index1 - 1;
              final isSelected = widget.selectedIndex != null &&
                  lineIndex == widget.selectedIndex;
              final isHighlighted =
                  widget.textBookState.highlightedLine == lineIndex;

              return FutureBuilder<String>(
                future: _getContentForLink(link),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                        height: 50,
                        child: Center(child: CircularProgressIndicator()));
                  }

                  final content = snapshot.data!;

                  return BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, settingsState) {
                      String displayText = content;
                      if (settingsState.replaceHolyNames) {
                        displayText = utils.replaceHolyNames(displayText);
                      }
                      if (widget.textBookState.removeNikud) {
                        displayText = utils.removeVolwels(displayText);
                      }

                      // Highlight search text
                      if (searchQuery.isNotEmpty) {
                        displayText = utils.highLight(displayText, searchQuery);
                      }

                      final backgroundColor = () {
                        if (isHighlighted) {
                          return Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.4);
                        }
                        if (isSelected) {
                          return Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withAlpha(40);
                        }
                        return null;
                      }();

                      return GestureDetector(
                        onTap: () {
                          // Scroll to the line in main text and highlight it
                          widget.textBookState.scrollController.scrollTo(
                            index: lineIndex,
                            alignment: 0.05,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          );
                          context
                              .read<TextBookBloc>()
                              .add(UpdateSelectedIndex(lineIndex));
                          context
                              .read<TextBookBloc>()
                              .add(HighlightLine(lineIndex));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: 2.0),
                          padding: const EdgeInsets.all(8.0),
                          decoration: backgroundColor != null
                              ? BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(4),
                                )
                              : null,
                          child: HtmlWidget(
                            '<div style="text-align: justify; direction: rtl;">$displayText</div>',
                            textStyle: TextStyle(
                              fontSize: widget.textBookState.fontSize * 0.8,
                              fontFamily: settingsState.commentatorsFontFamily,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
