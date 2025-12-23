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
        'bottom': 'אונקלוס על $bookTitle',
        'bottomRight': null,
      };
    }

    // תנ"ך - נביאים וכתובים
    if (categoryPath.contains('תנך') &&
        (categoryPath.contains('נביאים') || categoryPath.contains('כתובים'))) {
      return {
        'right': 'רדק על $bookTitle', // יוצג בשמאל
        'left': 'רשי על $bookTitle', // יוצג בימין
        'bottom': 'מצודת דוד על $bookTitle',
        'bottomRight': 'מלבים על $bookTitle',
      };
    }

    // משנה (לא משנה תורה להרמב"ם)
    if (categoryPath.contains('משנה') && !categoryPath.contains('משנה תורה')) {
      return {
        'right': 'תוספות יום טוב על $bookTitle', // יוצג בשמאל
        'left': 'ברטנורא על $bookTitle', // יוצג בימין
        'bottom': 'תפארת ישראל על $bookTitle',
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
        'right': 'פירוש הגרא על תלמוד ירושלמי $bookTitle', // יוצג בשמאל
        'left': 'פני משה על תלמוד ירושלמי $bookTitle', // יוצג בימין
        'bottom': null,
        'bottomRight': null,
      };
    }

    // שולחן ערוך
    if (categoryPath.contains('שולחן ערוך')) {
      // אורח חיים
      if (categoryPath.contains('אורח חיים')) {
        return {
          'right': 'טז על $bookTitle', // יוצג בשמאל
          'left': 'מגן אברהם על $bookTitle', // יוצג בימין
          'bottom': 'משנה ברורה על $bookTitle',
          'bottomRight': 'ביאור הלכה על $bookTitle',
        };
      }
      // שאר חלקי שולחן ערוך
      return {
        'right': 'ביאור הגרא על $bookTitle', // יוצג בשמאל
        'left': 'באר הגולה על $bookTitle', // יוצג בימין
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
