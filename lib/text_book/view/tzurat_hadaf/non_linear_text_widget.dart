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
    return CustomPaint(
      size: Size.infinite,
      painter: _NonLinearTextPainter(
        text: text,
        style: style,
        textDirection: Directionality.of(context),
      ),
    );
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

  @override
  void paint(Canvas canvas, Size size) {
    final words = text.split(' ');
    double y = 0;
    int wordIndex = 0;

    while (wordIndex < words.length) {
      // Calculate the available width for the current line
      final double horizontalPadding = _calculateHorizontalPadding(y, size.height);
      final double availableWidth = size.width - 2 * horizontalPadding;

      if (availableWidth <= 0) {
        y += style.fontSize! * 1.5;
        continue;
      }

      // Get the words for the current line
      final lineInfo = _getLine(
        words.sublist(wordIndex),
        availableWidth,
      );
      final line = lineInfo.item1;
      final wordsInLine = lineInfo.item2;

      // Paint the line
      final textSpan = TextSpan(text: line, style: style);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: textDirection,
        textAlign: TextAlign.justify,
      );
      textPainter.layout(minWidth: 0, maxWidth: availableWidth);
      
      final x = (textDirection == TextDirection.rtl)
          ? size.width - horizontalPadding - textPainter.width
          : horizontalPadding;

      textPainter.paint(canvas, Offset(x, y));

      // Move to the next line
      y += textPainter.height;
      wordIndex += wordsInLine;

      if(y > size.height){
        break;
      }
    }
  }

  // Tuple<String, int>
  (String, int) _getLine(List<String> words, double maxWidth) {
    String line = '';
    int wordCount = 0;

    for (final word in words) {
      final testLine = line.isEmpty ? word : '$line $word';
      final textPainter = TextPainter(
        text: TextSpan(text: testLine, style: style),
        textDirection: textDirection,
      );
      textPainter.layout(minWidth: 0, maxWidth: maxWidth);

      if (textPainter.width > maxWidth) {
        break;
      }
      line = testLine;
      wordCount++;
    }
    return (line, wordCount);
  }

  double _calculateHorizontalPadding(double y, double height) {
    // Parabolic function for the "belly" effect
    final double midPoint = height / 2;
    final double normalizedY = (y - midPoint) / midPoint; // from -1 to 1
    final double padding = 30 * (1 - normalizedY * normalizedY); // adjust 30 for more curve
    return padding > 0 ? padding : 0;
  }

  @override
  bool shouldRepaint(covariant _NonLinearTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection;
  }
}
