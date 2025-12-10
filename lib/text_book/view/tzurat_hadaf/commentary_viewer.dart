import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';

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

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterLinks();
    });
  }

  void _filterLinks() {
    if (_searchQuery.isEmpty) {
      _filteredLinks = _relevantLinks;
    } else {
      _filteredLinks = _relevantLinks; // נציג הכל ונסנן בזמן הרינדור
    }
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
            color: const Color(0xFFFCFCF5), // צבע רקע בהיר
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFE0D8C0),
                width: 1,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Title centered
              Center(
                child: Text(
                  widget.commentatorName!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFFA88B68), // צבע זהב/חום
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Search at bottom left
              Positioned(
                bottom: -4,
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
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFA88B68),
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
          child: Container(
            color: const Color(0xFFFCFCF5), // רקע בהיר לטורי הצד
            child: ScrollablePositionedList.builder(
              itemScrollController: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _filteredLinks.length,
              itemBuilder: (context, index) {
                final link = _filteredLinks[index];
                final isSelected = widget.selectedIndex != null &&
                    link.index1 - 1 == widget.selectedIndex;

                return FutureBuilder<String>(
                  future: link.content,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                          height: 50,
                          child: Center(child: CircularProgressIndicator()));
                    }

                    final content = snapshot.data!;
                    
                    // Filter by search query
                    if (_searchQuery.isNotEmpty) {
                      final searchableContent = utils.removeVolwels(content.toLowerCase());
                      final searchableQuery = utils.removeVolwels(_searchQuery.toLowerCase());
                      if (!searchableContent.contains(searchableQuery)) {
                        return const SizedBox.shrink(); // Hide non-matching items
                      }
                    }

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
                          displayText = utils.highLight(displayText, _searchQuery);
                        }

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: 3.0),
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFFFFF9C4) // צהוב עדין להדגשה
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFE0D8C0),
                              width: 0.5,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: Colors.black.withAlpha(25),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ] : null,
                          ),
                          child: HtmlWidget(
                            '<div style="text-align: justify; direction: rtl; line-height: 1.5;">$displayText</div>',
                            textStyle: TextStyle(
                              fontSize: widget.textBookState.fontSize * 0.8,
                              fontFamily: settingsState.commentatorsFontFamily,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                              color: const Color(0xFF444444),
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
        ),
      ],
    );
  }
}
