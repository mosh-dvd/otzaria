import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';

String stripHtmlIfNeeded(String text) {
  return text.replaceAll(SearchRegexPatterns.htmlStripper, '');
}

String truncate(String text, int length) {
  return text.length > length ? '${text.substring(0, length)}...' : text;
}

String removeVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll(' ׀', '');
  return s.replaceAll(SearchRegexPatterns.vowelsAndCantillation, '');
}

String highLight(String data, String searchQuery, {int currentIndex = -1}) {
  if (searchQuery.isEmpty) return data;

  final regex = RegExp(RegExp.escape(searchQuery), caseSensitive: false);
  final matches = regex.allMatches(data).toList();

  if (matches.isEmpty) return data;

  // אם לא צוין אינדקס נוכחי, נדגיש את כל התוצאות באדום
  if (currentIndex == -1) {
    return data.replaceAll(regex, '<font color=red>$searchQuery</font>');
  }

  // נדגיש את התוצאה הנוכחית בכחול ואת השאר באדום
  String result = data;
  int offset = 0;

  for (int i = 0; i < matches.length; i++) {
    final match = matches[i];
    final color = i == currentIndex ? 'blue' : 'red';
    final backgroundColor =
        i == currentIndex ? ' style="background-color: yellow;"' : '';
    final replacement =
        '<font color=$color$backgroundColor>${match.group(0)}</font>';

    final start = match.start + offset;
    final end = match.end + offset;

    result = result.substring(0, start) + replacement + result.substring(end);
    offset += replacement.length - match.group(0)!.length;
  }

  return result;
}

String getTitleFromPath(String path) {
  path = path
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
  final fileName = path.split(Platform.pathSeparator).last;

  // אם אין נקודה בשם הקובץ, נחזיר את השם כמו שהוא
  final lastDotIndex = fileName.lastIndexOf('.');
  if (lastDotIndex == -1) {
    return fileName;
  }

  // נסיר רק את הסיומת (החלק האחרון אחרי הנקודה האחרונה)
  return fileName.substring(0, lastDotIndex);
}

// Cache for the CSV data to avoid reading the file multiple times
Map<String, String>? _csvCache;

Future<bool> hasTopic(String title, String topic) async {
  // Load CSV data once and cache it
  if (_csvCache == null) {
    await _loadCsvCache();
  }

  // Check if title exists in CSV cache
  if (_csvCache!.containsKey(title)) {
    final generation = _csvCache![title]!;
    final mappedCategory = _mapGenerationToCategory(generation);
    return mappedCategory == topic;
  }

  // Book not found in CSV, it's "מפרשים נוספים"
  if (topic == 'מפרשים נוספים') {
    return true;
  }

  // Fallback to original path-based logic
  final titleToPath = await FileSystemData.instance.titleToPath;
  return titleToPath[title]?.contains(topic) ?? false;
}

Future<void> _loadCsvCache() async {
  _csvCache = {};

  try {
    final libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    final csvPath =
        '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אודות התוכנה${Platform.pathSeparator}סדר הדורות.csv';
    final csvFile = File(csvPath);

    debugPrint('📂 Loading CSV from: $csvPath');

    if (await csvFile.exists()) {
      debugPrint('✅ CSV file exists, loading...');
      final csvString = await csvFile.readAsString();
      final lines = csvString.split('\n');
      debugPrint('📊 CSV has ${lines.length} lines');

      // Skip header and parse all lines
      int loadedCount = 0;
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Parse CSV line properly - handle commas inside quoted fields
        final parts = _parseCsvLine(line);
        if (parts.length >= 2) {
          final bookTitle = parts[0].trim();
          final generation = parts[1].trim();
          _csvCache![bookTitle] = generation;
          loadedCount++;
        }
      }
      debugPrint('✅ Loaded $loadedCount commentators from CSV');
    } else {
      debugPrint('❌ CSV file not found at: $csvPath');
    }
  } catch (e) {
    debugPrint('❌ Error loading CSV: $e');
    // If CSV fails, keep empty cache
    _csvCache = {};
  }
}

/// Clears the CSV cache to force reload on next access
void clearCommentatorOrderCache() {
  _csvCache = null;
}

// Helper function to parse CSV line with proper comma handling
List<String> _parseCsvLine(String line) {
  final List<String> result = [];
  bool inQuotes = false;
  String currentField = '';

  for (int i = 0; i < line.length; i++) {
    final char = line[i];

    if (char == '"') {
      // Handle escaped quotes (double quotes)
      if (i + 1 < line.length && line[i + 1] == '"' && inQuotes) {
        currentField += '"';
        i++; // Skip the next quote
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      result.add(currentField.trim());
      currentField = '';
    } else {
      currentField += char;
    }
  }

  // Add the last field
  result.add(currentField.trim());

  return result;
}

// Helper function to map CSV generation to our categories
String _mapGenerationToCategory(String generation) {
  switch (generation) {
    case 'תורה שבכתב':
      return 'תורה שבכתב';
    case 'חז"ל':
      return 'חז"ל';
    case 'ראשונים':
      return 'ראשונים';
    case 'אחרונים':
      return 'אחרונים';
    case 'מחברי זמננו':
      return 'מחברי זמננו';
    default:
      return 'מפרשים נוספים';
  }
}

// Matches the Tetragrammaton with any Hebrew diacritics or cantillation marks.
/// מקטין טקסט בתוך סוגריים עגולים
/// תנאים:
/// 1. אם יש סוגר פותח נוסף בפנים - מתעלם מהסוגר החיצוני ומקטין רק את הפנימיים
/// 2. אם אין סוגר סוגר עד סוף המקטע - לא מקטין כלום
String formatTextWithParentheses(String text) {
  if (text.isEmpty) return text;

  final StringBuffer result = StringBuffer();
  int i = 0;

  while (i < text.length) {
    if (text[i] == '(') {
      // מחפשים את הסוגר הסוגר המתאים
      int openCount = 1;
      int j = i + 1;
      int innerOpenIndex = -1;

      // בודקים אם יש סוגר פותח נוסף בפנים
      while (j < text.length && openCount > 0) {
        if (text[j] == '(') {
          if (innerOpenIndex == -1) {
            innerOpenIndex = j; // שומרים את המיקום של הסוגר הפנימי הראשון
          }
          openCount++;
        } else if (text[j] == ')') {
          openCount--;
        }
        j++;
      }

      // אם לא מצאנו סוגר סוגר - מוסיפים הכל כמו שהוא
      if (openCount > 0) {
        result.write(text[i]);
        i++;
        continue;
      }

      // אם יש סוגר פנימי - מתעלמים מהחיצוני ומעבדים רק את הפנימי
      if (innerOpenIndex != -1) {
        // מוסיפים את החלק עד הסוגר הפנימי
        result.write(text.substring(i, innerOpenIndex));
        // ממשיכים מהסוגר הפנימי
        i = innerOpenIndex;
        continue;
      }

      // אם אין סוגר פנימי - מקטינים את כל התוכן
      final content = text.substring(i + 1, j - 1);
      result.write('<small>(');
      result.write(content);
      result.write(')</small>');
      i = j;
    } else {
      result.write(text[i]);
      i++;
    }
  }

  return result.toString();
}

String replaceHolyNames(String s) {
  return s.replaceAllMapped(
    SearchRegexPatterns.holyName,
    (match) => 'י${match[1]}ק${match[2]}ו${match[3]}ק${match[4]}',
  );
}

String removeTeamim(String s) => s
    .replaceAll('־', ' ')
    .replaceAll(' ׀', '')
    .replaceAll('ֽ', '')
    .replaceAll('׀', '')
    .replaceAll(SearchRegexPatterns.cantillationOnly, '');

String removeSectionNames(String s) => s
    .replaceAll('פרק', '')
    .replaceAll('פסוק', '')
    .replaceAll('פסקה', '')
    .replaceAll('סעיף', '')
    .replaceAll('סימן', '')
    .replaceAll('הלכה', '')
    .replaceAll('מאמר', '')
    .replaceAll('קטן', '')
    .replaceAll('משנה', '')
    .replaceAll(RegExp(r'(?<=[א-ת])י|י(?=[א-ת])'), '')
    .replaceAll(RegExp(r'(?<=[א-ת])ו|ו(?=[א-ת])'), '')
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll(',', '')
    .replaceAll(':', ' ב')
    .replaceAll('.', ' א');

String replaceParaphrases(String s) {
  s = s
      .replaceAll(' מהדורא תנינא', ' מהדו"ת')
      .replaceAll(' מהדורא', ' מהדורה')
      .replaceAll(' מהדורה', ' מהדורא')
      .replaceAll(' פני', ' פני יהושע')
      .replaceAll(' תניינא', ' תנינא')
      .replaceAll(' תנינא', ' תניינא')
      .replaceAll(' אא', ' אשל אברהם')
      .replaceAll(' אבהע', ' אבן העזר')
      .replaceAll(' אבעז', ' אבן עזרא')
      .replaceAll(' אדז', ' אדרא זוטא')
      .replaceAll(' אדרא רבה', ' אדרא')
      .replaceAll(' אדרות', ' אדרא')
      .replaceAll(' אהע', ' אבן העזר')
      .replaceAll(' אהעז', ' אבן העזר')
      .replaceAll(' אוהח', ' אור החיים')
      .replaceAll(' אוח', ' אורח חיים')
      .replaceAll(' אורח', ' אורח חיים')
      .replaceAll(' אידרא', ' אדרא')
      .replaceAll(' אידרות', ' אדרא')
      .replaceAll(' ארבעה טורים', ' טור')
      .replaceAll(' באהג', ' באר הגולה')
      .replaceAll(' באוה', ' ביאור הלכה')
      .replaceAll(' באוהל', ' ביאור הלכה')
      .replaceAll(' באור הלכה', ' ביאור הלכה')
      .replaceAll(' בב', ' בבא בתרא')
      .replaceAll(' בהגרא', ' ביאור הגרא')
      .replaceAll(' בי', ' ביאור')
      .replaceAll(' בי', ' בית יוסף')
      .replaceAll(' ביאהל', ' ביאור הלכה')
      .replaceAll(' ביאו', ' ביאור')
      .replaceAll(' ביאוה', ' ביאור הלכה')
      .replaceAll(' ביאוהג', ' ביאור הגרא')
      .replaceAll(' ביאוהל', ' ביאור הלכה')
      .replaceAll(' ביהגרא', ' ביאור הגרא')
      .replaceAll(' ביהל', ' בית הלוי')
      .replaceAll(' במ', ' בבא מציעא')
      .replaceAll(' במדבר', ' במדבר רבה')
      .replaceAll(' במח', ' באר מים חיים')
      .replaceAll(' במר', ' במדבר רבה')
      .replaceAll(' בעהט', ' בעל הטורים')
      .replaceAll(' בק', ' בבא קמא')
      .replaceAll(' בר', ' בראשית רבה')
      .replaceAll(' ברר', ' בראשית רבה')
      .replaceAll(' בש', ' בית שמואל')
      .replaceAll(' ד', ' דף')
      .replaceAll(' דבר', ' דברים רבה')
      .replaceAll(' דהי', ' דברי הימים')
      .replaceAll(' דויד', ' דוד')
      .replaceAll(' דמ', ' דגול מרבבה')
      .replaceAll(' דמ', ' דרכי משה')
      .replaceAll(' דמר', ' דגול מרבבה')
      .replaceAll(' דרך ה', ' דרך השם')
      .replaceAll(' דרך פיקודיך', ' דרך פקודיך')
      .replaceAll(' דרמ', ' דרכי משה')
      .replaceAll(' דרפ', ' דרך פקודיך')
      .replaceAll(' האריזל', ' הארי')
      .replaceAll(' הגהות מיימוני', ' הגהות מיימוניות')
      .replaceAll(' הגהות מימוניות', ' הגהות מיימוניות')
      .replaceAll(' הגהמ', ' הגהות מיימוניות')
      .replaceAll(' הגמ', ' הגהות מיימוניות')
      .replaceAll(' הילכות', ' הלכות')
      .replaceAll(' הל', ' הלכות')
      .replaceAll(' הלכ', ' הלכות')
      .replaceAll(' הלכה', ' הלכות')
      .replaceAll(' המשנה', ' המשניות')
      .replaceAll(' הרב', ' ר')
      .replaceAll(' הרב', ' רבי')
      .replaceAll(' הרב', ' רבינו')
      .replaceAll(' הרב', ' רבנו')
      .replaceAll(' ויקר', ' ויקרא רבה')
      .replaceAll(' ויר', ' ויקרא רבה')
      .replaceAll(' זהח', ' זוהר חדש')
      .replaceAll(' זהר חדש', ' זוהר חדש')
      .replaceAll(' זהר', ' זוהר')
      .replaceAll(' זוהח', ' זוהר חדש')
      .replaceAll(' זח', ' זוהר חדש')
      .replaceAll(' חדושי', ' חי')
      .replaceAll(' חוד', ' חוות דעת')
      .replaceAll(' חוהל', ' חובת הלבבות')
      .replaceAll(' חווד', ' חוות דעת')
      .replaceAll(' חומ', ' חושן משפט')
      .replaceAll(' חח', ' חפץ חיים')
      .replaceAll(' חי', ' חדושי')
      .replaceAll(' חידושי אגדות', ' חדושי אגדות')
      .replaceAll(' חידושי הלכות', ' חדושי הלכות')
      .replaceAll(' חידושי', ' חדושי')
      .replaceAll(' חידושי', ' חי')
      .replaceAll(' חתס', ' חתם סופר')
      .replaceAll(' יד החזקה', ' רמבם')
      .replaceAll(' יהושוע', ' יהושע')
      .replaceAll(' יוד', ' יורה דעה')
      .replaceAll(' יוט', ' יום טוב')
      .replaceAll(' יורד', ' יורה דעה')
      .replaceAll(' ילקוט', ' ילקוט שמעוני')
      .replaceAll(' ילקוש', ' ילקוט שמעוני')
      .replaceAll(' ילקש', ' ילקוט שמעוני')
      .replaceAll(' ירוש', ' ירושלמי')
      .replaceAll(' ירמי', ' ירמיהו')
      .replaceAll(' ירמיה', ' ירמיהו')
      .replaceAll(' ישעי', ' ישעיהו')
      .replaceAll(' ישעיה', ' ישעיהו')
      .replaceAll(' כופ', ' כרתי ופלתי')
      .replaceAll(' כפ', ' כרתי ופלתי')
      .replaceAll(' כרופ', ' כרתי ופלתי')
      .replaceAll(' כתס', ' כתב סופר')
      .replaceAll(' לחמ', ' לחם משנה')
      .replaceAll(' ליקוטי אמרים', ' תניא')
      .replaceAll(' מ', ' משנה')
      .replaceAll(' מאוש', ' מאור ושמש')
      .replaceAll(' מב', ' משנה ברורה')
      .replaceAll(' מגא', ' מגיני ארץ')
      .replaceAll(' מגא', ' מגן אברהם')
      .replaceAll(' מגילת', ' מגלת')
      .replaceAll(' מגמ', ' מגיד משנה')
      .replaceAll(' מד רבה', ' מדרש רבה')
      .replaceAll(' מד', ' מדרש')
      .replaceAll(' מדות', ' מידות')
      .replaceAll(' מדר', ' מדרש רבה')
      .replaceAll(' מדר', ' מדרש')
      .replaceAll(' מדרש רבא', ' מדרש רבה')
      .replaceAll(' מדת', ' מדרש תהלים')
      .replaceAll(' מהדורא תנינא', ' מהדות')
      .replaceAll(' מהדורא', ' מהדורה')
      .replaceAll(' מהדורה', ' מהדורא')
      .replaceAll(' מהרשא', ' חדושי אגדות')
      .replaceAll(' מהרשא', ' חדושי הלכות')
      .replaceAll(' מונ', ' מורה נבוכים')
      .replaceAll(' מז', ' משבצות זהב')
      .replaceAll(' ממ', ' מגיד משנה')
      .replaceAll(' מסי', ' מסילת ישרים')
      .replaceAll(' מפרג', ' מפראג')
      .replaceAll(' מקוח', ' מקור חיים')
      .replaceAll(' מרד', ' מרדכי')
      .replaceAll(' משבז', ' משבצות זהב')
      .replaceAll(' משנב', ' משנה ברורה')
      .replaceAll(' משנה תורה', ' רמבם')
      .replaceAll(' משנה', ' משניות')
      .replaceAll(' נהמ', ' נתיבות המשפט')
      .replaceAll(' נובי', ' נודע ביהודה')
      .replaceAll(' נובית', ' נודע ביהודה תניא')
      .replaceAll(' נועא', ' נועם אלימלך')
      .replaceAll(' נפהח', ' נפש החיים')
      .replaceAll(' נפש החים', ' נפש החיים')
      .replaceAll(' נתיבוש', ' נתיבות שלום')
      .replaceAll(' נתיהמ', ' נתיבות המשפט')
      .replaceAll(' ס', ' סעיף')
      .replaceAll(' סדצ', ' ספרא דצניעותא')
      .replaceAll(' סהמ', ' ספר המצוות')
      .replaceAll(' סהמצ', ' ספר המצוות')
      .replaceAll(' סי', ' סימן')
      .replaceAll(' סמע', ' מאירת עינים')
      .replaceAll(' סע', ' סעיף')
      .replaceAll(' סעי', ' סעיף')
      .replaceAll(' ספדצ', ' ספרא דצניעותא')
      .replaceAll(' ספהמצ', ' ספר המצוות')
      .replaceAll(' ספר המצות', ' ספר המצוות')
      .replaceAll(' ספרא', ' תורת כהנים')
      .replaceAll(' עמ', ' עמוד')
      .replaceAll(' עא', ' עמוד א')
      .replaceAll(' עב', ' עמוד ב')
      .replaceAll(' עהש', ' ערוך השולחן')
      .replaceAll(' עח', ' עץ חיים')
      .replaceAll(' עי', ' עין יעקב')
      .replaceAll(' ערהש', ' ערוך השולחן')
      .replaceAll(' ערוך השלחן', ' ערוך השולחן')
      .replaceAll(' פ', ' פרק')
      .replaceAll(' פי', ' פירוש')
      .replaceAll(' פיהמ', ' פירוש המשניות')
      .replaceAll(' פיהמש', ' פירוש המשניות')
      .replaceAll(' פיסקי', ' פסקי')
      .replaceAll(' פירו', ' פירוש')
      .replaceAll(' פירוש המשנה', ' פירוש המשניות')
      .replaceAll(' פמג', ' פרי מגדים')
      .replaceAll(' פני', ' פני יהושע')
      .replaceAll(' פסז', ' פסיקתא זוטרתא')
      .replaceAll(' פסיקתא זוטא', ' פסיקתא זוטרתא')
      .replaceAll(' פסיקתא רבה', ' פסיקתא רבתי')
      .replaceAll(' פסר', ' פסיקתא רבתי')
      .replaceAll(' פעח', ' פרי עץ חיים')
      .replaceAll(' פרח', ' פרי חדש')
      .replaceAll(' פרמג', ' פרי מגדים')
      .replaceAll(' פתש', ' פתחי תשובה')
      .replaceAll(' צפנפ', ' צפנת פענח')
      .replaceAll(' קדושל', ' קדושת לוי')
      .replaceAll(' קוא', ' קול אליהו')
      .replaceAll(' קידושין', ' קדושין')
      .replaceAll(' קיצור', ' קצור')
      .replaceAll(' קצהח', ' קצות החושן')
      .replaceAll(' קצוהח', ' קצות החושן')
      .replaceAll(' קצור', ' קיצור')
      .replaceAll(' קצשוע', ' קיצור שולחן ערוך')
      .replaceAll(' קשוע', ' קיצור שולחן ערוך')
      .replaceAll(' ר חיים', ' הגרח')
      .replaceAll(' ר', ' הרב')
      .replaceAll(' ר', ' ר')
      .replaceAll(' ר', ' רבי')
      .replaceAll(' ר', ' רבינו')
      .replaceAll(' ר', ' רבנו')
      .replaceAll(' רא בהרמ', ' רבי אברהם בן הרמבם')
      .replaceAll(' ראבע', ' אבן עזרא')
      .replaceAll(' ראשיח', ' ראשית חכמה')
      .replaceAll(' רבה', ' מדרש רבה')
      .replaceAll(' רבה', ' רבא')
      .replaceAll(' רבי חיים', ' הגרח')
      .replaceAll(' רבי נחמן', ' מוהרן')
      .replaceAll(' רבי נתן', ' מוהרנת')
      .replaceAll(' רבי', ' הרב')
      .replaceAll(' רבי', ' רבינו')
      .replaceAll(' רבי', ' רבנו')
      .replaceAll(' רבינו חיים', ' הגרח')
      .replaceAll(' רבינו', ' הרב')
      .replaceAll(' רבינו', ' ר')
      .replaceAll(' רבינו', ' רבי')
      .replaceAll(' רבינו', ' רבנו')
      .replaceAll(' רבנו', ' הרב')
      .replaceAll(' רבנו', ' ר')
      .replaceAll(' רבנו', ' רבי')
      .replaceAll(' רבנו', ' רבינו')
      .replaceAll(' רח', ' רבנו חננאל')
      .replaceAll(' ריהל', ' רבי יהודה הלוי')
      .replaceAll(' רעא', ' רבי עקיבא איגר')
      .replaceAll(' רעמ', ' רעיא מהימנא')
      .replaceAll(' רעקא', ' רבי עקיבא איגר')
      .replaceAll(' שבהל', ' שבלי הלקט')
      .replaceAll(' שהג', ' שער הגלגולים')
      .replaceAll(' שהש', ' שיר השירים')
      .replaceAll(' שולחן ערוך הגרז', ' שולחן ערוך הרב')
      .replaceAll(' שוע הגאון רבי זלמן', ' שוע הגרז')
      .replaceAll(' שוע הגאון רבי זלמן', ' שוע הרב')
      .replaceAll(' שוע הגרז', ' שוע הרב')
      .replaceAll(' שוע הרב', ' שולחן ערוך הרב')
      .replaceAll(' שוע הרב', ' שוע הגרז')
      .replaceAll(' שוע', ' שולחן ערוך')
      .replaceAll(' שורש', ' שרש')
      .replaceAll(' שורשים', ' שרשים')
      .replaceAll(' שות', ' תשו')
      .replaceAll(' שות', ' תשובה')
      .replaceAll(' שות', ' תשובות')
      .replaceAll(' שטה מקובצת', ' שיטה מקובצת')
      .replaceAll(' שטמק', ' שיטה מקובצת')
      .replaceAll(' שיהש', ' שיר השירים')
      .replaceAll(' שיטמק', ' שיטה מקובצת')
      .replaceAll(' שך', ' שפתי כהן')
      .replaceAll(' שלחן ערוך', ' שולחן ערוך')
      .replaceAll(' שמור', ' שמות רבה')
      .replaceAll(' שמטה', ' שמיטה')
      .replaceAll(' שמיהל', ' שמירת הלשון')
      .replaceAll(' שע', ' שולחן ערוך')
      .replaceAll(' שעק', ' שערי קדושה')
      .replaceAll(' שעת', ' שערי תשובה')
      .replaceAll(' שפח', ' שפתי חכמים')
      .replaceAll(' שפתח', ' שפתי חכמים')
      .replaceAll(' תבואש', ' תבואות שור')
      .replaceAll(' תבוש', ' תבואות שור')
      .replaceAll(' תהילים', ' תהלים')
      .replaceAll(' תהלים', ' תהילים')
      .replaceAll(' תוכ', ' תורת כהנים')
      .replaceAll(' תומד', ' תומר דבורה')
      .replaceAll(' תוס', ' תוספות')
      .replaceAll(' תוס', ' תוספתא')
      .replaceAll(' תוספ', ' תוספתא')
      .replaceAll(' תנדא', ' תנא דבי אליהו')
      .replaceAll(' תנדבא', ' תנא דבי אליהו')
      .replaceAll(' תנח', ' תנחומא')
      .replaceAll(' תניינא', ' תנינא')
      .replaceAll(' תנינא', ' תניינא')
      .replaceAll(' תקוז', ' תיקוני זוהר')
      .replaceAll(' תשו', ' שות')
      .replaceAll(' תשו', ' תשובה')
      .replaceAll(' תשו', ' תשובות')
      .replaceAll(' תשובה', ' שות')
      .replaceAll(' תשובה', ' תשו')
      .replaceAll(' תשובה', ' תשובות')
      .replaceAll(' תשובות', ' שות')
      .replaceAll(' תשובות', ' תשו')
      .replaceAll(' תשובות', ' תשובה')
      .replaceAll(' תשובת', ' שות')
      .replaceAll(' תשובת', ' תשו')
      .replaceAll(' תשובת', ' תשובה')
      .replaceAll(' תשובת', ' תשובות');

  if (s.startsWith("טז")) {
    s = s.replaceFirst("טז", "טורי זהב");
  }

  if (s.startsWith("מב")) {
    s = s.replaceFirst("מב", "משנה ברורה");
  }

  return s;
}

//פונקציה לחלוקת מפרשים לפי תקופה
Future<Map<String, List<String>>> splitByEra(
  List<String> titles,
) async {
  // יוצרים מבנה נתונים ריק לכל הקטגוריות החדשות
  final Map<String, List<String>> byEra = {
    'תורה שבכתב': [],
    'חז"ל': [],
    'ראשונים': [],
    'אחרונים': [],
    'מחברי זמננו': [],
    'מפרשים נוספים': [],
  };

  // ממיינים כל פרשן לקטגוריה הראשונה שמתאימה לו
  for (final t in titles) {
    if (await hasTopic(t, 'תורה שבכתב')) {
      byEra['תורה שבכתב']!.add(t);
    } else if (await hasTopic(t, 'חז"ל')) {
      byEra['חז"ל']!.add(t);
    } else if (await hasTopic(t, 'ראשונים')) {
      byEra['ראשונים']!.add(t);
    } else if (await hasTopic(t, 'אחרונים')) {
      byEra['אחרונים']!.add(t);
    } else if (await hasTopic(t, 'מחברי זמננו')) {
      byEra['מחברי זמננו']!.add(t);
    } else {
      // כל ספר שלא נמצא בקטגוריות הקודמות יוכנס ל"מפרשים נוספים"
      byEra['מפרשים נוספים']!.add(t);
    }
  }

  // מחזירים את כל הקטגוריות, גם אם הן ריקות
  return byEra;
}
