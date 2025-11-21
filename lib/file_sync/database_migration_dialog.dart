import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/file_sync/database_migration_bloc.dart';
import 'package:otzaria/file_sync/database_migration_event.dart';
import 'package:otzaria/file_sync/database_migration_state.dart';

/// Dialog for database migration process
class DatabaseMigrationDialog extends StatelessWidget {
  const DatabaseMigrationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DatabaseMigrationBloc, DatabaseMigrationState>(
      builder: (context, state) {
        return AlertDialog(
          title: const Text(
            'העברת ספרים למסד נתונים',
            textAlign: TextAlign.right,
          ),
          content: SizedBox(
            width: 500,
            child: _buildContent(context, state),
          ),
          actions: _buildActions(context, state),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, DatabaseMigrationState state) {
    switch (state.status) {
      case DatabaseMigrationStatus.initial:
        return const Center(
          child: Text('מאתחל...', textAlign: TextAlign.right),
        );

      case DatabaseMigrationStatus.checking:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('בודק אילו ספרים צריכים להיות מועברים...', textAlign: TextAlign.right),
          ],
        );

      case DatabaseMigrationStatus.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'נמצאו ${state.booksToMigrate.length} ספרים שטרם הועברו למסד הנתונים.',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            Text(
              'זמן משוער: ${_estimateTime(state.booksToMigrate.length)}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.secondary,
              ),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            const Text(
              'לאחר ההעברה, הקבצים המקוריים יימחקו.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            const Text(
              'האם להתחיל בתהליך ההעברה?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ],
        );

      case DatabaseMigrationStatus.migrating:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: state.progress / 100,
              minHeight: 8,
            ),
            const SizedBox(height: 16),
            Text(
              'מעביר ספר ${state.processedCount + 1} מתוך ${state.totalCount}',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            if (state.currentBook != null)
              Text(
                'ספר נוכחי: ${state.currentBook}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Text(
              '${state.progress.toStringAsFixed(1)}% הושלם',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            if (state.estimatedTimeRemaining != null) ...[
              const SizedBox(height: 8),
              Text(
                'זמן משוער שנותר: ${_formatDuration(state.estimatedTimeRemaining!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ],
        );

      case DatabaseMigrationStatus.completed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'ההעברה הושלמה בהצלחה!',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            Text(
              '${state.totalCount} ספרים הועברו למסד הנתונים',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ],
        );

      case DatabaseMigrationStatus.cancelled:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cancel,
              color: Colors.orange,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'התהליך בוטל',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            Text(
              '${state.processedCount} ספרים הועברו לפני הביטול',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ],
        );

      case DatabaseMigrationStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'אירעה שגיאה',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            Text(
              state.errorMessage ?? 'שגיאה לא ידועה',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions(BuildContext context, DatabaseMigrationState state) {
    switch (state.status) {
      case DatabaseMigrationStatus.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: state.canStart
                ? () {
                    context.read<DatabaseMigrationBloc>().add(
                          StartMigration(state.booksToMigrate),
                        );
                  }
                : null,
            child: const Text('התחל העברה'),
          ),
        ];

      case DatabaseMigrationStatus.migrating:
        return [
          TextButton(
            onPressed: () {
              context.read<DatabaseMigrationBloc>().add(const CancelMigration());
            },
            child: const Text('בטל'),
          ),
        ];

      case DatabaseMigrationStatus.completed:
      case DatabaseMigrationStatus.cancelled:
      case DatabaseMigrationStatus.error:
        return [
          ElevatedButton(
            onPressed: () {
              context.read<DatabaseMigrationBloc>().add(const ResetMigrationState());
              Navigator.of(context).pop();
            },
            child: const Text('סגור'),
          ),
        ];

      default:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ];
    }
  }

  String _estimateTime(int bookCount) {
    // Estimate ~2 seconds per book
    final seconds = bookCount * 2;
    if (seconds < 60) {
      return '$seconds שניות';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).ceil();
      return '$minutes דקות';
    } else {
      final hours = (seconds / 3600).ceil();
      return '$hours שעות';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} שניות';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes} דקות';
    } else {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '$hours:${minutes.toString().padLeft(2, '0')} שעות';
    }
  }
}
