import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';

class PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState> {
  PersonalNotesBloc({PersonalNotesRepository? repository})
      : _repository = repository ?? PersonalNotesRepository(),
        super(const PersonalNotesState.initial()) {
    on<LoadPersonalNotes>(_onLoadNotes);
    on<AddPersonalNote>(_onAddNote);
    on<UpdatePersonalNote>(_onUpdateNote);
    on<DeletePersonalNote>(_onDeleteNote);
    on<RepositionPersonalNote>(_onRepositionNote);
    on<ConvertLegacyNotes>(_onConvertLegacy);
  }

  final PersonalNotesRepository _repository;

  Future<void> _onLoadNotes(
    LoadPersonalNotes event,
    Emitter<PersonalNotesState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        bookId: event.bookId,
        errorMessage: null,
      ),
    );

    try {
      final notes = await _repository.loadNotes(event.bookId);
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          bookId: event.bookId,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onAddNote(
    AddPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.addNote(
        bookId: event.bookId,
        lineNumber: event.lineNumber,
        content: event.content,
        selectedText: event.selectedText,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onUpdateNote(
    UpdatePersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.updateNote(
        bookId: event.bookId,
        noteId: event.noteId,
        content: event.content,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteNote(
    DeletePersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.deleteNote(
        bookId: event.bookId,
        noteId: event.noteId,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onRepositionNote(
    RepositionPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.repositionNote(
        bookId: event.bookId,
        noteId: event.noteId,
        lineNumber: event.lineNumber,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onConvertLegacy(
    ConvertLegacyNotes event,
    Emitter<PersonalNotesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final summary = await _repository.convertLegacyNotes();

      PersonalNotesState nextState = state.copyWith(
        isLoading: false,
        conversionSummary: summary,
      );

      if (state.bookId != null &&
          summary.convertedBooks.contains(state.bookId)) {
        final notes = await _repository.loadNotes(state.bookId!);
        final split = _splitNotes(notes);
        nextState = nextState.copyWith(
          locatedNotes: split.locatedNotes,
          missingNotes: split.missingNotes,
        );
      }

      emit(nextState);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _emitNotes(
    String bookId,
    List<PersonalNote> notes,
    Emitter<PersonalNotesState> emit,
  ) {
    final split = _splitNotes(notes);
    emit(
      state.copyWith(
        isLoading: false,
        bookId: bookId,
        locatedNotes: split.locatedNotes,
        missingNotes: split.missingNotes,
        errorMessage: null,
      ),
    );
  }

  _NotesPartition _splitNotes(List<PersonalNote> notes) {
    final sorted = sortPersonalNotes(notes);
    final located = <PersonalNote>[];
    final missing = <PersonalNote>[];
    for (final note in sorted) {
      if (note.hasLocation) {
        located.add(note);
      } else {
        missing.add(note);
      }
    }
    return _NotesPartition(locatedNotes: located, missingNotes: missing);
  }
}

class _NotesPartition {
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;

  _NotesPartition({required this.locatedNotes, required this.missingNotes});
}
