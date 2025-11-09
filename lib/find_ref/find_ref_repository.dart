import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:search_engine/search_engine.dart';
import 'package:otzaria/models/books.dart';

class FindRefRepository {
  final DataRepository dataRepository;

  FindRefRepository({required this.dataRepository});

  Future<List<ReferenceSearchResult>> findRefs(String ref, {List<String>? topics}) async {
    // שלב 1: שלוף יותר תוצאות מהרגיל כדי לפצות על אלו שיסוננו
    final rawResults = await TantivyDataProvider.instance
        .searchRefs(replaceParaphrases(removeSectionNames(ref)), 300, false);

    // שלב 2: בצע סינון כפילויות (דה-דופליקציה) חכם
    final unique = _dedupeRefs(rawResults);

    // שלב 3: סנן לפי נושאים אם נבחרו
    final filtered = await _filterByTopics(unique, topics);

    // שלב 4: החזר עד 100 תוצאות ייחודיות
    return filtered.length > 100
        ? filtered.take(100).toList(growable: false)
        : filtered;
  }

  /// מסנן תוצאות לפי נושאים נבחרים
  Future<List<ReferenceSearchResult>> _filterByTopics(
    List<ReferenceSearchResult> results,
    List<String>? selectedTopics,
  ) async {
    // אם לא נבחרו נושאים, החזר את כל התוצאות
    if (selectedTopics == null || selectedTopics.isEmpty) {
      return results;
    }

    // קבל את כל הספרים מהספרייה
    final library = await dataRepository.library;
    final allBooks = library.getAllBooks();
    
    // צור מפה מכותרת ספר לספר עצמו לחיפוש מהיר
    final booksByTitle = <String, Book>{};
    for (final book in allBooks) {
      booksByTitle[book.title] = book;
    }

    // סנן תוצאות לפי נושאים
    final filtered = <ReferenceSearchResult>[];
    for (final result in results) {
      final book = booksByTitle[result.title];
      
      // אם הספר לא נמצא בספרייה, כלול אותו בתוצאות (לא נסנן ספרים חיצוניים)
      if (book == null) {
        filtered.add(result);
        continue;
      }

      // בדוק אם אחד מהנושאים הנבחרים מופיע בנושאי הספר
      final bookTopics = book.topics.split(', ');
      final matchesTopics = selectedTopics.any((selectedTopic) => 
        bookTopics.contains(selectedTopic)
      );

      if (matchesTopics) {
        filtered.add(result);
      }
    }

    return filtered;
  }

  /// מסננת רשימת תוצאות ומשאירה רק את הייחודיות על בסיס מפתח מורכב.
  List<ReferenceSearchResult> _dedupeRefs(List<ReferenceSearchResult> results) {
    final seen = <String>{}; // סט לשמירת מפתחות שכבר נראו
    final out = <ReferenceSearchResult>[];

    for (final r in results) {
      // יצירת מפתח ייחודי חכם שמורכב מ-3 חלקים:

      // 1. טקסט ההפניה לאחר נרמול
      final refKey = _normalize(r.reference);

      // 2. יעד ההפניה (קובץ ספציפי או שם ספר וסוג)
      final file = r.filePath.trim().toLowerCase();
      final title = r.title.trim().toLowerCase();
      final typ = r.isPdf ? 'pdf' : 'txt';
      final dest = file.isNotEmpty ? file : '$title|$typ';

      // 3. המיקום המדויק בתוך היעד
      final seg = _segNum(r.segment);

      // הרכבת המפתח הסופי
      final key = '$refKey|$dest|$seg';

      // הוסף לרשימת הפלט רק אם המפתח לא נראה בעבר
      if (seen.add(key)) {
        out.add(r);
      }
    }
    return out;
  }

  /// פונקציית עזר לנרמול טקסט: מורידה רווחים, הופכת לאותיות קטנות ומאחדת רווחים.
  String _normalize(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// פונקציית עזר להמרת 'segment' למספר שלם (int) בצורה בטוחה.
  int _segNum(dynamic s) {
    if (s is num) return s.round();
    return int.tryParse(s?.toString() ?? '') ?? 0;
  }
}
