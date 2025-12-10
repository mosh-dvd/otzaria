import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/utils/html_link_handler.dart';

class PaginatedMainTextViewer extends StatefulWidget {
  final TextBookLoaded textBookState;
  final Function(OpenedTab) openBookCallback;
  final ItemScrollController scrollController;

  const PaginatedMainTextViewer({
    super.key,
    required this.textBookState,
    required this.openBookCallback,
    required this.scrollController,
  });

  @override
  State<PaginatedMainTextViewer> createState() =>
      _PaginatedMainTextViewerState();
}

class _PaginatedMainTextViewerState extends State<PaginatedMainTextViewer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchFocused = false;
  bool _userSelectedManually = false;
  List<int> _filteredIndices = [];

  @override
  void initState() {
    super.initState();
    _updateFilteredIndices();
    // Listen to scroll position changes and update selected index
    widget.textBookState.positionsListener.itemPositions
        .addListener(_onScrollChanged);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(PaginatedMainTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filtered indices if content changed
    if (oldWidget.textBookState.content.length !=
        widget.textBookState.content.length) {
      _updateFilteredIndices();
    }
  }

  @override
  void dispose() {
    widget.textBookState.positionsListener.itemPositions
        .removeListener(_onScrollChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _updateFilteredIndices();
    });
  }

  void _updateFilteredIndices() {
    if (_searchQuery.isEmpty) {
      _filteredIndices =
          List.generate(widget.textBookState.content.length, (i) => i);
    } else {
      final searchableQuery = utils.removeVolwels(_searchQuery.toLowerCase());
      _filteredIndices = [];
      for (int i = 0; i < widget.textBookState.content.length; i++) {
        final data = widget.textBookState.content[i];
        final searchableContent = utils.removeVolwels(data.toLowerCase());
        if (searchableContent.contains(searchableQuery)) {
          _filteredIndices.add(i);
        }
      }
    }
  }

  void _onFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  void _onScrollChanged() {
    // Don't auto-update if user manually selected
    if (_userSelectedManually) {
      _userSelectedManually = false;
      return;
    }

    final positions =
        widget.textBookState.positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // Get the first visible item
      final firstVisible =
          positions.reduce((a, b) => a.index < b.index ? a : b);
      final newIndex = firstVisible.index;

      // Update selected index if it changed
      if (widget.textBookState.selectedIndex != newIndex) {
        context.read<TextBookBloc>().add(UpdateSelectedIndex(newIndex));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Search header for main text
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
                  widget.textBookState.book.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
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
            itemScrollController: widget.scrollController,
            itemPositionsListener: widget.textBookState.positionsListener,
            itemCount: _filteredIndices.length,
            itemBuilder: (context, index) =>
                _buildLine(_filteredIndices[index], theme),
          ),
        ),
      ],
    );
  }

  Widget _buildLine(int index, ThemeData theme) {
    final state = widget.textBookState;
    final isSelected = state.selectedIndex == index;
    final isHighlighted = state.highlightedLine == index;

    final backgroundColor = () {
      if (isHighlighted) {
        return theme.colorScheme.secondaryContainer.withAlpha(100);
      }
      if (isSelected) {
        return theme.colorScheme.primaryContainer.withAlpha(30);
      }
      return null;
    }();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _userSelectedManually = true;
        context.read<TextBookBloc>().add(UpdateSelectedIndex(index));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            String data = state.content[index];

            // Apply text manipulations
            if (!settingsState.showTeamim) {
              data = utils.removeTeamim(data);
            }
            if (settingsState.replaceHolyNames) {
              data = utils.replaceHolyNames(data);
            }
            if (state.removeNikud) {
              data = utils.removeVolwels(data);
            }

            // Highlight search text (both global and local)
            String processedData = state.removeNikud
                ? utils.highLight(
                    utils.removeVolwels('$data\n'), state.searchText)
                : utils.highLight('$data\n', state.searchText);

            // Apply local search highlighting
            if (_searchQuery.isNotEmpty) {
              processedData = state.removeNikud
                  ? utils.highLight(
                      processedData, utils.removeVolwels(_searchQuery))
                  : utils.highLight(processedData, _searchQuery);
            }

            processedData = utils.formatTextWithParentheses(processedData);

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.all(8.0),
              child: HtmlWidget(
                '''
                <div style="text-align: justify; direction: rtl;">
                  $processedData
                </div>
                ''',
                key: ValueKey('html_tzurat_hadaf_$index'),
                textStyle: TextStyle(
                  fontSize: state.fontSize,
                  fontFamily: settingsState.fontFamily,
                  height: 1.5,
                ),
                onTapUrl: (url) async {
                  return await HtmlLinkHandler.handleLink(
                    context,
                    url,
                    (tab) => widget.openBookCallback(tab),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
