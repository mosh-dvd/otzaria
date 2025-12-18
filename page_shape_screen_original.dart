import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'dart:async';

/// ╫º╫ס╫ץ╫ó╫ש╫¥ ╫£╫ק╫ש╫⌐╫ץ╫ס ╫¿╫ץ╫ק╫ס ╫ק╫£╫ץ╫á╫ש╫ץ╫¬ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥
const double _kCommentaryPaneWidthFactor = 0.17;
/// ╫¿╫ץ╫ק╫ס ╫פ╫¢╫ץ╫¬╫¿╫¬ ╫פ╫נ╫á╫¢╫ש╫¬ + ╫¿╫ץ╫ץ╫ק╫ש╫¥ (20 ╫£╫¢╫ץ╫¬╫¿╫¬ + 4 ╫£╫¿╫ץ╫ץ╫ק + 6 ╫£╫₧╫ñ╫¿╫ש╫ף)
const double _kCommentaryLabelAndSpacingWidth = 30.0;

/// ╫₧╫í╫ת ╫¬╫ª╫ץ╫ע╫¬ ╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú - ╫₧╫ª╫ש╫ע ╫נ╫¬ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש ╫ó╫¥ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫í╫ס╫ש╫ס
class PageShapeScreen extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;

  const PageShapeScreen({super.key, required this.openBookCallback});

  @override
  State<PageShapeScreen> createState() => _PageShapeScreenState();
}

class _PageShapeScreenState extends State<PageShapeScreen> {
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConfiguration();
  }

  void _loadConfiguration() {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final config = PageShapeSettingsManager.loadConfiguration(state.book.title);

    if (config != null) {
      if (mounted) {
        setState(() {
          _leftCommentator = config['left'];
          _rightCommentator = config['right'];
          _bottomCommentator = config['bottom'];
          _bottomRightCommentator = config['bottomRight'];
        });
      }
    } else {
      // ╫נ╫¥ ╫נ╫ש╫ƒ ╫פ╫ע╫ף╫¿╫פ ╫⌐╫₧╫ץ╫¿╫פ, ╫פ╫⌐╫¬╫₧╫⌐ ╫ס╫ס╫¿╫ש╫¿╫ץ╫¬ ╫₧╫ק╫ף╫£
      final defaults = DefaultCommentators.getDefaults(state.book);
      if (mounted) {
        setState(() {
          _leftCommentator = defaults['left'];
          _rightCommentator = defaults['right'];
          _bottomCommentator = defaults['bottom'];
          _bottomRightCommentator = defaults['bottomRight'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  // Main Content Row - ╫₧╫¬╫¿╫ק╫ס ╫£╫ñ╫ש ╫פ╫⌐╫ר╫ק ╫פ╫ñ╫á╫ץ╫ש
                  Expanded(
                    child: Row(
                      children: [
                        // Left Commentary with label (label on outer edge - first in RTL)
                        if (_leftCommentator != null) ...[
                          SizedBox(
                            width: 20,
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  _leftCommentator!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * _kCommentaryPaneWidthFactor,
                            child: _CommentaryPane(
                              commentatorName: _leftCommentator!,
                              openBookCallback: widget.openBookCallback,
                            ),
                          ),
                          const _ResizableDivider(
                            isVertical: true,
                          ),
                        ],
                        // Main Text - ╫₧╫¬╫¿╫ק╫ס ╫£╫ñ╫ש ╫פ╫⌐╫ר╫ק ╫פ╫ñ╫á╫ץ╫ש
                        Expanded(
                          child: SimpleTextViewer(
                            content: state.content,
                            fontSize: state.fontSize,
                            openBookCallback: widget.openBookCallback,
                            scrollController: state.scrollController,
                            positionsListener: state.positionsListener,
                            isMainText: true,
                          ),
                        ),
                    // Right Commentary with label (label on outer edge - last in RTL)
                    if (_rightCommentator != null) ...[
                      const _ResizableDivider(
                        isVertical: true,
                      ),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * _kCommentaryPaneWidthFactor,
                        child: _CommentaryPane(
                          commentatorName: _rightCommentator!,
                          openBookCallback: widget.openBookCallback,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 20,
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              _rightCommentator!,
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Bottom Commentary - ╫ע╫ץ╫ס╫פ ╫º╫ס╫ץ╫ó ╫⌐╫£ 27% ╫₧╫פ╫₧╫í╫ת
              if (_bottomCommentator != null ||
                  _bottomRightCommentator != null) ...[
                // ╫º╫ץ╫ץ╫ש╫¥ ╫₧╫¬╫ק╫¬ ╫£╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫פ╫ó╫£╫ש╫ץ╫á╫ש╫¥ - ╫ס╫נ╫₧╫ª╫ó ╫פ╫¿╫ץ╫ץ╫ק
                SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      // ╫º╫ץ ╫₧╫¬╫ק╫¬ ╫£╫₧╫ñ╫¿╫⌐ ╫פ╫⌐╫₧╫נ╫£╫ש
                      if (_leftCommentator != null)
                        SizedBox(
                          width: MediaQuery.of(context).size.width * _kCommentaryPaneWidthFactor + _kCommentaryLabelAndSpacingWidth,
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Container(
                                height: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      // ╫º╫ץ ╫₧╫¬╫ק╫¬ ╫£╫₧╫ñ╫¿╫⌐ ╫פ╫ש╫₧╫á╫ש
                      if (_rightCommentator != null)
                        SizedBox(
                          width: MediaQuery.of(context).size.width * _kCommentaryPaneWidthFactor + _kCommentaryLabelAndSpacingWidth,
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Container(
                                height: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.27,
                  child: Column(
                    children: [
                      Expanded(
                        child: _bottomRightCommentator != null
                            ? Row(
                                children: [
                                  if (_bottomCommentator != null) ...[
                                    SizedBox(
                                      width: 20,
                                      child: Center(
                                        child: RotatedBox(
                                          quarterTurns: 1,
                                          child: Text(
                                            _bottomCommentator!,
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: _CommentaryPane(
                                        commentatorName: _bottomCommentator!,
                                        openBookCallback: widget.openBookCallback,
                                        isBottom: true,
                                      ),
                                    ),
                                    const _ResizableDivider(
                                      isVertical: true,
                                    ),
                                  ],
                                  Expanded(
                                    child: _CommentaryPane(
                                      commentatorName: _bottomRightCommentator!,
                                      openBookCallback: widget.openBookCallback,
                                      isBottom: true,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 20,
                                    child: Center(
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: Text(
                                          _bottomRightCommentator!,
                                          style: const TextStyle(
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    child: Center(
                                      child: RotatedBox(
                                        quarterTurns: 1,
                                        child: Text(
                                          _bottomCommentator!,
                                          style: const TextStyle(
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _CommentaryPane(
                                      commentatorName: _bottomCommentator!,
                                      openBookCallback: widget.openBookCallback,
                                      isBottom: true,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          // Settings button - ╫ס╫ñ╫ש╫á╫פ ╫פ╫ש╫₧╫á╫ש╫¬ ╫פ╫ó╫£╫ש╫ץ╫á╫פ ╫⌐╫£ ╫¢╫£ ╫פ╫₧╫í╫ת
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.settings, size: 18),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final hadChanges = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => PageShapeSettingsDialog(
                      availableCommentators: state.availableCommentators,
                      bookTitle: state.book.title,
                      currentLeft: _leftCommentator,
                      currentRight: _rightCommentator,
                      currentBottom: _bottomCommentator,
                      currentBottomRight: _bottomRightCommentator,
                    ),
                  );
                  // ╫ר╫ó╫ש╫á╫פ ╫₧╫ק╫ף╫⌐ ╫נ╫¥ ╫פ╫ש╫ץ ╫⌐╫ש╫á╫ץ╫ש╫ש╫¥
                  if (hadChanges == true && mounted) {
                    _loadConfiguration();
                  }
                },
              ),
            ),
          ),
        ],
          ),
        );
      },
    );
  }
}

/// ╫ק╫£╫ץ╫á╫ש╫¬ ╫₧╫ñ╫¿╫⌐ - ╫ר╫ץ╫ó╫á╫¬ ╫ץ╫₧╫ª╫ש╫ע╫פ ╫נ╫¬ ╫פ╫í╫ñ╫¿ ╫⌐╫£ ╫פ╫₧╫ñ╫¿╫⌐
class _CommentaryPane extends StatefulWidget {
  final String commentatorName;
  final Function(OpenedTab) openBookCallback;
  final bool isBottom; // ╫פ╫נ╫¥ ╫צ╫פ ╫₧╫ñ╫¿╫⌐ ╫¬╫ק╫¬╫ץ╫ƒ

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
    this.isBottom = false,
  });

  @override
  State<_CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<_CommentaryPane> {
  List<String>? _content;
  bool _isLoading = true;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  List<Link> _relevantLinks = [];
  int? _lastSyncedIndex; // ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫נ╫ק╫¿╫ץ╫ƒ ╫⌐╫í╫ץ╫á╫¢╫¿╫ƒ
  StreamSubscription<TextBookState>? _blocSubscription;

  @override
  void initState() {
    super.initState();
    _loadCommentary();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ╫פ╫ע╫ף╫¿╫¬ ╫פ╫₧╫נ╫צ╫ש╫ƒ ╫¿╫º ╫ñ╫ó╫¥ ╫נ╫ק╫¬
    if (_blocSubscription == null) {
      _setupBlocListener();
    }
  }

  @override
  void didUpdateWidget(_CommentaryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentatorName != widget.commentatorName) {
      _loadCommentary();
    }
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// ╫פ╫ע╫ף╫¿╫¬ ╫₧╫נ╫צ╫ש╫ƒ ╫£╫⌐╫ש╫á╫ץ╫ש╫ש╫¥ ╫ס-Bloc
  void _setupBlocListener() {
    _blocSubscription = context.read<TextBookBloc>().stream.listen((state) {
      if (state is TextBookLoaded && mounted) {
        _syncWithMainText(state);
      }
    });
  }

  Future<void> _loadCommentary() async {
    setState(() => _isLoading = true);

    try {
      final book = TextBook(title: widget.commentatorName);
      final bookContent = await book.text;
      final lines = bookContent.split('\n');

      if (!mounted) return;

      // ╫ר╫ó╫ש╫á╫¬ ╫פ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ ╫פ╫¿╫£╫ץ╫ץ╫á╫ר╫ש╫ש╫¥ ╫£╫₧╫ñ╫¿╫⌐ ╫צ╫פ
      final state = context.read<TextBookBloc>().state;
      if (state is TextBookLoaded) {
        // ╫í╫ש╫á╫ץ╫ƒ ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ ╫£╫ñ╫ש ╫⌐╫¥ ╫פ╫₧╫ñ╫¿╫⌐ ╫ץ╫£╫ñ╫ש ╫í╫ץ╫ע ╫פ╫º╫ש╫⌐╫ץ╫¿ (commentary/targum)
        _relevantLinks = state.links.where((link) {
          final linkTitle = utils.getTitleFromPath(link.path2);
          return linkTitle == widget.commentatorName &&
              (link.connectionType == 'commentary' ||
                  link.connectionType == 'targum');
        }).toList();
      }

      if (mounted) {
        setState(() {
          _content = lines;
          _isLoading = false;
          _lastSyncedIndex = null; // ╫נ╫ש╫ñ╫ץ╫í ╫£╫í╫á╫¢╫¿╫ץ╫ƒ ╫¿╫נ╫⌐╫ץ╫á╫ש
        });

        // ╫í╫á╫¢╫¿╫ץ╫ƒ ╫¿╫נ╫⌐╫ץ╫á╫ש
        if (state is TextBookLoaded) {
          _syncWithMainText(state);
        }
      }
    } catch (e) {
      debugPrint('Error loading commentary ${widget.commentatorName}: $e');
      if (mounted) {
        setState(() {
          _content = null;
          _isLoading = false;
        });
      }
    }
  }

  /// ╫í╫á╫¢╫¿╫ץ╫ƒ ╫פ╫₧╫ñ╫¿╫⌐ ╫ó╫¥ ╫פ╫ר╫º╫í╫ר ╫פ╫¿╫נ╫⌐╫ש
  void _syncWithMainText(TextBookLoaded state) {
    // ╫נ╫¥ ╫נ╫ש╫ƒ ╫¬╫ץ╫¢╫ƒ ╫נ╫ץ ╫נ╫ש╫ƒ ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ - ╫נ╫ש╫ƒ ╫₧╫פ ╫£╫í╫á╫¢╫¿╫ƒ
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      return;
    }

    // ╫º╫ס╫ש╫ó╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫ס╫ר╫º╫í╫ר ╫פ╫¿╫נ╫⌐╫ש
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else if (state.visibleIndices.isNotEmpty) {
      currentMainIndex = state.visibleIndices.first;
    } else {
      return; // ╫נ╫ש╫ƒ ╫₧╫ש╫ף╫ó ╫ó╫£ ╫₧╫ש╫º╫ץ╫¥ ╫á╫ץ╫¢╫ק╫ש
    }

    // ╫ק╫ש╫⌐╫ץ╫ס ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫£╫ץ╫ע╫ש (╫ó╫¥ ╫ר╫ש╫ñ╫ץ╫£ ╫ס╫¢╫ץ╫¬╫¿╫ץ╫¬)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // ╫₧╫ª╫ש╫נ╫¬ ╫פ╫º╫ש╫⌐╫ץ╫¿ ╫פ╫ר╫ץ╫ס ╫ס╫ש╫ץ╫¬╫¿
    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // ╫ק╫ש╫⌐╫ץ╫ס ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫ש╫ó╫ף ╫ס╫₧╫ñ╫¿╫⌐
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(bestLink);

    // ╫נ╫¥ ╫נ╫ש╫ƒ ╫º╫ש╫⌐╫ץ╫¿ - ╫£╫נ ╫₧╫צ╫ש╫צ╫ש╫¥ ╫נ╫¬ ╫פ╫₧╫ñ╫¿╫⌐
    if (targetIndex == null) {
      return;
    }

    // ╫נ╫¥ ╫¢╫ס╫¿ ╫í╫ץ╫á╫¢╫¿╫á╫ץ ╫£╫נ╫ש╫á╫ף╫º╫í ╫פ╫צ╫פ - ╫£╫נ ╫ª╫¿╫ש╫ת ╫£╫ע╫£╫ץ╫£ ╫⌐╫ץ╫ס
    if (targetIndex == _lastSyncedIndex) {
      return;
    }

    // ╫ע╫£╫ש╫£╫פ ╫£╫₧╫ש╫º╫ץ╫¥ ╫פ╫á╫¢╫ץ╫ƒ ╫ס╫₧╫ñ╫¿╫⌐
    if (targetIndex >= 0 && targetIndex < _content!.length && _scrollController.isAttached) {
      _scrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0, // ╫ס╫¿╫נ╫⌐ ╫פ╫ק╫£╫ץ╫ƒ
      );
      _lastSyncedIndex = targetIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_content == null || _content!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            '╫£╫נ ╫á╫ש╫¬╫ƒ ╫£╫ר╫ó╫ץ╫ƒ ╫נ╫¬ ${widget.commentatorName}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const SizedBox();
        }

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫¬╫ק╫¬╫ץ╫á╫ש╫¥ ╫₧╫⌐╫¬╫₧╫⌐╫ש╫¥ ╫ס╫ע╫ץ╫ñ╫ƒ ╫₧╫פ╫פ╫ע╫ף╫¿╫ץ╫¬, ╫ó╫£╫ש╫ץ╫á╫ש╫¥ ╫ס╫ע╫ץ╫ñ╫ƒ ╫פ╫¿╫ע╫ש╫£
            final bottomFont = Settings.getValue<String>('page_shape_bottom_font') ?? AppFonts.defaultFont;
            final fontFamily = widget.isBottom
                ? bottomFont
                : settingsState.commentatorsFontFamily;
            return SimpleTextViewer(
              content: _content!,
              fontSize: 16, // ╫ע╫ץ╫ñ╫ƒ ╫º╫ס╫ץ╫ó ╫£╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ס╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú
              fontFamily: fontFamily,
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              bookTitle: widget.commentatorName, // ╫£╫ñ╫¬╫ש╫ק╫פ ╫ס╫ר╫נ╫ס ╫á╫ñ╫¿╫ף
            );
          },
        );
      },
    );
  }
}

class _ResizableDivider extends StatefulWidget {
  final bool isVertical;
  /// ╫נ╫¥ null, ╫פ╫₧╫ñ╫¿╫ש╫ף ╫ש╫פ╫ש╫פ ╫¿╫º ╫ץ╫ש╫צ╫ץ╫נ╫£╫ש ╫£╫£╫נ ╫נ╫ñ╫⌐╫¿╫ץ╫¬ ╫ע╫¿╫ש╫¿╫פ
  final Function(double)? onDrag;

  const _ResizableDivider({
    required this.isVertical,
    this.onDrag,
  });

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // ╫נ╫¥ ╫נ╫ש╫ƒ onDrag, ╫₧╫ª╫ש╫ע╫ש╫¥ ╫₧╫ñ╫¿╫ש╫ף ╫ñ╫⌐╫ץ╫ר ╫£╫£╫נ ╫נ╫ש╫á╫ר╫¿╫נ╫º╫ª╫ש╫פ
    if (widget.onDrag == null) {
      return Container(
        width: widget.isVertical ? 8 : null,
        height: widget.isVertical ? null : 8,
        color: Colors.transparent,
      );
    }

    return MouseRegion(
      cursor: widget.isVertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanUpdate: (details) {
          widget.onDrag!(
            widget.isVertical ? details.delta.dx : details.delta.dy,
          );
        },
        child: Container(
          width: widget.isVertical ? 8 : null,
          height: widget.isVertical ? null : 8,
          color: _isHovered
              ? Colors.grey.withValues(alpha: 0.3)
              : Colors.transparent,
          child: _isHovered
              ? Center(
                  child: Container(
                    width: widget.isVertical ? 2 : null,
                    height: widget.isVertical ? null : 2,
                    color: Colors.grey,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
