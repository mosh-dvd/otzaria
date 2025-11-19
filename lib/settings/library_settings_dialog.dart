import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/widgets/generic_settings_dialog.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות ספרייה
/// ניתן לקרוא לה מכל מקום באפליקציה
void showLibrarySettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, currentSettingsState) {
        return GenericSettingsDialog(
          title: 'הגדרות ספרייה',
          width: 500,
          items: [
            SwitchSettingsItem(
              title: 'האם להציג ספרים מאתרים חיצוניים?',
              subtitle: currentSettingsState.showExternalBooks
                  ? 'יוצגו גם ספרים מאתרים חיצוניים'
                  : 'יוצגו רק ספרים מספריית אוצריא',
              value: currentSettingsState.showExternalBooks,
              onChanged: (value) {
                context
                    .read<SettingsBloc>()
                    .add(UpdateShowExternalBooks(value));
                context.read<SettingsBloc>().add(UpdateShowHebrewBooks(value));
                context
                    .read<SettingsBloc>()
                    .add(UpdateShowOtzarHachochma(value));
              },
              dependentItems: currentSettingsState.showExternalBooks
                  ? [
                      CheckboxSettingsItem(
                        title: 'הצג ספרים מאוצר החכמה',
                        value: currentSettingsState.showOtzarHachochma,
                        onChanged: (bool? value) {
                          if (value != null) {
                            context.read<SettingsBloc>().add(
                                  UpdateShowOtzarHachochma(value),
                                );
                          }
                        },
                      ),
                      CheckboxSettingsItem(
                        title: 'הצג ספרים מהיברובוקס',
                        value: currentSettingsState.showHebrewBooks,
                        onChanged: (bool? value) {
                          if (value != null) {
                            context.read<SettingsBloc>().add(
                                  UpdateShowHebrewBooks(value),
                                );
                          }
                        },
                      ),
                    ]
                  : null,
            ),
          ],
        );
      },
    ),
  );
}
