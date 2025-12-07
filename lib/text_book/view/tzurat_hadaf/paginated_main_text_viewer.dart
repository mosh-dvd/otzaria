import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/text_book/view/tzurat_hadaf/non_linear_text_widget.dart';
import 'package:otzaria/utils/text_with_inline_links.dart';
import 'package:otzaria/tabs/models/tab.dart';


class PaginatedMainTextViewer extends StatefulWidget {
  final TextBookLoaded textBookState;
  final Function(OpenedTab) openBookCallback;

  const PaginatedMainTextViewer({
    super.key,
    required this.textBookState,
    required this.openBookCallback,
  });

  @override
  _PaginatedMainTextViewerState createState() =>
      _PaginatedMainTextViewerState();
}

class _PaginatedMainTextViewerState extends State<PaginatedMainTextViewer> {
  final PageController _pageController = PageController();
  List<List<int>> _pages = [];

  @override
  void initState() {
    super.initState();
    // Trigger page calculation after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculatePages();
    });
  }

  @override
  void didUpdateWidget(PaginatedMainTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textBookState.content.hashCode !=
            widget.textBookState.content.hashCode ||
        oldWidget.textBookState.fontSize != widget.textBookState.fontSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculatePages();
      });
    }
  }

  void _calculatePages() {
    final availableHeight = context.size?.height;
    if (availableHeight == null || availableHeight == 0) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textStyle = TextStyle(
      fontSize: widget.textBookState.fontSize,
      fontFamily: settingsState.fontFamily,
      height: 1.5,
    );

    // Estimate line height
    final singleLineHeight =
        (textStyle.fontSize! * (textStyle.height ?? 1.5)) * 1.2;

    List<List<int>> pages = [];
    List<int> currentPage = [];
    double currentPageHeight = 0;

    for (int i = 0; i < widget.textBookState.content.length; i++) {
      // a simple heuristic for line height. A more accurate measurement is needed
      final line = widget.textBookState.content[i];
      final estimatedLineHeight = (line.length / 50 + 1) * singleLineHeight;

      if (currentPageHeight + estimatedLineHeight > availableHeight &&
          currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = [];
        currentPageHeight = 0;
      }
      currentPage.add(i);
      currentPageHeight += estimatedLineHeight;
    }
    if (currentPage.isNotEmpty) {
      pages.add(currentPage);
    }

    setState(() {
      _pages = pages;
    });
  }

  String _stripHtmlTags(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      itemBuilder: (context, pageIndex) {
        final pageLines = _pages[pageIndex];
        return ListView.builder(
          itemCount: pageLines.length,
          itemBuilder: (context, lineIndexInPage) {
            final lineIndex = pageLines[lineIndexInPage];
            return _buildLine(lineIndex);
          },
        );
      },
    );
  }

  Widget _buildLine(int index) {
    final state = widget.textBookState;
    final isSelected = state.selectedIndex == index;
    final isHighlighted = state.highlightedLine == index;

    final theme = Theme.of(context);
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
            String processedData = utils.highLight(data, state.searchText);
            processedData = utils.formatTextWithParentheses(processedData);

            return NonLinearText(
              text: _stripHtmlTags(processedData),
              style: TextStyle(
                fontSize: state.fontSize,
                fontFamily: settingsState.fontFamily,
                height: 1.5,
              ),
            );
          },
        ),
      ),
    );
  }
}
