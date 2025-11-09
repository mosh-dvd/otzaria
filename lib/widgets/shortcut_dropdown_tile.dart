import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/shortcut_validator.dart';

/// Custom DropDownSettingsTile that filters out shortcuts already in use
class ShortcutDropDownTile extends StatelessWidget {
  final String settingKey;
  final String title;
  final String selected;
  final Widget? leading;
  final Map<String, String> allShortcuts;

  const ShortcutDropDownTile({
    super.key,
    required this.settingKey,
    required this.title,
    required this.selected,
    required this.allShortcuts,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    // Get current value for this setting
    final currentValue = Settings.getValue<String>(settingKey) ?? selected;

    // Get all shortcuts that are in use by OTHER settings
    final usedShortcuts = <String>{};
    for (final key in ShortcutValidator.shortcutKeys) {
      if (key != settingKey) {
        // Don't include current setting
        final value = Settings.getValue<String>(key) ??
            ShortcutValidator.defaultShortcuts[key];
        if (value != null && value.isNotEmpty) {
          usedShortcuts.add(value);
        }
      }
    }

    // Filter out shortcuts that are already in use
    final availableShortcuts = <String, String>{};
    for (final entry in allShortcuts.entries) {
      // Include if: it's the current value OR it's not used by others
      if (entry.key == currentValue || !usedShortcuts.contains(entry.key)) {
        availableShortcuts[entry.key] = entry.value;
      }
    }

    // If current value is not in available shortcuts (shouldn't happen), add it
    if (!availableShortcuts.containsKey(currentValue)) {
      availableShortcuts[currentValue] =
          allShortcuts[currentValue] ?? currentValue.toUpperCase();
    }

    return DropDownSettingsTile<String>(
      settingKey: settingKey,
      title: title,
      selected: selected,
      values: availableShortcuts,
      leading: leading,
      onChange: (newValue) {
        // Check if the new value creates a conflict
        final conflicts = ShortcutValidator.checkConflicts();
        if (conflicts.isNotEmpty && conflicts.containsKey(newValue)) {
          // Show warning
          final conflictingKeys = conflicts[newValue]!;
          final conflictingNames = conflictingKeys
              .where((k) => k != settingKey)
              .map((k) => ShortcutValidator.shortcutNames[k] ?? k)
              .join(', ');

          if (conflictingNames.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'אזהרה: קיצור זה כבר בשימוש עבור: $conflictingNames',
                  textDirection: TextDirection.rtl,
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }
}
