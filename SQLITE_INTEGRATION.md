# אינטגרציית SQLite לאוצריא

## סקירה כללית

ענף זה מוסיף תמיכה בקריאת ספרים ממסד נתונים SQLite במקום קבצי טקסט בודדים, מה שמשפר משמעותית את הביצועים.

## שינויים שבוצעו

### 1. קובץ חדש: `lib/data/data_providers/sqlite_data_provider.dart`

ספק נתונים חדש שמטפל בכל הפעולות מול מסד הנתונים SQLite:

**פונקציות עיקריות:**
- `getBookLines(String title)` - קריאת כל שורות הספר
- `getBookText(String title)` - קריאת טקסט הספר כמחרוזת אחת
- `getBookToc(String title)` - קריאת תוכן העניינים
- `getBookLinks(String title)` - קריאת קישורים (מפרשים)
- `bookExists(String title)` - בדיקה אם ספר קיים
- `getBookMetadata(String title)` - קריאת מטא-דאטה

**תכונות:**
- ✅ תמיכה בכל הפלטפורמות (Windows, Linux, macOS, Android, iOS)
- ✅ חיפוש אוטומטי של קובץ ה-DB במספר מיקומים
- ✅ פתיחה במצב קריאה בלבד (read-only)
- ✅ טיפול בשגיאות מקיף

### 2. עדכון: `lib/data/data_providers/file_system_data_provider.dart`

הוספת תמיכה ב-SQLite עם fallback לקבצים:

**פונקציות שעודכנו:**
- `getBookText()` - מנסה SQLite קודם, אחר כך קבצים
- `getAllLinksForBook()` - מנסה SQLite קודם, אחר כך JSON
- `getBookToc()` - מנסה SQLite קודם, אחר כך ניתוח טקסט
- `bookExists()` - בודק ב-SQLite וגם בקבצים

**יתרונות:**
- ✅ תאימות לאחור מלאה - ספרים שלא ב-DB עדיין עובדים
- ✅ מעבר חלק - אין צורך להמיר את כל הספרים בבת אחת
- ✅ PDF נשאר ללא שינוי

## מבנה מסד הנתונים

### טבלאות עיקריות:

```sql
-- ספרים
CREATE TABLE book (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    categoryId INTEGER,
    sourceId INTEGER,
    heShortDesc TEXT,
    totalLines INTEGER,
    orderIndex INTEGER
);

-- שורות
CREATE TABLE line (
    id INTEGER PRIMARY KEY,
    bookId INTEGER,
    lineIndex INTEGER,
    content TEXT,
    tocEntryId INTEGER
);

-- תוכן עניינים
CREATE TABLE tocEntry (
    id INTEGER PRIMARY KEY,
    bookId INTEGER,
    parentId INTEGER,
    textId INTEGER,
    level INTEGER,
    lineId INTEGER
);

-- קישורים (מפרשים)
CREATE TABLE link (
    id INTEGER PRIMARY KEY,
    sourceBookId INTEGER,
    targetBookId INTEGER,
    sourceLineId INTEGER,
    targetLineId INTEGER,
    connectionTypeId INTEGER
);
```

## התקנה ושימוש

### דרישות מוקדמות:
- קובץ `seforim.db` בתיקיית הספרייה (library path)
  - המיקום מוגדר בהגדרות: `key-library-path`
  - ברירת מחדל: תיקיית הפרויקט
  - הקובץ צריך להיות: `<library-path>/seforim.db`

### אין צורך בשינויים נוספים!
הקוד מזהה אוטומטית את קובץ ה-DB ומשתמש בו.

### Fallback אוטומטי:
- ✅ **ספר קיים ב-DB** → נטען מה-DB (מהיר מאוד!)
- ✅ **ספר לא קיים ב-DB** → נטען מקובץ TXT/DOCX (עובד רגיל!)
- ✅ **PDF** → תמיד נטען מקובץ (ללא שינוי)
- ✅ **ספר חדש שהוספת** → יעבוד מיד מהקובץ!

## שיפורי ביצועים צפויים

| פעולה | לפני (קבצים) | אחרי (SQLite) | שיפור |
|-------|--------------|---------------|--------|
| פתיחת ספר (10MB) | 2-5 שניות | 50-200ms | **95%+** |
| קריאת שורה בודדת | 500ms | 1-5ms | **99%** |
| טעינת TOC | 1-3 שניות | 10-50ms | **98%** |
| חיפוש קישורים | 500ms-2s | 10-50ms | **95%** |
| זיכרון לספר | 10-50MB | 1-5MB | **80-90%** |

## בדיקות

### בדיקה ידנית:
1. העתק את `seforim.db` לשורש הפרויקט
2. הרץ את האפליקציה
3. פתח ספר - אמור להיטען מהר יותר
4. בדוק את הלוגים - אמור לראות: `"Loaded book from SQLite"`

### בדיקת fallback:
1. שנה שם ספר שלא קיים ב-DB
2. הספר אמור להיטען מקובץ (fallback)
3. בלוגים: `"SQLite failed, trying file system"`

## פתרון בעיות

### "Database file seforim.db not found"
- ודא שקובץ ה-DB קיים באחד מהמיקומים הנתמכים
- בדוק הרשאות קריאה לקובץ

### "Error opening database"
- ודא שקובץ ה-DB תקין (לא פגום)
- נסה לפתוח אותו עם `sqlite3` בטרמינל

### ספר לא נטען מ-SQLite
- בדוק שהספר קיים ב-DB: `SELECT * FROM book WHERE title = 'שם הספר'`
- בדוק את הלוגים לשגיאות

## תכונות עתידיות אפשריות

- [ ] מטמון חכם לספרים שנפתחו לאחרונה
- [ ] אינדקס חיפוש מלא (FTS5)
- [ ] סנכרון אוטומטי של ספרים חדשים
- [ ] דחיסת תוכן לחיסכון במקום
- [ ] תמיכה בעדכונים מקוונים של ה-DB

## מידע טכני נוסף

### תלויות:
- `sqflite: ^2.4.2` - SQLite למובייל
- `sqflite_common_ffi: ^2.3.0` - SQLite לדסקטופ
- `sqlite3_flutter_libs: any` - ספריות Native

### קבצים שהשתנו:
1. ✅ `lib/data/data_providers/sqlite_data_provider.dart` (חדש)
2. ✅ `lib/data/data_providers/file_system_data_provider.dart` (עודכן)

### קבצים שלא השתנו:
- ❌ `lib/models/books.dart` - ללא שינוי
- ❌ `lib/text_book/bloc/text_book_bloc.dart` - ללא שינוי
- ❌ כל שאר הקוד - ללא שינוי

## תרומה

אם מצאת באג או יש לך הצעה לשיפור, אנא פתח Issue או Pull Request.

---

**גרסה:** 1.0.0  
**תאריך:** 2024  
**מחבר:** Kiro AI Assistant
