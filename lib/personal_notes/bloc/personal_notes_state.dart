import 'package:equatable/equatable.dart';

import 'package:otzaria/personal_notes/migration/legacy_notes_converter.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesState extends Equatable {
  final bool isLoading;
  final String? bookId;
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;
  final String? errorMessage;
  final LegacyConversionSummary? conversionSummary;

  const PersonalNotesState({
    required this.isLoading,
    required this.bookId,
    required this.locatedNotes,
    required this.missingNotes,
    required this.errorMessage,
    required this.conversionSummary,
  });

  const PersonalNotesState.initial()
      : isLoading = false,
        bookId = null,
        locatedNotes = const [],
        missingNotes = const [],
        errorMessage = null,
        conversionSummary = null;

  PersonalNotesState copyWith({
    bool? isLoading,
    String? bookId,
    List<PersonalNote>? locatedNotes,
    List<PersonalNote>? missingNotes,
    String? errorMessage,
    LegacyConversionSummary? conversionSummary,
  }) {
    return PersonalNotesState(
      isLoading: isLoading ?? this.isLoading,
      bookId: bookId ?? this.bookId,
      locatedNotes: locatedNotes ?? this.locatedNotes,
      missingNotes: missingNotes ?? this.missingNotes,
      errorMessage: errorMessage,
      conversionSummary: conversionSummary ?? this.conversionSummary,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        bookId,
        locatedNotes,
        missingNotes,
        errorMessage,
        conversionSummary,
      ];
}
