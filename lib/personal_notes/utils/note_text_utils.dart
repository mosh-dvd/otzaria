import 'package:characters/characters.dart';

const int kReferenceWordsLimit = 10;

final RegExp wordPattern = RegExp(r'[\p{L}\d]+', unicode: true);
final RegExp wordCharPattern = RegExp(r'[\p{L}\d]', unicode: true);

List<String> splitBookContentIntoLines(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

List<String> extractReferenceWordsFromLine(
  String line, {
  int limit = kReferenceWordsLimit,
}) {
  final matches = wordPattern.allMatches(line);
  final words = <String>[];
  for (final match in matches) {
    words.add(normalizeWord(match.group(0)!));
    if (words.length == limit) {
      break;
    }
  }
  return words;
}

List<String> extractReferenceWordsFromLines(
  List<String> lines,
  int lineNumber, {
  int limit = kReferenceWordsLimit,
}) {
  final index = lineNumber - 1;
  if (index < 0 || index >= lines.length) {
    return const [];
  }
  return extractReferenceWordsFromLine(lines[index], limit: limit);
}

String normalizeWord(String word) {
  final cleaned =
      word.characters.where((c) => wordCharPattern.hasMatch(c)).toString();
  final normalized = cleaned.trim();
  if (normalized.isEmpty) {
    return word.trim();
  }
  return normalized;
}

double computeWordOverlapRatio(List<String> stored, List<String> actual) {
  if (stored.isEmpty) {
    return 1.0;
  }
  if (actual.isEmpty) {
    return 0.0;
  }
  final storedSet = stored.map(normalizeWord).toSet();
  final actualSet = actual.map(normalizeWord).toSet();
  if (storedSet.isEmpty) {
    return actualSet.isEmpty ? 1.0 : 0.0;
  }

  final matches = storedSet.intersection(actualSet).length;
  return matches / storedSet.length;
}
