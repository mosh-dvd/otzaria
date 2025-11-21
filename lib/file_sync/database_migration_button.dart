import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/file_sync/database_migration_bloc.dart';
import 'package:otzaria/file_sync/database_migration_dialog.dart';
import 'package:otzaria/file_sync/database_migration_event.dart';
import 'package:otzaria/file_sync/database_migration_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// Button to trigger database migration
class DatabaseMigrationButton extends StatelessWidget {
  final double size;
  final Color? color;

  const DatabaseMigrationButton({
    super.key,
    this.size = 24.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DatabaseMigrationBloc(
        fileSystemData: FileSystemData.instance,
      ),
      child: BlocConsumer<DatabaseMigrationBloc, DatabaseMigrationState>(
        listener: (context, state) {
          // Show dialog when ready to migrate
          if (state.status == DatabaseMigrationStatus.ready && state.booksToMigrate.isNotEmpty) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => BlocProvider.value(
                value: context.read<DatabaseMigrationBloc>(),
                child: const DatabaseMigrationDialog(),
              ),
            );
          }
        },
        builder: (context, state) {
          Color iconColor;
          IconData iconData;
          String tooltip;

          switch (state.status) {
            case DatabaseMigrationStatus.checking:
              iconColor = color ?? Theme.of(context).iconTheme.color!;
              iconData = FluentIcons.database_search_24_regular;
              tooltip = 'בודק ספרים...';
              break;

            case DatabaseMigrationStatus.ready:
              iconColor = state.booksToMigrate.isNotEmpty
                  ? Colors.orange
                  : Colors.green;
              iconData = FluentIcons.database_24_regular;
              tooltip = state.booksToMigrate.isNotEmpty
                  ? '${state.booksToMigrate.length} ספרים ממתינים להעברה'
                  : 'כל הספרים במסד הנתונים';
              break;

            case DatabaseMigrationStatus.migrating:
              iconColor = Colors.blue;
              iconData = FluentIcons.database_arrow_right_24_regular;
              tooltip = 'מעביר ספרים... ${state.progress.toStringAsFixed(0)}%';
              break;

            case DatabaseMigrationStatus.completed:
              iconColor = Colors.green;
              iconData = FluentIcons.database_checkmark_24_regular;
              tooltip = 'ההעברה הושלמה';
              break;

            case DatabaseMigrationStatus.error:
              iconColor = Colors.red;
              iconData = FluentIcons.database_24_regular;
              tooltip = 'שגיאה בהעברה';
              break;

            default:
              iconColor = color ?? Theme.of(context).iconTheme.color!;
              iconData = FluentIcons.database_24_regular;
              tooltip = 'העבר ספרים למסד נתונים';
          }

          return Tooltip(
            message: tooltip,
            child: IconButton(
              onPressed: state.status == DatabaseMigrationStatus.migrating
                  ? null
                  : () {
                      context.read<DatabaseMigrationBloc>().add(
                            const CheckBooksToMigrate(),
                          );
                    },
              icon: state.status == DatabaseMigrationStatus.checking ||
                      state.status == DatabaseMigrationStatus.migrating
                  ? SizedBox(
                      width: size * 0.7,
                      height: size * 0.7,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(
                      iconData,
                      color: iconColor,
                      size: size,
                    ),
              splashRadius: size * 0.8,
            ),
          );
        },
      ),
    );
  }
}
