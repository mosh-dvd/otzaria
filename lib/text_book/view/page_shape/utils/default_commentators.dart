import 'package:otzaria/models/books.dart';

/// מחלקה לניהול ברירות מחדל של מפרשים לפי סוג הספר
class DefaultCommentators {
  /// מחזיר מפרשי ברירת מחדל לפי קטגוריית הספר
  ///
  /// המפתחות:
  /// - 'right': מפרש שיוצג בצד שמאל (בגלל RTL)
  /// - 'left': מפרש שיוצג בצד ימין (בגלל RTL)
  /// - 'bottom': מפרש תחתון
  /// - 'bottomRight': מפרש תחתון נוסף
  static Map<String, String?> getDefaults(TextBook book) {
    final categoryPath = book.category?.path ?? '';
    final bookTitle = book.title;

    // תנ"ך - תורה
    if (categoryPath.contains('תנך') && categoryPath.contains('תורה')) {
      return {
        'right': 'רמבן על $bookTitle', // יוצג בשמאל
        'left': 'רשי על $bookTitle', // יוצג בימין
        'bottom': 'אור החיים על $bookTitle',
        'bottomRight': null,
      };
    }

    // משנה (לא משנה תורה להרמב"ם)
    if (categoryPath.contains('משנה') && !categoryPath.contains('משנה תורה')) {
      return {
        'right': 'תוספות יום טוב על $bookTitle', // יוצג בשמאל
        'left': 'ברטנורא על $bookTitle', // יוצג בימין
        'bottom': 'עיקר תוספות יום טוב על $bookTitle',
        'bottomRight': null,
      };
    }

    // תלמוד בבלי
    if (categoryPath.contains('תלמוד בבלי')) {
      return {
        'right': 'תוספות על $bookTitle', // יוצג בשמאל
        'left': 'רשי על $bookTitle', // יוצג בימין
        'bottom': null,
        'bottomRight': null,
      };
    }

    // תלמוד ירושלמי
    if (categoryPath.contains('תלמוד ירושלמי')) {
      return {
        'right': 'נועם ירושלמי על $bookTitle', // יוצג בשמאל
        'left': 'פני משה על תלמוד ירושלמי $bookTitle', // יוצג בימין
        'bottom': null,
        'bottomRight': null,
      };
    }

    // אם אין ברירת מחדל, החזר ערכים ריקים
    return {
      'right': null,
      'left': null,
      'bottom': null,
      'bottomRight': null,
    };
  }
}
