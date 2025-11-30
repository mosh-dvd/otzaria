import 'package:equatable/equatable.dart';

/// Events for database migration
abstract class DatabaseMigrationEvent extends Equatable {
  const DatabaseMigrationEvent();

  @override
  List<Object?> get props => [];
}

/// Event to check which books need to be migrated
class CheckBooksToMigrate extends DatabaseMigrationEvent {
  const CheckBooksToMigrate();
}

/// Event to start the migration process
class StartMigration extends DatabaseMigrationEvent {
  final List<String> bookTitles;

  const StartMigration(this.bookTitles);

  @override
  List<Object?> get props => [bookTitles];
}

/// Event to cancel the migration process
class CancelMigration extends DatabaseMigrationEvent {
  const CancelMigration();
}

/// Event to reset the migration state
class ResetMigrationState extends DatabaseMigrationEvent {
  const ResetMigrationState();
}

/// Event to update progress during migration
class UpdateMigrationProgress extends DatabaseMigrationEvent {
  final String currentBook;
  final int processedCount;
  final int totalCount;

  const UpdateMigrationProgress({
    required this.currentBook,
    required this.processedCount,
    required this.totalCount,
  });

  @override
  List<Object?> get props => [currentBook, processedCount, totalCount];
}

/// Event to migrate books from a specific folder
class MigrateFolderToDatabase extends DatabaseMigrationEvent {
  final String folderPath;

  const MigrateFolderToDatabase(this.folderPath);

  @override
  List<Object?> get props => [folderPath];
}
