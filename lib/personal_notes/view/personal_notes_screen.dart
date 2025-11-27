import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_storage.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/input_dialog.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

class PersonalNotesManagerScreen extends StatefulWidget {
  const PersonalNotesManagerScreen({super.key});

  @override
  State<PersonalNotesManagerScreen> createState() =>
      _PersonalNotesManagerScreenState();
}

class _PersonalNotesManagerScreenState extends State<PersonalNotesManagerScreen> {
  final PersonalNotesRepository _repository = PersonalNotesRepository();

  List<StoredBookNotes> _books = [];
  String? _selectedFilter; // null = all notes
  bool _isLoadingBooks = true;
  String? _booksError;
  Map<String, PersonalNotesState> _bookStates = {};
  final Map<String, bool> _expansionState = {};

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoadingBooks = true;
      _booksError = null;
    });

    try {
      final books = await _repository.listBooksWithNotes();
      if (!mounted) return;
      setState(() {
        _books = books;
        _isLoadingBooks = false;
      });
      // Load all books
      for (final book in books) {
        context.read<PersonalNotesBloc>().add(LoadPersonalNotes(book.bookId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booksError = e.toString();
        _isLoadingBooks = false;
      });
    }
  }

  Future<void> _reloadAllBooks() async {
    // Clear existing states
    setState(() {
      _bookStates.clear();
    });
    
    // Reload the books list from storage
    await _loadBooks();
  }

  void _onFilterChanged(String? filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingBooks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_booksError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'אירעה שגיאה בעת טעינת רשימת ההערות:\n${_booksError!}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadBooks,
              child: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }

    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('לא נמצאו הערות אישיות.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadBooks,
              child: const Text('רענון'),
            ),
          ],
        ),
      );
    }

    return BlocListener<PersonalNotesBloc, PersonalNotesState>(
      listener: (context, state) {
        // Store the state for each book and trigger rebuild
        if (state.bookId != null) {
          setState(() {
            _bookStates[state.bookId!] = state;
          });
        }
      },
      child: Row(
        children: [
          // Right sidebar navigation
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: _buildNavigationPanel(),
          ),
          // Main content area
          Expanded(
            child: _buildAllNotesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationPanel() {
    return Column(
      children: [
        Container(
          height: 1,
          color: Colors.grey.shade300,
        ),
        Expanded(
          child: _buildNotesTree(),
        ),
      ],
    );
  }

  Widget _buildNotesTree() {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (libraryState.error != null) {
          return Center(child: Text('Error: ${libraryState.error}'));
        }

        if (libraryState.library == null) {
          return const Center(child: Text('No library data available'));
        }

        final rootCategory = libraryState.library!;
        final totalNotesCount = _getNotesCountForCategory(rootCategory) + _getMissingNotesCount();
        final isRootExpanded = _expansionState['/personal_notes_root'] ?? true;
        final isRootSelected = _selectedFilter == null;

        return SingleChildScrollView(
          child: Column(
            children: [
              // Root "הערות אישיות" folder
              InkWell(
                onTap: () => _onFilterChanged(null),
                child: Container(
                  padding: const EdgeInsets.only(
                    right: 16.0,
                    left: 16.0,
                    top: 12.0,
                    bottom: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: isRootSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3)
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isRootExpanded
                            ? FluentIcons.folder_open_24_regular
                            : FluentIcons.folder_24_regular,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'הערות אישיות',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      if (totalNotesCount > 0)
                        Text(
                          '($totalNotesCount)',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expansionState['/personal_notes_root'] = !isRootExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            isRootExpanded
                                ? FluentIcons.chevron_up_24_regular
                                : FluentIcons.chevron_down_24_regular,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isRootExpanded) ...[
                ..._buildCategoryChildren(rootCategory, 0),
                _buildMissingNotesTile(),
              ],
            ],
          ),
        );
      },
    );
  }

  int _getMissingNotesCount() {
    int count = 0;
    for (final state in _bookStates.values) {
      count += state.missingNotes.length;
    }
    return count;
  }

  int _getNotesCountForBook(String bookTitle) {
    final state = _bookStates[bookTitle];
    if (state != null) {
      return state.locatedNotes.length + state.missingNotes.length;
    }
    return 0;
  }

  int _getNotesCountForCategory(Category category) {
    int count = 0;
    for (final book in category.books) {
      count += _getNotesCountForBook(book.title);
    }
    for (final subCat in category.subCategories) {
      count += _getNotesCountForCategory(subCat);
    }
    return count;
  }

  Widget _buildMissingNotesTile() {
    final count = _getMissingNotesCount();
    if (count == 0) return const SizedBox.shrink();
    
    final isSelected = _selectedFilter == '__missing__';

    return InkWell(
      onTap: () => _onFilterChanged('__missing__'),
      child: Container(
        padding: const EdgeInsets.only(
          right: 16.0 + 24.0,
          left: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.warning_24_regular,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'הערות ללא מיקום',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (count > 0)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(Category category, int count, int level) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final isExpanded = _expansionState[category.path] ?? level == 0;
    final isSelected = _selectedFilter == category.path;

    return Column(
      children: [
        InkWell(
          onTap: () => _onFilterChanged(category.path),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0),
              left: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 8),
                if (category.subCategories.isNotEmpty || category.books.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expansionState[category.path] = !isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isExpanded
                            ? FluentIcons.chevron_up_24_regular
                            : FluentIcons.chevron_down_24_regular,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && category.path != '/__missing__')
          ..._buildCategoryChildren(category, level),
      ],
    );
  }

  List<Widget> _buildCategoryChildren(Category category, int level) {
    final List<Widget> children = [];

    for (final subCategory in category.subCategories) {
      final count = _getNotesCountForCategory(subCategory);
      if (count > 0) {
        children.add(_buildCategoryTile(subCategory, count, level + 1));
      }
    }

    for (final book in category.books) {
      final count = _getNotesCountForBook(book.title);
      if (count > 0) {
        children.add(_buildBookTile(book, count, level + 1));
      }
    }

    return children;
  }

  Widget _buildBookTile(Book book, int count, int level) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final isSelected = _selectedFilter == book.title;

    return InkWell(
      onTap: () => _onFilterChanged(book.title),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0) + 32.0,
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.book_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                book.title,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (count > 0)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }



  List<String> _getBooksInCategory(Category category) {
    final List<String> bookTitles = [];
    
    void collectBooks(Category cat) {
      for (final book in cat.books) {
        bookTitles.add(book.title);
      }
      for (final subCat in cat.subCategories) {
        collectBooks(subCat);
      }
    }
    
    collectBooks(category);
    return bookTitles;
  }

  Widget _buildAllNotesList() {
    final allNotes = <_NoteWithBook>[];

    // Collect all notes from all books
    for (final book in _books) {
      final state = _bookStates[book.bookId];
      if (state != null) {
        for (final note in state.locatedNotes) {
          allNotes.add(_NoteWithBook(note: note, bookId: book.bookId));
        }
        if (_selectedFilter == '__missing__' || _selectedFilter == null) {
          for (final note in state.missingNotes) {
            allNotes.add(_NoteWithBook(
                note: note, bookId: book.bookId, isMissing: true));
          }
        }
      }
    }

    // Filter by selected filter
    List<_NoteWithBook> filteredNotes;
    
    if (_selectedFilter == null) {
      // Show all notes
      filteredNotes = allNotes;
    } else if (_selectedFilter == '__missing__') {
      // Show only missing notes
      filteredNotes = allNotes.where((n) => n.isMissing).toList();
    } else if (_selectedFilter!.startsWith('/')) {
      // Category selected - find all books in this category
      final libraryState = context.read<LibraryBloc>().state;
      if (libraryState.library != null) {
        Category? findCategory(Category cat, String path) {
          if (cat.path == path) return cat;
          for (final subCat in cat.subCategories) {
            final found = findCategory(subCat, path);
            if (found != null) return found;
          }
          return null;
        }
        
        final category = findCategory(libraryState.library!, _selectedFilter!);
        if (category != null) {
          final booksInCategory = _getBooksInCategory(category);
          filteredNotes = allNotes.where((n) => booksInCategory.contains(n.bookId)).toList();
        } else {
          filteredNotes = [];
        }
      } else {
        filteredNotes = [];
      }
    } else {
      // Book selected
      filteredNotes = allNotes.where((n) => n.bookId == _selectedFilter).toList();
    }

    // Filter missing notes if not showing missing filter
    final displayNotes = _selectedFilter == '__missing__'
        ? filteredNotes
        : filteredNotes;

    // Sort by book and line number
    displayNotes.sort((a, b) {
      final bookCompare = a.bookId.compareTo(b.bookId);
      if (bookCompare != 0) return bookCompare;
      return (a.note.lineNumber ?? 0).compareTo(b.note.lineNumber ?? 0);
    });

    if (displayNotes.isEmpty) {
      return const Center(
        child: Text('אין הערות להצגה'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: displayNotes.length,
      itemBuilder: (context, index) {
        final item = displayNotes[index];
        final showBookHeader = index == 0 ||
            displayNotes[index - 1].bookId != item.bookId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBookHeader && _selectedFilter == null)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  item.bookId,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            _buildNoteCard(item.note, item.isMissing),
          ],
        );
      },
    );
  }

  Widget _buildNoteCard(PersonalNote note, bool isMissing) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Row(
          children: [
            Text(
              isMissing ? 'הערה ללא מיקום' : 'שורה ${note.lineNumber}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            Text(
              _formatDate(note.updatedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMissing && note.referenceWords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Text(
                  note.referenceWords.join(' '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            Text(
              note.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (isMissing && note.lastKnownLineNumber != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'שורה קודמת: ${note.lastKnownLineNumber}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        onTap: isMissing ? () => _repositionMissing(note) : null,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'עריכה',
              icon: const Icon(FluentIcons.edit_24_regular),
              onPressed: () => _editNote(note),
            ),
            if (isMissing)
              IconButton(
                tooltip: 'מיקום מחדש',
                icon: const Icon(FluentIcons.location_24_regular),
                onPressed: () => _repositionMissing(note),
              ),
            IconButton(
              tooltip: 'מחיקה',
              icon: const Icon(FluentIcons.delete_24_regular),
              onPressed: () => _deleteNote(note),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(PersonalNote note) async {
    final controller = TextEditingController(text: note.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => PersonalNoteEditorDialog(
        title: 'עריכת הערה',
        controller: controller,
      ),
    );
    if (result == null) return;

    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      UiSnack.show('ההערה ריקה, לא נשמרה');
      return;
    }

    if (!mounted) return;
    context.read<PersonalNotesBloc>().add(
          UpdatePersonalNote(
            bookId: note.bookId,
            noteId: note.id,
            content: trimmed,
          ),
        );
    UiSnack.show('ההערה עודכנה');
  }

  Future<void> _deleteNote(PersonalNote note) async {
    final shouldDelete = await showConfirmationDialog(
      context: context,
      title: 'מחיקת הערה',
      content: 'האם למחוק את ההערה לצמיתות?',
      confirmText: 'מחק',
      isDangerous: true,
    );

    if (shouldDelete == true) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(
            DeletePersonalNote(
              bookId: note.bookId,
              noteId: note.id,
            ),
          );
      UiSnack.show('ההערה נמחקה');
    }
  }

  Future<void> _repositionMissing(PersonalNote note) async {
    final result = await showInputDialog(
      context: context,
      title: 'מיקום מחדש של הערה',
      subtitle: note.lastKnownLineNumber != null
          ? 'שורה קודמת: ${note.lastKnownLineNumber}'
          : null,
      labelText: 'מספר שורה חדש',
      initialValue: (note.lastKnownLineNumber ?? '').toString(),
      keyboardType: TextInputType.number,
    );

    final newLine = result != null ? int.tryParse(result) : null;

    if (newLine != null) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(
            RepositionPersonalNote(
              bookId: note.bookId,
              noteId: note.id,
              lineNumber: newLine,
            ),
          );
      UiSnack.show('ההערה הועברה לשורה $newLine');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _NoteWithBook {
  final PersonalNote note;
  final String bookId;
  final bool isMissing;

  _NoteWithBook({
    required this.note,
    required this.bookId,
    this.isMissing = false,
  });
}
