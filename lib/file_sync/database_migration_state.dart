import 'package:equatable/equatable.dart';

/// Status of the database migration process
enum DatabaseMigrationStatus {
  initial,
  checking,
  ready,
  migrating,
  completed,
  cancelled,
  error,
}

/// State for database migration
class DatabaseMigrationState extends Equatable {
  final DatabaseMigrationStatus status;
  final List<String> booksToMigrate;
  final String? currentBook;
  final int processedCount;
  final int totalCount;
  final String? errorMessage;
  final Duration? estimatedTimeRemaining;

  const DatabaseMigrationState({
    this.status = DatabaseMigrationStatus.initial,
    this.booksToMigrate = const [],
    this.currentBook,
    this.processedCount = 0,
    this.totalCount = 0,
    this.errorMessage,
    this.estimatedTimeRemaining,
  });

  /// Progress percentage (0-100)
  double get progress {
    if (totalCount == 0) return 0;
    return (processedCount / totalCount * 100).clamp(0, 100);
  }

  /// Whether migration is in progress
  bool get isInProgress => status == DatabaseMigrationStatus.migrating;

  /// Whether migration can be started
  bool get canStart => status == DatabaseMigrationStatus.ready && booksToMigrate.isNotEmpty;

  DatabaseMigrationState copyWith({
    DatabaseMigrationStatus? status,
    List<String>? booksToMigrate,
    String? currentBook,
    int? processedCount,
    int? totalCount,
    String? errorMessage,
    Duration? estimatedTimeRemaining,
  }) {
    return DatabaseMigrationState(
      status: status ?? this.status,
      booksToMigrate: booksToMigrate ?? this.booksToMigrate,
      currentBook: currentBook ?? this.currentBook,
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
      errorMessage: errorMessage ?? this.errorMessage,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
    );
  }

  @override
  List<Object?> get props => [
        status,
        booksToMigrate,
        currentBook,
        processedCount,
        totalCount,
        errorMessage,
        estimatedTimeRemaining,
      ];
}
