import 'package:flutter/material.dart';
import 'dart:math';

class NonLinearText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const NonLinearText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = _NonLinearTextPainter(
        text: text,
        style: style,
        textDirection: Directionality.of(context),
      );

      final height = painter.calculateHeight(constraints.maxWidth);

      return SizedBox(
        height: height,
        child: CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: painter,
        ),
      );
    });
  }
}

class _NonLinearTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final TextDirection textDirection;

  _NonLinearTextPainter({
    required this.text,
    required this.style,
    required this.textDirection,
  });

  double calculateHeight(double width) {
    if (width <= 0) return 0;

    final words = text.split(' ');
    double y = 0;
    int wordIndex = 0;

    while (wordIndex < words.length) {
      final double horizontalPadding = _calculateHorizontalPadding(y);
      final double availableWidth = width - 2 * horizontalPadding;

      if (availableWidth <= 0) {
        y += style.fontSize! * 1.5;
        continue;
      }

      final lineInfo = _getLine(
        words.sublist(wordIndex),
        availableWidth,
      );
      final line = lineInfo.$1;
      final wordsInLine = lineInfo.$2;

      if (wordsInLine == 0) {
        // Handle case where a single word is wider than the available width
        y += style.fontSize! * 1.5;
        wordIndex++;
        continue;
      }

      final textPainter = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: textDirection,
      );
      textPainter.layout(minWidth: 0, maxWidth: availableWidth);

      y += textPainter.height;
      wordIndex += wordsInLine;
    }
    return y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final words = text.split(' ');
    double y = 0;
    int wordIndex = 0;

    while (wordIndex < words.length) {
      final double horizontalPadding = _calculateHorizontalPadding(y);
      final double availableWidth = size.width - 2 * horizontalPadding;

      if (availableWidth <= 0) {
        y += style.fontSize! * 1.5;
        continue;
      }

      final lineInfo = _getLine(
        words.sublist(wordIndex),
        availableWidth,
      );
      final line = lineInfo.$1;
      final wordsInLine = lineInfo.$2;

      if (wordsInLine == 0) {
        // Handle case where a single word is wider than the available width
        y += style.fontSize! * 1.5;
        wordIndex++;
        continue;
      }

      final textPainter = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: textDirection,
        textAlign: TextAlign.justify,
      );
      textPainter.layout(minWidth: 0, maxWidth: availableWidth);

      final x = (textDirection == TextDirection.rtl)
          ? size.width - horizontalPadding - textPainter.width
          : horizontalPadding;

      textPainter.paint(canvas, Offset(x, y));

      y += textPainter.height;
      wordIndex += wordsInLine;

      if (y > size.height) {
        break;
      }
    }
  }

  (String, int) _getLine(List<String> words, double maxWidth) {
    String line = '';
    int wordCount = 0;

    if (words.isEmpty) {
      return ('', 0);
    }

    for (final word in words) {
      final testLine = line.isEmpty ? word : '$line $word';
      final textPainter = TextPainter(
        text: TextSpan(text: testLine, style: style),
        textDirection: textDirection,
      );
      textPainter.layout(minWidth: 0, maxWidth: maxWidth);

      if (textPainter.width > maxWidth && line.isNotEmpty) {
        break;
      }
      line = testLine;
      wordCount++;
    }
    return (line, wordCount);
  }

  double _calculateHorizontalPadding(double y) {
    // Parabolic function for the "belly" effect
    final double midPoint = 100; // Assume a mid point for the curve
    final double normalizedY = (y - midPoint) / midPoint;
    final double padding = 30 * (1 - normalizedY * normalizedY);
    return padding > 0 ? padding : 0;
  }

  @override
  bool shouldRepaint(covariant _NonLinearTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection;
  }
}
