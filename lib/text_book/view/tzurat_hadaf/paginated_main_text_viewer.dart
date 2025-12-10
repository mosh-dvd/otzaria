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
  @override
  void initState() {
    super.initState();
    // Listen to scroll position changes and update selected index
    widget.textBookState.positionsListener.itemPositions.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    widget.textBookState.positionsListener.itemPositions.removeListener(_onScrollChanged);
    super.dispose();
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
    return ScrollablePositionedList.builder(
      itemScrollController: widget.scrollController,
      itemPositionsListener: widget.textBookState.positionsListener,
      itemCount: widget.textBookState.content.length,
      itemBuilder: (context, index) => _buildLine(index, theme),
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
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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

            // Highlight search text
            String processedData = state.removeNikud
                ? utils.highLight(
                    utils.removeVolwels('$data\n'), state.searchText)
                : utils.highLight('$data\n', state.searchText);
            processedData = utils.formatTextWithParentheses(processedData);

            return HtmlWidget(
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
            );
          },
        ),
      ),
    );
  }
}
