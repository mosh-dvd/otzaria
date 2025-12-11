import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

/// מסך תצוגת צורת הדף - מציג את הטקסט המרכזי עם מפרשים מסביב
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

  // ברירות מחדל - יחושבו לפי גודל המסך
  double? _leftWidth;
  double? _rightWidth;
  double? _bottomHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConfiguration();
    _loadSizes();
  }

  /// טעינת גדלים שמורים או חישוב ברירות מחדל
  void _loadSizes() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // טעינת גדלים שמורים
    _leftWidth = Settings.getValue<double>('page_shape_left_width') ??
        screenWidth * 0.30; // 30% מרוחב המסך
    _rightWidth = Settings.getValue<double>('page_shape_right_width') ??
        screenWidth * 0.30; // 30% מרוחב המסך
    _bottomHeight = Settings.getValue<double>('page_shape_bottom_height') ??
        screenHeight * 0.35; // 35% מגובה המסך

    setState(() {});
  }

  /// שמירת גדלים
  void _saveSizes() {
    if (_leftWidth != null) {
      Settings.setValue<double>('page_shape_left_width', _leftWidth!);
    }
    if (_rightWidth != null) {
      Settings.setValue<double>('page_shape_right_width', _rightWidth!);
    }
    if (_bottomHeight != null) {
      Settings.setValue<double>('page_shape_bottom_height', _bottomHeight!);
    }
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
      // אם אין הגדרה שמורה, השתמש בברירות מחדל
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
          body: Column(
            children: [
              // Main Content Row
              Expanded(
                child: Row(
                  children: [
                    // Left Commentary
                    if (_leftCommentator != null) ...[
                      SizedBox(
                        width: _leftWidth,
                        child: _CommentaryPane(
                          commentatorName: _leftCommentator!,
                          openBookCallback: widget.openBookCallback,
                        ),
                      ),
                      _ResizableDivider(
                        isVertical: true,
                        onDrag: (delta) {
                          setState(() {
                            _leftWidth = (_leftWidth! - delta).clamp(
                                100.0, MediaQuery.of(context).size.width * 0.5);
                          });
                        },
                        onDragEnd: _saveSizes,
                      ),
                    ],
                    // Main Text - שימוש ב-SimpleTextViewer!
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          children: [
                            SimpleTextViewer(
                              content: state.content,
                              fontSize: state.fontSize,
                              openBookCallback: widget.openBookCallback,
                              scrollController: state.scrollController,
                              positionsListener: state.positionsListener,
                              isMainText: true,
                              title: state.book.title,
                            ),
                            // Settings button
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
                                    final result = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) =>
                                          PageShapeSettingsDialog(
                                        availableCommentators:
                                            state.availableCommentators,
                                        bookTitle: state.book.title,
                                        currentLeft: _leftCommentator,
                                        currentRight: _rightCommentator,
                                        currentBottom: _bottomCommentator,
                                        currentBottomRight:
                                            _bottomRightCommentator,
                                      ),
                                    );
                                    if (result == true && mounted) {
                                      _loadConfiguration();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Right Commentary
                    if (_rightCommentator != null) ...[
                      _ResizableDivider(
                        isVertical: true,
                        onDrag: (delta) {
                          setState(() {
                            _rightWidth = (_rightWidth! + delta).clamp(
                                100.0, MediaQuery.of(context).size.width * 0.5);
                          });
                        },
                        onDragEnd: _saveSizes,
                      ),
                      SizedBox(
                        width: _rightWidth,
                        child: _CommentaryPane(
                          commentatorName: _rightCommentator!,
                          openBookCallback: widget.openBookCallback,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Bottom Commentary
              if (_bottomCommentator != null ||
                  _bottomRightCommentator != null) ...[
                _ResizableDivider(
                  isVertical: false,
                  onDrag: (delta) {
                    setState(() {
                      // תיקון הבאג: משיכה למעלה (delta שלילי) צריכה להקטין את הגובה
                      _bottomHeight = (_bottomHeight! - delta).clamp(
                          100.0, MediaQuery.of(context).size.height * 0.6);
                    });
                  },
                  onDragEnd: _saveSizes,
                ),
                SizedBox(
                  height: _bottomHeight,
                  child: _bottomRightCommentator != null
                      ? Row(
                          children: [
                            if (_bottomCommentator != null) ...[
                              Expanded(
                                child: _CommentaryPane(
                                  commentatorName: _bottomCommentator!,
                                  openBookCallback: widget.openBookCallback,
                                ),
                              ),
                              _ResizableDivider(
                                isVertical: true,
                                onDrag: (delta) {},
                              ),
                            ],
                            Expanded(
                              child: _CommentaryPane(
                                commentatorName: _bottomRightCommentator!,
                                openBookCallback: widget.openBookCallback,
                              ),
                            ),
                          ],
                        )
                      : _CommentaryPane(
                          commentatorName: _bottomCommentator!,
                          openBookCallback: widget.openBookCallback,
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// חלונית מפרש - טוענת ומציגה את הספר של המפרש
class _CommentaryPane extends StatefulWidget {
  final String commentatorName;
  final Function(OpenedTab) openBookCallback;

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
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
  int? _lastSyncedIndex; // האינדקס האחרון שסונכרן
  StreamSubscription<TextBookState>? _blocSubscription;

  @override
  void initState() {
    super.initState();
    _loadCommentary();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // הגדרת המאזין רק פעם אחת
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

  /// הגדרת מאזין לשינויים ב-Bloc
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

      // טעינת הקישורים הרלוונטיים למפרש זה
      final state = context.read<TextBookBloc>().state;
      if (state is TextBookLoaded) {
        _relevantLinks = state.links.where((link) {
          final linkTitle = utils.getTitleFromPath(link.path2);
          return linkTitle == widget.commentatorName;
        }).toList();
      }

      if (mounted) {
        setState(() {
          _content = lines;
          _isLoading = false;
        });

        // סנכרון ראשוני
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

  /// סנכרון המפרש עם הטקסט הראשי
  void _syncWithMainText(TextBookLoaded state) {
    // אם אין תוכן או אין קישורים - אין מה לסנכרן
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      return;
    }

    // קביעת האינדקס הנוכחי בטקסט הראשי
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else if (state.visibleIndices.isNotEmpty) {
      currentMainIndex = state.visibleIndices.first;
    } else {
      return; // אין מידע על מיקום נוכחי
    }

    // חישוב האינדקס הלוגי (עם טיפול בכותרות)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // מציאת הקישור הטוב ביותר
    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // חישוב האינדקס היעד במפרש
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(bestLink);

    // אם אין קישור או שכבר סונכרנו לאינדקס הזה - לא צריך לגלול
    if (targetIndex == null || targetIndex == _lastSyncedIndex) {
      return;
    }

    // גלילה למיקום הנכון במפרש
    if (targetIndex >= 0 && targetIndex < _content!.length) {
      try {
        _scrollController.scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1, // קצת מתחת לראש החלון
        );
        _lastSyncedIndex = targetIndex;
      } catch (e) {
        debugPrint('Error scrolling commentary: $e');
      }
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
            'לא ניתן לטעון את ${widget.commentatorName}',
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
            return SimpleTextViewer(
              content: _content!,
              fontSize: state.fontSize * 0.8, // מפרשים בגופן קטן יותר
              fontFamily: settingsState.commentatorsFontFamily,
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              title: widget.commentatorName,
              bookTitle: widget.commentatorName, // לפתיחה בטאב נפרד
            );
          },
        );
      },
    );
  }
}

class _ResizableDivider extends StatefulWidget {
  final bool isVertical;
  final Function(double) onDrag;
  final VoidCallback? onDragEnd;

  const _ResizableDivider({
    required this.isVertical,
    required this.onDrag,
    this.onDragEnd,
  });

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isVertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanUpdate: (details) {
          widget.onDrag(
            widget.isVertical ? details.delta.dx : details.delta.dy,
          );
        },
        onPanEnd: (_) {
          // שמירת הגדלים כשמסיימים את הגרירה
          widget.onDragEnd?.call();
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
