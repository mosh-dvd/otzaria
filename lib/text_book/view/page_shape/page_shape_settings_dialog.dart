import 'package:flutter/material.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

/// דיאלוג הגדרות צורת הדף - בחירת מפרשים לכל מיקום
class PageShapeSettingsDialog extends StatefulWidget {
  final List<String> availableCommentators;
  final String bookTitle;
  final String? currentLeft;
  final String? currentRight;
  final String? currentBottom;
  final String? currentBottomRight;

  const PageShapeSettingsDialog({
    super.key,
    required this.availableCommentators,
    required this.bookTitle,
    this.currentLeft,
    this.currentRight,
    this.currentBottom,
    this.currentBottomRight,
  });

  @override
  State<PageShapeSettingsDialog> createState() =>
      _PageShapeSettingsDialogState();
}

class _PageShapeSettingsDialogState extends State<PageShapeSettingsDialog> {
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    // טעינת הערכים הנוכחיים שהועברו מהמסך
    setState(() {
      _leftCommentator = widget.currentLeft;
      _rightCommentator = widget.currentRight;
      _bottomCommentator = widget.currentBottom;
      _bottomRightCommentator = widget.currentBottomRight;
    });
  }

  Future<void> _saveSettings() async {
    await PageShapeSettingsManager.saveConfiguration(
      widget.bookTitle,
      {
        'left': _leftCommentator,
        'right': _rightCommentator,
        'bottom': _bottomCommentator,
        'bottomRight': _bottomRightCommentator,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הגדרות צורת הדף'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'בחר מפרשים להצגה:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildCommentatorDropdown(
                label: 'מפרש שמאלי (יוצג בימין)',
                value: _leftCommentator,
                onChanged: (value) => setState(() => _leftCommentator = value),
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש ימני (יוצג בשמאל)',
                value: _rightCommentator,
                onChanged: (value) => setState(() => _rightCommentator = value),
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש תחתון',
                value: _bottomCommentator,
                onChanged: (value) =>
                    setState(() => _bottomCommentator = value),
              ),
              const SizedBox(height: 12),
              _buildCommentatorDropdown(
                label: 'מפרש תחתון נוסף',
                value: _bottomRightCommentator,
                onChanged: (value) =>
                    setState(() => _bottomRightCommentator = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: () async {
            await _saveSettings();
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          child: const Text('שמור'),
        ),
      ],
    );
  }

  Widget _buildCommentatorDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String?>(
          value: value,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('ללא מפרש'),
            ),
            ...widget.availableCommentators.map(
              (commentator) => DropdownMenuItem<String?>(
                value: commentator,
                child: Text(commentator),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
