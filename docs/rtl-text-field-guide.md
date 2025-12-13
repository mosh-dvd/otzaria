# מדריך: תיקון שדות טקסט RTL

## סקירה כללית

רכיב `RtlTextField` מתקן שתי בעיות ידועות ב-Flutter Desktop עם שדות טקסט בעברית:

1. **מקשי חיצים הפוכים** - חץ שמאל מזיז ימינה וחץ ימין מזיז שמאלה
2. **תפריט הקשר לא מתאים** - תפריט ברירת המחדל מרווח מדי ולא מעוצב

## איך ליישם?

### שלב 1: הוסף ייבוא

בראש הקובץ, הוסף:

```dart
import 'package:otzaria/widgets/rtl_text_field.dart';
```

### שלב 2: החלף TextField ב-RtlTextField

**לפני:**
```dart
TextField(
  controller: myController,
  focusNode: myFocusNode,
  decoration: InputDecoration(
    hintText: 'הקלד טקסט...',
  ),
  onChanged: (value) {
    // הקוד שלך
  },
)
```

**אחרי:**
```dart
RtlTextField(
  controller: myController,
  focusNode: myFocusNode,
  decoration: InputDecoration(
    hintText: 'הקלד טקסט...',
  ),
  onChanged: (value) {
    // הקוד שלך
  },
)
```

זהו! פשוט החלף `TextField` ב-`RtlTextField` - כל הפרמטרים זהים.

## פרמטרים נתמכים

`RtlTextField` תומך בכל הפרמטרים הנפוצים של `TextField`:

- `controller` - TextEditingController
- `focusNode` - FocusNode
- `decoration` - InputDecoration
- `onChanged` - ValueChanged<String>
- `onSubmitted` - ValueChanged<String>
- `autofocus` - bool
- `keyboardType` - TextInputType
- `textInputAction` - TextInputAction
- `maxLines` - int
- `minLines` - int
- `enabled` - bool
- `style` - TextStyle
- `textAlign` - TextAlign
- `inputFormatters` - List<TextInputFormatter>

## דוגמאות מהפרויקט

### דוגמה 1: שדה חיפוש פשוט (ספרייה)

```dart
RtlTextField(
  controller: searchController,
  focusNode: searchFocusNode,
  autofocus: true,
  decoration: InputDecoration(
    prefixIcon: const Icon(FluentIcons.search_24_regular),
    suffixIcon: IconButton(
      onPressed: () => searchController.clear(),
      icon: const Icon(FluentIcons.dismiss_24_regular),
    ),
    hintText: 'איתור ספר...',
  ),
  onChanged: (value) {
    // טיפול בשינוי
  },
)
```

### דוגמה 2: שדה עם אימות (חיפוש - מרווח)

```dart
RtlTextField(
  controller: spacingController,
  focusNode: spacingFocusNode,
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    FilteringTextInputFormatter.allow(RegExp(r'^([0-9]|[12][0-9]|30)$')),
  ],
  decoration: InputDecoration(
    labelText: 'מרווח למילה הבאה',
    hintText: '0-30',
  ),
  onChanged: (value) {
    // טיפול בשינוי
  },
)
```

### דוגמה 3: שדה עם onSubmitted (איתור)

```dart
RtlTextField(
  controller: refController,
  focusNode: refFocusNode,
  autofocus: true,
  decoration: InputDecoration(
    hintText: 'הקלד מקור מדוייק...',
    suffixIcon: IconButton(
      icon: const Icon(FluentIcons.dismiss_24_regular),
      onPressed: () => refController.clear(),
    ),
  ),
  onChanged: (value) {
    // חיפוש בזמן אמת
  },
  onSubmitted: (value) {
    // פתיחת התוצאה
  },
)
```

## מה קורה מאחורי הקלעים?

1. **זיהוי RTL אוטומטי** - הרכיב בודק את `Directionality.of(context)`
2. **תיקון חיצים** - אם RTL, מוסיף `CallbackShortcuts` שמהפך את כיוון החיצים
3. **תפריט מותאם** - מוסיף `Listener` שתופס לחיצה ימנית ומציג תפריט קומפקטי
4. **השבתת תפריט ברירת מחדל** - משתמש ב-`contextMenuBuilder` להשבתת התפריט המובנה

## תפריט ההקשר

התפריט המותאם כולל:

**כשיש טקסט נבחר:**
- גזור
- העתק
- הדבק

**כשאין טקסט נבחר:**
- הדבק
- בחר הכל (רק אם יש טקסט בשדה)

התפריט מעוצב בצורה קומפקטית:
- גובה פריט: 36px (במקום 48px)
- padding: 12px (במקום 16px)
- גודל אייקון: 18px (במקום 20px)
- גודל טקסט: 14px

## שאלות נפוצות

**ש: האם זה עובד גם ב-LTR?**  
ת: כן! הרכיב זוהה אוטומטית את הכיוון. ב-LTR הוא מתנהג כמו TextField רגיל.

**ש: האם אני צריך לשנות משהו בקוד הקיים?**  
ת: לא! פשוט החלף `TextField` ב-`RtlTextField` - כל הפרמטרים זהים.

**ש: מה אם אני צריך פרמטר שלא נתמך?**  
ת: פתח issue או הוסף את הפרמטר ל-`RtlTextField` בקובץ `lib/widgets/rtl_text_field.dart`.

**ש: האם זה משפיע על ביצועים?**  
ת: לא. התיקונים מתבצעים רק כשצריך (RTL) ובצורה יעילה.

## קבצים שכבר משתמשים ב-RtlTextField

- ✅ `lib/library/view/library_browser.dart` - שדה חיפוש בספרייה
- ✅ `lib/find_ref/find_ref_dialog.dart` - שדה איתור מקורות
- ✅ `lib/search/view/search_dialog.dart` - שדות מרווח ומילה חילופית
- ✅ `lib/search/view/enhanced_search_field.dart` - שדה החיפוש הראשי

## סיכום

החלפת `TextField` ב-`RtlTextField` היא פשוטה וישירה:

1. הוסף ייבוא: `import 'package:otzaria/widgets/rtl_text_field.dart';`
2. החלף `TextField(` ב-`RtlTextField(`
3. זהו!

הרכיב יטפל אוטומטית בתיקון החיצים ובתפריט ההקשר.
