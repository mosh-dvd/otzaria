import 'package:equatable/equatable.dart';

abstract class PersonalNotesEvent extends Equatable {
  const PersonalNotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadPersonalNotes extends PersonalNotesEvent {
  final String bookId;

  const LoadPersonalNotes(this.bookId);

  @override
  List<Object?> get props => [bookId];
}

class AddPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int lineNumber;
  final String content;
  final String? selectedText;

  const AddPersonalNote({
    required this.bookId,
    required this.lineNumber,
    required this.content,
    this.selectedText,
  });

  @override
  List<Object?> get props => [bookId, lineNumber, content, selectedText];
}

class UpdatePersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;
  final String content;

  const UpdatePersonalNote({
    required this.bookId,
    required this.noteId,
    required this.content,
  });

  @override
  List<Object?> get props => [bookId, noteId, content];
}

class DeletePersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;

  const DeletePersonalNote({
    required this.bookId,
    required this.noteId,
  });

  @override
  List<Object?> get props => [bookId, noteId];
}

class RepositionPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;
  final int lineNumber;

  const RepositionPersonalNote({
    required this.bookId,
    required this.noteId,
    required this.lineNumber,
  });

  @override
  List<Object?> get props => [bookId, noteId, lineNumber];
}

class ConvertLegacyNotes extends PersonalNotesEvent {
  const ConvertLegacyNotes();
}
