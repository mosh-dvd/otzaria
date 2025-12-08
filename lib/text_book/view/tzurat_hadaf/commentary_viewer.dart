import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
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
  List<Link> _relevantLinks = [];

  @override
  void initState() {
    super.initState();
    _loadLinks();
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
    });
    
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (widget.selectedIndex == null || _relevantLinks.isEmpty) return;

    // Find first link that matches the selected index
    final targetIndex = _relevantLinks.indexWhere(
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

    return ScrollablePositionedList.builder(
      itemScrollController: _scrollController,
      padding: const EdgeInsets.all(8.0),
      itemCount: _relevantLinks.length,
      itemBuilder: (context, index) {
        final link = _relevantLinks[index];
        final isSelected = widget.selectedIndex != null && 
                          link.index1 - 1 == widget.selectedIndex;
        
        return FutureBuilder<String>(
          future: link.content,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
            }

            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String displayText = snapshot.data!;
                if (settingsState.replaceHolyNames) {
                  displayText = utils.replaceHolyNames(displayText);
                }
                if (widget.textBookState.removeNikud) {
                  displayText = utils.removeVolwels(displayText);
                }
                
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 2.0),
                  padding: const EdgeInsets.all(8.0),
                  decoration: isSelected ? BoxDecoration(
                    color: Colors.yellow.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4),
                  ) : null,
                  child: HtmlWidget(
                    '<div style="text-align: justify; direction: rtl;">$displayText</div>',
                    textStyle: TextStyle(
                      fontSize: widget.textBookState.fontSize * 0.8,
                      fontFamily: settingsState.commentatorsFontFamily,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
