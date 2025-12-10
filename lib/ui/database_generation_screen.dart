import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import '../migration/core/models/generation_progress.dart';
import '../migration/dao/daos/database.dart';
import '../migration/dao/repository/seforim_repository.dart';
import '../migration/generator/progress_generator.dart';
import '../data/constants/database_constants.dart';

enum DuplicateBookStrategy {
  skip,
  replace,
  ask,
}

enum IndexCreationMode {
  withIndexes,
  withoutIndexes,
}

class DatabaseGenerationScreen extends StatefulWidget {
  const DatabaseGenerationScreen({super.key});

  @override
  State<DatabaseGenerationScreen> createState() =>
      _DatabaseGenerationScreenState();
}

class _DatabaseGenerationScreenState extends State<DatabaseGenerationScreen> {
  final _logger = Logger('DatabaseGenerationScreen');
  GenerationProgress _progress = GenerationProgress.initial();
  StreamSubscription<GenerationProgress>? _progressSubscription;
  ProgressDatabaseGenerator? _generator;
  DateTime? _startTime;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  String? _selectedLibraryPath;
  String? _selectedDbPath;
  DuplicateBookStrategy _duplicateStrategy = DuplicateBookStrategy.ask;
  IndexCreationMode _indexMode = IndexCreationMode.withIndexes;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _timer?.cancel();
    _generator?.dispose();
    super.dispose();
  }

  void _resetToInitialState() {
    setState(() {
      _progress = GenerationProgress.initial();
      _progressSubscription?.cancel();
      _progressSubscription = null;
      _timer?.cancel();
      _timer = null;
      _generator?.dispose();
      _generator = null;
      _startTime = null;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _selectLibraryFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'בחר תיקיית אוצריא',
      );

      if (selectedDirectory != null) {
        _logger.info('Selected library folder: $selectedDirectory');

        // Auto-set DB path to database file in the selected folder
        final dbPath =
            '$selectedDirectory/${DatabaseConstants.databaseFileName}';

        setState(() {
          _selectedLibraryPath = selectedDirectory;
          _selectedDbPath = dbPath;
        });

        _logger.info('Auto-set database path: $dbPath');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error selecting library folder', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בבחירת תיקייה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Removed - DB path is now auto-set based on library folder

  Future<bool> _askUserAboutDuplicate(String bookTitle) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ספר קיים'),
          content: Text(
              'הספר "$bookTitle" כבר קיים במסד הנתונים.\nהאם להחליף אותו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('דלג'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('החלף'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> _createIndexesOnly() async {
    if (_selectedDbPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור תיקיית אוצריא תחילה'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יצירת אינדקסים'),
          content: const Text(
            'האם ליצור אינדקסים למסד הנתונים?\n\n'
            'תהליך זה עשוי לקחת מספר דקות תלוי בגודל מסד הנתונים.\n\n'
            'אינדקסים משפרים משמעותית את מהירות החיפוש והניווט.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('צור אינדקסים'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() {
      _progress = GenerationProgress(
        phase: GenerationPhase.initializing,
        message: 'יוצר אינדקסים...',
        progress: 0.0,
      );
      _startTime = DateTime.now();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });

    try {
      MyDatabase.initialize();
      final database = MyDatabase.withPath(_selectedDbPath!);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();

      setState(() {
        _progress = GenerationProgress(
          phase: GenerationPhase.finalizing,
          message: 'יוצר אינדקסים...',
          progress: 0.5,
        );
      });

      await repository.createOptimizationIndexes();
      await repository.close();

      setState(() {
        _progress = GenerationProgress.complete();
      });

      _timer?.cancel();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('אינדקסים נוצרו בהצלחה!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      _logger.severe('Error creating indexes', e, stackTrace);
      setState(() {
        _progress = GenerationProgress.error(e.toString());
      });
      _timer?.cancel();
    }
  }

  Future<void> _startGeneration() async {
    if (_selectedLibraryPath == null || _selectedDbPath == null) {
      _logger.warning(
          'Cannot start generation: missing library path or database path');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור תיקיית אוצריא'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _logger.info('Starting database generation');
    _logger.info('Library path: $_selectedLibraryPath');
    _logger.info('Database path: $_selectedDbPath');
    _logger.info('Duplicate strategy: $_duplicateStrategy');
    _logger.info('Index mode: $_indexMode');

    setState(() {
      _progress = GenerationProgress(
        phase: GenerationPhase.initializing,
        message: 'מתחיל...',
      );
      _startTime = DateTime.now();
      _elapsed = Duration.zero;
    });

    // Start timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });

    try {
      MyDatabase.initialize();
      final database = MyDatabase.withPath(_selectedDbPath!);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();

      // Create callback based on selected strategy
      Future<bool> Function(String)? duplicateCallback;
      switch (_duplicateStrategy) {
        case DuplicateBookStrategy.skip:
          duplicateCallback = (title) async => false;
          break;
        case DuplicateBookStrategy.replace:
          duplicateCallback = (title) async => true;
          break;
        case DuplicateBookStrategy.ask:
          duplicateCallback = _askUserAboutDuplicate;
          break;
      }

      _generator = ProgressDatabaseGenerator(
        _selectedLibraryPath!,
        repository,
        onDuplicateBook: duplicateCallback,
        createIndexes: _indexMode == IndexCreationMode.withIndexes,
      );

      _progressSubscription = _generator!.progressStream.listen(
        (progress) {
          setState(() {
            _progress = progress;
          });
        },
        onError: (error) {
          final errorMsg = error.toString();
          _logger.severe('Error during generation: $errorMsg');
          setState(() {
            _progress = GenerationProgress.error(errorMsg);
          });
        },
      );

      await _generator!.generate();
      await repository.close();

      _timer?.cancel();
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      _logger.severe('Error during generation: $errorMsg', e, stackTrace);
      setState(() {
        _progress = GenerationProgress.error(errorMsg);
      });
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('יצירת מסד נתונים'),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Configuration section
                if (_progress.phase == GenerationPhase.idle) ...[
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'הגדרות',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 16),

                          // Library folder selection
                          _buildPathSelector(
                            label: 'תיקיית אוצריא',
                            path: _selectedLibraryPath,
                            onTap: _selectLibraryFolder,
                            icon: Icons.folder_open,
                          ),

                          const SizedBox(height: 8),

                          // Database path display (read-only)
                          if (_selectedDbPath != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.blue[700], size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'מסד הנתונים: $_selectedDbPath',
                                      style: TextStyle(
                                        color: Colors.blue[900],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // Index creation mode
                          Text(
                            'יצירת אינדקסים',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'אינדקסים משפרים את מהירות החיפוש אך מאריכים את זמן היצירה',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                          const SizedBox(height: 8),

                          // ignore: deprecated_member_use
                          RadioListTile<IndexCreationMode>(
                            title: const Text('עם אינדקסים (מומלץ)'),
                            subtitle: const Text(
                                'מהיר יותר בשימוש, אך לוקח יותר זמן ליצירה'),
                            value: IndexCreationMode.withIndexes,
                            // ignore: deprecated_member_use
                            groupValue: _indexMode,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _indexMode = value!;
                              });
                            },
                          ),
                          // ignore: deprecated_member_use
                          RadioListTile<IndexCreationMode>(
                            title: const Text('בלי אינדקסים'),
                            subtitle:
                                const Text('יצירה מהירה, אך חיפוש איטי יותר'),
                            value: IndexCreationMode.withoutIndexes,
                            // ignore: deprecated_member_use
                            groupValue: _indexMode,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _indexMode = value!;
                              });
                            },
                          ),

                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // Duplicate strategy
                          Text(
                            'טיפול בספרים קיימים',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),

                          // ignore: deprecated_member_use
                          RadioListTile<DuplicateBookStrategy>(
                            title: const Text('שאל בכל פעם'),
                            value: DuplicateBookStrategy.ask,
                            // ignore: deprecated_member_use
                            groupValue: _duplicateStrategy,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _duplicateStrategy = value!;
                              });
                            },
                          ),
                          // ignore: deprecated_member_use
                          RadioListTile<DuplicateBookStrategy>(
                            title: const Text('דלג על ספרים קיימים'),
                            value: DuplicateBookStrategy.skip,
                            // ignore: deprecated_member_use
                            groupValue: _duplicateStrategy,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _duplicateStrategy = value!;
                              });
                            },
                          ),
                          // ignore: deprecated_member_use
                          RadioListTile<DuplicateBookStrategy>(
                            title: const Text('החלף ספרים קיימים'),
                            value: DuplicateBookStrategy.replace,
                            // ignore: deprecated_member_use
                            groupValue: _duplicateStrategy,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _duplicateStrategy = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Status Card
                if (_progress.phase != GenerationPhase.idle)
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          // Phase indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _progress.phase.emoji,
                                style: const TextStyle(fontSize: 48),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                _progress.phase.displayName,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Progress bar
                          if (_progress.phase != GenerationPhase.error)
                            Column(
                              children: [
                                LinearProgressIndicator(
                                  value: _progress.progress,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _progress.isComplete
                                        ? Colors.green
                                        : Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(_progress.progress * 100).toStringAsFixed(1)}%',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),

                          const SizedBox(height: 16),

                          // Current message
                          Text(
                            _progress.message,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),

                          // Current book
                          if (_progress.currentBook.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'ספר נוכחי: ${_progress.currentBook}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          // Elapsed time
                          if (_startTime != null && !_progress.isComplete) ...[
                            const SizedBox(height: 8),
                            Text(
                              'זמן שעבר: ${_formatDuration(_elapsed)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Statistics Cards
                if (_progress.totalBooks > 0 || _progress.totalLinks > 0)
                  Row(
                    children: [
                      // Books card
                      if (_progress.totalBooks > 0)
                        Expanded(
                          child: _StatCard(
                            icon: Icons.book,
                            title: 'ספרים',
                            current: _progress.processedBooks,
                            total: _progress.totalBooks,
                            color: Colors.blue,
                          ),
                        ),

                      if (_progress.totalBooks > 0 && _progress.totalLinks > 0)
                        const SizedBox(width: 16),

                      // Links card
                      if (_progress.totalLinks > 0)
                        Expanded(
                          child: _StatCard(
                            icon: Icons.link,
                            title: 'קישורים',
                            current: _progress.processedLinks,
                            total: _progress.totalLinks,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Error message
                if (_progress.error != null)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _progress.error!,
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _progress.error!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('השגיאה הועתקה ללוח'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('העתק שגיאה'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_progress.error != null) const SizedBox(height: 16),

                // Action buttons
                if (_progress.error != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _resetToInitialState,
                          icon: const Icon(Icons.refresh),
                          label: const Text('חזור להתחלה'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _startGeneration,
                          icon: const Icon(Icons.replay),
                          label: const Text('נסה שוב'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_progress.isComplete &&
                    _indexMode == IndexCreationMode.withoutIndexes) ...[
                  // Show option to create indexes after completion
                  Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _createIndexesOnly,
                        icon: const Icon(Icons.add_chart),
                        label: const Text('צור אינדקסים עכשיו'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'מומלץ ליצור אינדקסים לשיפור ביצועי החיפוש',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange[700],
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ] else
                  ElevatedButton(
                    onPressed: _progress.phase == GenerationPhase.idle ||
                            _progress.phase == GenerationPhase.complete
                        ? _startGeneration
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor:
                          _progress.isComplete ? Colors.green : Colors.blue,
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: Text(
                      _getButtonText(),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                const SizedBox(height: 16),

                // Info text
                if (_progress.phase == GenerationPhase.idle)
                  Text(
                    'בחר תיקיית אוצריא.\n'
                    'מסד הנתונים ייווצר אוטומטית בתיקייה (${DatabaseConstants.databaseFileName}).\n'
                    'אם הקובץ קיים, הוא ישמש למסד הנתונים.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                    textAlign: TextAlign.center,
                  ),

                if (_progress.isComplete && _progress.error == null)
                  Text(
                    'מסד הנתונים נוצר בהצלחה!\n'
                    'זמן כולל: ${_formatDuration(_elapsed)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPathSelector({
    required String label,
    required String? path,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    path ?? 'לחץ לבחירה...',
                    style: TextStyle(
                      color: path != null ? Colors.black87 : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_back_ios, size: 16, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getButtonText() {
    if (_progress.phase == GenerationPhase.idle) {
      return 'התחל יצירת מסד נתונים';
    } else if (_progress.isComplete && _progress.error == null) {
      return 'הושלם בהצלחה ✓';
    } else {
      return 'מעבד...';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int current;
  final int total;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.current,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percentage =
        total > 0 ? (current / total * 100).toStringAsFixed(0) : '0';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '$current / $total',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '$percentage%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
