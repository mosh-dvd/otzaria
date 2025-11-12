import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// דיאלוג הזנת טקסט עם תמיכה באנטר וחיצים
class InputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String labelText;
  final String? hintText;
  final String initialValue;
  final TextInputType? keyboardType;
  final String cancelText;
  final String confirmText;
  final Color? confirmColor;

  const InputDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
    this.keyboardType,
    this.cancelText = 'ביטול',
    this.confirmText = 'שמור',
    this.confirmColor,
  });

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late final TextEditingController _controller;
  int _focusedButtonIndex = 1; // 0 = ביטול, 1 = אישור (ברירת מחדל)
  final FocusNode _textFieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // תן פוקוס לשדה הטקסט אחרי שהדיאלוג נפתח
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // אם הפוקוס בשדה הטקסט, אנטר שולח את הטופס
        if (_textFieldFocusNode.hasFocus) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            _submit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // אם הפוקוס בכפתורים - חיצים ואנטר
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _focusedButtonIndex = _focusedButtonIndex == 0 ? 1 : 0;
          });
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (_focusedButtonIndex == 1) {
            _submit();
          } else {
            Navigator.of(context).pop();
          }
          return KeyEventResult.handled;
        }

        // Escape - ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: _controller,
              focusNode: _textFieldFocusNode,
              keyboardType: widget.keyboardType,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          _buildButton(
            text: widget.cancelText,
            isFocused: _focusedButtonIndex == 0,
            onPressed: () => Navigator.of(context).pop(),
          ),
          _buildButton(
            text: widget.confirmText,
            isFocused: _focusedButtonIndex == 1,
            isConfirm: true,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    bool isConfirm = false,
  }) {
    final color = isConfirm
        ? (widget.confirmColor ?? Theme.of(context).primaryColor)
        : null;

    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? (color ?? Theme.of(context).primaryColor).withValues(alpha: 0.9)
              : null,
        ),
        child: Text(text),
      );
    } else {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
        ),
        child: Text(text),
      );
    }
  }
}

/// הצגת דיאלוג הזנת טקסט
Future<String?> showInputDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  required String labelText,
  String? hintText,
  String initialValue = '',
  TextInputType? keyboardType,
  String cancelText = 'ביטול',
  String confirmText = 'שמור',
  Color? confirmColor,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => InputDialog(
      title: title,
      subtitle: subtitle,
      labelText: labelText,
      hintText: hintText,
      initialValue: initialValue,
      keyboardType: keyboardType,
      cancelText: cancelText,
      confirmText: confirmText,
      confirmColor: confirmColor,
    ),
  );
}
