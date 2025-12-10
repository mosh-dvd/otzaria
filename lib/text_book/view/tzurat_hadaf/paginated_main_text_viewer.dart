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

  @override
  void initState() {
    super.initState();
    // Listen to scroll position changes and update selected index
    widget.textBookState.positionsListener.itemPositions.addListener(_onScrollChanged);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.textBookState.positionsListener.itemPositions.removeListener(_onScrollChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _onFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  void _onScrollChanged() {
    final positions = widget.textBookState.positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // Get the first visible item
      final firstVisible = positions.reduce((a, b) => a.index < b.index ? a : b);
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
            color: const Color(0xFFFDFAF2), // צבע דף קרם
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFE0D8C0),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.textBookState.book.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFFA88B68), // צבע זהב/חום
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isSearchFocused ? 100 : 60,
                height: 28,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'חיפוש',
                    hintStyle: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[400]!),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFFA88B68),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    isDense: true,
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
            itemCount: widget.textBookState.content.length,
            itemBuilder: (context, index) => _buildLine(index, theme),
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
        return theme.colorScheme.primaryContainer.withAlpha(50);
      }
      return null;
    }();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
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
                  ? utils.highLight(processedData, utils.removeVolwels(_searchQuery))
                  : utils.highLight(processedData, _searchQuery);
            }
            
            processedData = utils.formatTextWithParentheses(processedData);

            // Filter by local search query
            if (_searchQuery.isNotEmpty) {
              final searchableContent = utils.removeVolwels(data.toLowerCase());
              final searchableQuery = utils.removeVolwels(_searchQuery.toLowerCase());
              if (!searchableContent.contains(searchableQuery)) {
                return const SizedBox.shrink(); // Hide non-matching items
              }
            }

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDFAF2), // צבע דף קרם
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFFE0D8C0), // גבול עדין
                  width: 0.5,
                ),
              ),
              padding: const EdgeInsets.all(12.0),
              child: HtmlWidget(
                '''
                <div style="text-align: justify; direction: rtl; line-height: 1.6;">
                  $processedData
                </div>
                ''',
                key: ValueKey('html_tzurat_hadaf_$index'),
                textStyle: TextStyle(
                  fontSize: state.fontSize,
                  fontFamily: settingsState.fontFamily,
                  height: 1.6,
                  color: const Color(0xFF2C2C2C), // צבע טקסט כהה
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
