import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

class TzuratHadafDialog extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;

  const TzuratHadafDialog({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
  });

  @override
  State<TzuratHadafDialog> createState() => _TzuratHadafDialogState();
}

class _TzuratHadafDialogState extends State<TzuratHadafDialog> {
  String? _topCommentator;
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;

  String get _settingsKey => 'tzurat_hadaf_config_${widget.bookTitle}';

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  void _loadConfiguration() {
    final configString = Settings.getValue<String>(_settingsKey);
    if (configString != null) {
      try {
        final config = json.decode(configString) as Map<String, dynamic>;
        setState(() {
          _topCommentator = config['top'];
          _leftCommentator = config['left'];
          _rightCommentator = config['right'];
          _bottomCommentator = config['bottom'];
        });
      } catch (e) {
        // Handle error or ignore if JSON is malformed
      }
    }
  }

  void _saveConfiguration() {
    final config = {
      'top': _topCommentator,
      'left': _leftCommentator,
      'right': _rightCommentator,
      'bottom': _bottomCommentator,
    };
    final configString = json.encode(config);
    Settings.setValue<String>(_settingsKey, configString);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הגדרת תצורת הדף'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCommentatorSelector('מפרש עליון', _topCommentator, (value) {
              setState(() => _topCommentator = value);
            }),
            _buildCommentatorSelector('מפרש שמאלי', _leftCommentator, (value) {
              setState(() => _leftCommentator = value);
            }),
            _buildCommentatorSelector('מפרש ימני', _rightCommentator, (value) {
              setState(() => _rightCommentator = value);
            }),
            _buildCommentatorSelector('מפרש תחתון', _bottomCommentator, (value) {
              setState(() => _bottomCommentator = value);
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: () {
            _saveConfiguration();
            Navigator.of(context).pop(true);
          },
          child: const Text('שמור'),
        ),
      ],
    );
  }

  Widget _buildCommentatorSelector(
    String label,
    String? currentValue,
    ValueChanged<String?> onChanged,
  ) {
    // Add "None" option to the list
    final items = [null, ...widget.availableCommentators];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items.map((String? commentator) {
          return DropdownMenuItem<String>(
            value: commentator,
            child: Text(commentator ?? 'ללא'),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
