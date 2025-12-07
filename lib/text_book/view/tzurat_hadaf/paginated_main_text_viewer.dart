import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/text_book/view/tzurat_hadaf/non_linear_text_widget.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';


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
    final availableWidth = context.size?.width;
    final availableHeight = context.size?.height;
    if (availableWidth == null ||
        availableWidth == 0 ||
        availableHeight == null ||
        availableHeight == 0) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textStyle = TextStyle(
      fontSize: widget.textBookState.fontSize,
      fontFamily: settingsState.fontFamily,
      height: 1.5,
      color: Colors.black,
    );
    final textDirection = Directionality.of(context);

    List<List<int>> pages = [];
    List<int> currentPage = [];
    double currentPageHeight = 0;

    for (int i = 0; i < widget.textBookState.content.length; i++) {
      String data = widget.textBookState.content[i];
      // Note: text manipulations should be consistent with _buildLine
      if (!settingsState.showTeamim) {
        data = utils.removeTeamim(data);
      }
      if (settingsState.replaceHolyNames) {
        data = utils.replaceHolyNames(data);
      }
      if (widget.textBookState.removeNikud) {
        data = utils.removeVolwels(data);
      }
      String strippedData = _stripHtmlTags(data);

      final painter = _NonLinearTextPainter(
        text: strippedData,
        style: textStyle,
        textDirection: textDirection,
      );
      final lineHeight = painter.calculateHeight(availableWidth);

      if (currentPageHeight + lineHeight > availableHeight &&
          currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = [];
        currentPageHeight = 0;
      }
      currentPage.add(i);
      currentPageHeight += lineHeight;
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
        return Column(
          children: pageLines.map((lineIndex) {
            return _buildLine(lineIndex);
          }).toList(),
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
                color: Colors.black, // Explicitly set color for diagnosis
              ),
            );
          },
        ),
      ),
    );
  }
}
