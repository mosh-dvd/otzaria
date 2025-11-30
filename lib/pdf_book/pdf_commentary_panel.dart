import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/pdf_book/pdf_commentators_selector.dart';
import 'package:otzaria/pdf_book/pdf_commentary_content.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:pdfrx/pdfrx.dart';

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
class CommentaryGroup {
  final String bookTitle;
  final List<Link> links;

  CommentaryGroup({required this.bookTitle, required this.links});
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    final title = utils.getTitleFromPath(link.path2);

    if (currentTitle == null || currentTitle != title) {
      // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      // אותו ספר - מוסיף לקבוצה הנוכחית
      currentGroup.add(link);
    }
  }

  // מוסיף את הקבוצה האחרונה
  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}

/// Widget שמציג מפרשים וקישורים עבור PDF
class PdfCommentaryPanel extends StatefulWidget {
  final PdfBookTab tab;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final VoidCallback? onClose;
  final int? initialTabIndex;

  const PdfCommentaryPanel({
    super.key,
    required this.tab,
    required this.openBookCallback,
    required this.fontSize,
    this.onClose,
    this.initialTabIndex,
  });

  @override
  State<PdfCommentaryPanel> createState() => _PdfCommentaryPanelState();
}

class _PdfCommentaryPanelState extends State<PdfCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showFilterTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3, // מפרשים, קישורים, הערות
      vsync: this,
      initialIndex: widget.initialTabIndex ?? 0,
    );
  }

  @override
  void didUpdateWidget(PdfCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם initialTabIndex השתנה, מעדכן את הטאב
    if (oldWidget.initialTabIndex != widget.initialTabIndex &&
        widget.initialTabIndex != null) {
      _tabController.animateTo(widget.initialTabIndex!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // שורת הכרטיסיות
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // כפתור סינון מפרשים
              IconButton(
                icon: Icon(
                  FluentIcons.apps_list_24_regular,
                  color: _showFilterTab
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                ),
                tooltip: 'בחירת מפרשים',
                onPressed: () {
                  setState(() {
                    _showFilterTab = !_showFilterTab;
                  });
                },
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // חישוב גודל הטקסט לפי רוחב זמין
                    final availableWidth = constraints.maxWidth;
                    final fontSize = availableWidth < 200
                        ? 11.0
                        : (availableWidth < 300 ? 13.0 : 14.0);

                    return TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.symmetric(
                          horizontal: availableWidth < 250 ? 8 : 16),
                      tabs: [
                        Tab(
                          child: Text(
                            'מפרשים',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'קישורים',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'הערות אישיות',
                            style: TextStyle(fontSize: fontSize),
                          ),
                        ),
                      ],
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      dividerColor: Colors.transparent,
                      onTap: (index) {
                        // אם לוחצים על טאב מפרשים (0) ואנחנו בכפתור סינון, סוגרים אותו
                        if (index == 0 && _showFilterTab) {
                          setState(() {
                            _showFilterTab = false;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
              // לחצן סגירה
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                margin: const EdgeInsets.all(8.0),
                child: IconButton(
                  iconSize: 18,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: widget.onClose ?? () {},
                ),
              ),
            ],
          ),
        ),
        // תוכן הכרטיסיות
        Expanded(
          child: _showFilterTab
              ? _buildCommentatorsFilter()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCommentariesView(),
                    _buildLinksView(),
                    _buildNotesView(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCommentatorsFilter() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: PdfCommentatorsSelector(
        tab: widget.tab,
        onChanged: () {
          setState(() {
            // עדכון התצוגה כשמשנים מפרשים
          });
        },
      ),
    );
  }

  Widget _buildCommentariesView() {
    debugPrint('=== PDF Commentary Debug ===');
    debugPrint('currentTextLineNumber: ${widget.tab.currentTextLineNumber}');
    debugPrint('total links: ${widget.tab.links.length}');
    debugPrint('activeCommentators: ${widget.tab.activeCommentators}');

    // בדיקה אם יש מספר שורה נוכחי
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'לא נמצאו מפרשים לדף זה',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Debug: currentTextLineNumber is null',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.7,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // סינון מפרשים לפי טווח השורות של העמוד הנוכחי
    final currentLine = widget.tab.currentTextLineNumber!;

    // מציאת טווח השורות של העמוד הנוכחי
    int startLine = currentLine + 1;
    int endLine = startLine;

    if (widget.tab.pdfHeadings != null) {
      final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
      final currentIndex =
          sortedHeadings.indexWhere((e) => e.value == currentLine);

      if (currentIndex != -1 && currentIndex < sortedHeadings.length - 1) {
        endLine = sortedHeadings[currentIndex + 1].value - 1;
      } else {
        // אם זה העמוד האחרון, נניח טווח של 50 שורות
        endLine = startLine + 50;
      }
    } else {
      // אם אין headings, נניח טווח של 50 שורות
      endLine = startLine + 50;
    }

    debugPrint('Looking for links in range: $startLine-$endLine');
    debugPrint('Active commentators: ${widget.tab.activeCommentators.length}');

    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 >= startLine &&
            link.index1 <= endLine &&
            (link.connectionType == "commentary" ||
                link.connectionType == "targum") &&
            widget.tab.activeCommentators
                .contains(utils.getTitleFromPath(link.path2)))
        .toList();

    debugPrint('Found ${relevantLinks.length} relevant links');

    if (relevantLinks.isEmpty) {
      // בדיקה מפורטת למה אין קישורים
      final allLinksInRange = widget.tab.links
          .where((link) => link.index1 >= startLine && link.index1 <= endLine)
          .toList();

      final hasCommentaryLinks = allLinksInRange.any((link) =>
          link.connectionType == "commentary" ||
          link.connectionType == "targum");

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                hasCommentaryLinks
                    ? 'לא נבחרו מפרשים להצגה'
                    : 'לא נמצאו מפרשים לקטע הנבחר',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasCommentaryLinks) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showFilterTab = true;
                    });
                  },
                  icon: const Icon(FluentIcons.apps_list_24_regular),
                  label: const Text('בחר מפרשים'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // קיבוץ המפרשים לפי ספר
    final groups = _groupConsecutiveLinks(relevantLinks);

    // מיון הקבוצות לפי סדר הדורות
    return FutureBuilder<List<CommentaryGroup>>(
      future: _sortGroupsByEra(groups),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sortedGroups = snapshot.data!;

        return ListView.builder(
          itemCount: sortedGroups.length,
          itemBuilder: (context, index) {
            final group = sortedGroups[index];
            return _buildCommentaryGroupTile(group);
          },
        );
      },
    );
  }

  /// ממיין קבוצות מפרשים לפי סדר הדורות
  Future<List<CommentaryGroup>> _sortGroupsByEra(
      List<CommentaryGroup> groups) async {
    // יצירת מפה של כל שם ספר לדור שלו
    final Map<String, int> eraOrder = {};

    for (final group in groups) {
      final title = group.bookTitle;

      // בדיקה לאיזה דור שייך הספר
      if (await utils.hasTopic(title, 'תורה שבכתב')) {
        eraOrder[title] = 0;
      } else if (await utils.hasTopic(title, 'חז"ל')) {
        eraOrder[title] = 1;
      } else if (await utils.hasTopic(title, 'ראשונים')) {
        eraOrder[title] = 2;
      } else if (await utils.hasTopic(title, 'אחרונים')) {
        eraOrder[title] = 3;
      } else if (await utils.hasTopic(title, 'מחברי זמננו')) {
        eraOrder[title] = 4;
      } else {
        eraOrder[title] = 5; // שאר מפרשים
      }
    }

    // מיון הקבוצות לפי הדור
    final sortedGroups = List<CommentaryGroup>.from(groups);
    sortedGroups.sort((a, b) {
      final orderA = eraOrder[a.bookTitle] ?? 5;
      final orderB = eraOrder[b.bookTitle] ?? 5;

      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // אם שני הספרים באותו דור, ממיינים לפי שם
      return a.bookTitle.compareTo(b.bookTitle);
    });

    return sortedGroups;
  }

  Widget _buildCommentaryGroupTile(CommentaryGroup group) {
    return ExpansionTile(
      key: PageStorageKey(
          '${group.bookTitle}_${widget.tab.currentTextLineNumber}'),
      maintainState: true,
      initiallyExpanded: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        group.bookTitle,
        style: TextStyle(
          fontSize: widget.fontSize * 0.85,
          fontWeight: FontWeight.bold,
          fontFamily: 'FrankRuhlCLM',
        ),
      ),
      children: group.links.map((link) {
        return ListTile(
          contentPadding: const EdgeInsets.only(right: 32.0, left: 16.0),
          title: Text(
            link.heRef,
            style: TextStyle(
              fontSize: widget.fontSize * 0.75,
              fontWeight: FontWeight.normal,
              fontFamily: 'FrankRuhlCLM',
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
          subtitle: PdfCommentaryContent(
            key: ValueKey(
                '${link.path2}_${link.index2}_${widget.tab.currentTextLineNumber}'),
            link: link,
            fontSize: widget.fontSize,
            openBookCallback: widget.openBookCallback,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLinksView() {
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    // סינון קישורים (לא מפרשים) לפי טווח השורות של העמוד
    final currentLine = widget.tab.currentTextLineNumber!;

    // מציאת טווח השורות של העמוד הנוכחי
    int startLine = currentLine + 1;
    int endLine = startLine;

    if (widget.tab.pdfHeadings != null) {
      final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
      final currentIndex =
          sortedHeadings.indexWhere((e) => e.value == currentLine);

      if (currentIndex != -1 && currentIndex < sortedHeadings.length - 1) {
        endLine = sortedHeadings[currentIndex + 1].value - 1;
      } else {
        endLine = startLine + 50;
      }
    } else {
      endLine = startLine + 50;
    }

    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 >= startLine &&
            link.index1 <= endLine &&
            link.connectionType != "commentary" &&
            link.connectionType != "targum" &&
            link.start == null &&
            link.end == null)
        .toList();

    if (relevantLinks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: relevantLinks.length,
      itemBuilder: (context, index) {
        final link = relevantLinks[index];
        return _buildLinkTile(link);
      },
    );
  }

  Widget _buildLinkTile(Link link) {
    final keyStr = '${link.path2}_${link.index2}';
    return ExpansionTile(
      key: PageStorageKey(keyStr),
      maintainState: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        link.heRef,
        style: TextStyle(
          fontSize: widget.fontSize * 0.75,
          fontWeight: FontWeight.w600,
          fontFamily: 'FrankRuhlCLM',
        ),
      ),
      subtitle: Text(
        utils.getTitleFromPath(link.path2),
        style: TextStyle(
          fontSize: widget.fontSize * 0.65,
          fontFamily: 'FrankRuhlCLM',
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      children: [
        GestureDetector(
          onTap: () {
            // פתיחת הספר בלחיצה על הקישור
            widget.openBookCallback(
              TextBookTab(
                book: TextBook(
                  title: utils.getTitleFromPath(link.path2),
                ),
                index: link.index2 - 1,
                openLeftPane:
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<String>(
              future: link.content,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint('Error loading link content: ${snapshot.error}');
                  debugPrint('Stack trace: ${snapshot.stackTrace}');
                  return Text('שגיאה: ${snapshot.error}');
                }
                return Text(
                  utils.stripHtmlIfNeeded(snapshot.data ?? ''),
                  style: TextStyle(
                    fontSize: widget.fontSize * 0.75,
                    fontFamily: 'FrankRuhlCLM',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesView() {
    // נשתמש בספר הטקסט המקורי תמיד - כך ההערות יהיו משותפות
    return FutureBuilder(
      future: DataRepository.instance.library.then(
        (library) => library.findBookByTitle(widget.tab.book.title, TextBook),
      ),
      builder: (context, snapshot) {
        final bookId = widget.tab.book.title; // תמיד נשתמש בשם הספר המקורי

        debugPrint('Building notes view for bookId: $bookId');

        return PersonalNotesSidebar(
          key: ValueKey(bookId),
          bookId: bookId,
          onNavigateToLine: (lineNumber) {
            // מנסים למצוא את העמוד המתאים למספר השורה
            if (widget.tab.pdfHeadings != null) {
              final sortedHeadings =
                  widget.tab.pdfHeadings!.getSortedHeadings();

              // מציאת הכותרת הקרובה ביותר למספר השורה
              for (int i = sortedHeadings.length - 1; i >= 0; i--) {
                if (sortedHeadings[i].value <= lineNumber) {
                  // מצאנו את הכותרת - צריך למצוא את העמוד שלה
                  final headingTitle = sortedHeadings[i].key;
                  final targetPage = _findPageForHeading(headingTitle);

                  if (targetPage != null) {
                    debugPrint(
                        'Navigating from line $lineNumber to page: $targetPage');
                    if (widget.tab.pdfViewerController.isReady) {
                      widget.tab.pdfViewerController
                          .goToPage(pageNumber: targetPage);
                    }
                    return;
                  }
                  break;
                }
              }
            }

            // אם לא הצלחנו למצוא, נניח שזה מספר עמוד
            debugPrint('Navigating to page: $lineNumber');
            if (widget.tab.pdfViewerController.isReady) {
              widget.tab.pdfViewerController.goToPage(pageNumber: lineNumber);
            }
          },
        );
      },
    );
  }

  // מוצא את העמוד של כותרת מסוימת
  int? _findPageForHeading(String heading) {
    final outline = widget.tab.outline.value;
    if (outline == null) return null;

    int? findInNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        if (node.title == heading) {
          return node.dest?.pageNumber;
        }
        final childResult = findInNodes(node.children);
        if (childResult != null) return childResult;
      }
      return null;
    }

    return findInNodes(outline);
  }
}
