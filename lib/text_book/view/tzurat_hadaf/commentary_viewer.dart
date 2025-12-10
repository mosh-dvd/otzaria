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

class _CommentaryViewerState extends State<CommentaryViewer> {
  final ItemScrollController _scrollController = ItemScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Link> _relevantLinks = [];
  List<Link> _filteredLinks = [];
  String _searchQuery = '';
  bool _isSearchFocused = false;
  final Map<String, List<String>> _loadedBooks =
      {}; // Cache for loaded book contents

  @override
  void initState() {
    super.initState();
    _loadLinks();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  void _onSearchChanged() async {
    _searchQuery = _searchController.text;
    await _filterLinks();
    setState(() {});
  }

  Future<void> _filterLinks() async {
    if (_searchQuery.isEmpty) {
      _filteredLinks = _relevantLinks;
    } else {
      final searchableQuery = utils.removeVolwels(_searchQuery.toLowerCase());
      final filtered = <Link>[];

      for (final link in _relevantLinks) {
        final content = await _getContentForLink(link);
        final searchableContent = utils.removeVolwels(content.toLowerCase());
        if (searchableContent.contains(searchableQuery)) {
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
            alignment: 0.2,
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
        // Search header
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(128),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Title centered
              Center(
                child: Text(
                  widget.commentatorName!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Search at bottom left
              Positioned(
                bottom: -12,
                left: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isSearchFocused ? 80 : 50,
                  height: 24,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'חיפוש',
                      hintStyle: TextStyle(
                        fontSize: 9,
                        color: Colors.grey[600],
                      ),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 0,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
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
                      if (_searchQuery.isNotEmpty) {
                        displayText =
                            utils.highLight(displayText, _searchQuery);
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
