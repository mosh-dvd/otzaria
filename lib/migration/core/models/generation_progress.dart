/// Model for tracking database generation progress
class GenerationProgress {
  final GenerationPhase phase;
  final String currentBook;
  final int processedBooks;
  final int totalBooks;
  final int processedLines;
  final int totalLines;
  final int processedLinks;
  final int totalLinks;
  final String message;
  final double progress; // 0.0 to 1.0
  final bool isComplete;
  final String? error;

  const GenerationProgress({
    required this.phase,
    this.currentBook = '',
    this.processedBooks = 0,
    this.totalBooks = 0,
    this.processedLines = 0,
    this.totalLines = 0,
    this.processedLinks = 0,
    this.totalLinks = 0,
    this.message = '',
    this.progress = 0.0,
    this.isComplete = false,
    this.error,
  });

  GenerationProgress copyWith({
    GenerationPhase? phase,
    String? currentBook,
    int? processedBooks,
    int? totalBooks,
    int? processedLines,
    int? totalLines,
    int? processedLinks,
    int? totalLinks,
    String? message,
    double? progress,
    bool? isComplete,
    String? error,
  }) {
    return GenerationProgress(
      phase: phase ?? this.phase,
      currentBook: currentBook ?? this.currentBook,
      processedBooks: processedBooks ?? this.processedBooks,
      totalBooks: totalBooks ?? this.totalBooks,
      processedLines: processedLines ?? this.processedLines,
      totalLines: totalLines ?? this.totalLines,
      processedLinks: processedLinks ?? this.processedLinks,
      totalLinks: totalLinks ?? this.totalLinks,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }

  factory GenerationProgress.initial() {
    return const GenerationProgress(
      phase: GenerationPhase.idle,
      message: 'מוכן להתחלה',
    );
  }

  factory GenerationProgress.error(String error) {
    return GenerationProgress(
      phase: GenerationPhase.error,
      message: 'שגיאה: $error',
      error: error,
      isComplete: true,
    );
  }

  factory GenerationProgress.complete() {
    return const GenerationProgress(
      phase: GenerationPhase.complete,
      message: 'התהליך הושלם בהצלחה!',
      progress: 1.0,
      isComplete: true,
    );
  }
}

enum GenerationPhase {
  idle,
  initializing,
  loadingMetadata,
  processingBooks,
  processingLinks,
  finalizing,
  complete,
  error,
}

extension GenerationPhaseExtension on GenerationPhase {
  String get displayName {
    switch (this) {
      case GenerationPhase.idle:
        return 'ממתין';
      case GenerationPhase.initializing:
        return 'מאתחל מסד נתונים';
      case GenerationPhase.loadingMetadata:
        return 'טוען מטא-דאטה';
      case GenerationPhase.processingBooks:
        return 'מעבד ספרים';
      case GenerationPhase.processingLinks:
        return 'מעבד קישורים';
      case GenerationPhase.finalizing:
        return 'משלים';
      case GenerationPhase.complete:
        return 'הושלם';
      case GenerationPhase.error:
        return 'שגיאה';
    }
  }

  String get emoji {
    switch (this) {
      case GenerationPhase.idle:
        return '⏸️';
      case GenerationPhase.initializing:
        return '🔧';
      case GenerationPhase.loadingMetadata:
        return '📋';
      case GenerationPhase.processingBooks:
        return '📚';
      case GenerationPhase.processingLinks:
        return '🔗';
      case GenerationPhase.finalizing:
        return '✨';
      case GenerationPhase.complete:
        return '✅';
      case GenerationPhase.error:
        return '❌';
    }
  }
}
