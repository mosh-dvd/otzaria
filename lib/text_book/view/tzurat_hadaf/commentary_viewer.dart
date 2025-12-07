import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

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
  final Map<int, String> _contentCache = {};
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchCommentaryWindow();
  }

  @override
  void didUpdateWidget(CommentaryViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentatorName != widget.commentatorName) {
      _contentCache.clear();
      _fetchCommentaryWindow();
    } else if (oldWidget.selectedIndex != widget.selectedIndex) {
      // Debounce fetching to avoid rapid firing while scrolling
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), () {
        _fetchCommentaryWindow();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchCommentaryWindow() async {
    if (widget.commentatorName == null || widget.selectedIndex == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final int centerIndex = widget.selectedIndex!;
    final int windowSize = 5;
    final int start = (centerIndex - windowSize).clamp(0, widget.textBookState.content.length - 1);
    final int end = (centerIndex + windowSize).clamp(0, widget.textBookState.content.length - 1);

    final repo = context.read<TextBookBloc>().repository;

    for (int i = start; i <= end; i++) {
      if (_contentCache.containsKey(i)) {
        continue; // Already cached
      }

      try {
        final link = widget.textBookState.links.firstWhere(
          (link) =>
              link.index1 == i + 1 &&
              utils.getTitleFromPath(link.path2) == widget.commentatorName,
        );

        final book = TextBook(title: utils.getTitleFromPath(link.path2));
        final commentaryContent = await repo.getBookContent(book);
        final lines = commentaryContent.split('\n');
        
        if (link.index2 > 0 && link.index2 <= lines.length) {
          _contentCache[i] = lines[link.index2 - 1];
        } else {
          _contentCache[i] = 'התוכן לא נמצא';
        }
      } catch (e) {
        // Cache that no commentary was found for this index
        _contentCache[i] = ''; 
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _contentCache[widget.selectedIndex];

    if (_isLoading && content == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (content != null && content.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          content,
          style: TextStyle(fontSize: widget.textBookState.fontSize * 0.8),
          textDirection: TextDirection.rtl,
        ),
      );
    }

    return Center(
      child: Text(
        widget.commentatorName ?? 'בחר מפרש',
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }
}
