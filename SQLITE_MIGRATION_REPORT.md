# דוח מפורט: מעבר ל-SQLite ושינויים שבוצעו

## תאריך: 9 בנובמבר 2025

---

## 1. סיכום השינויים שבוצעו היום

### 1.1 תיקון מערכת הייבוא האוטומטי

#### בעיה 1: ביטול סריקה אוטומטית לא עבד
**הבעיה:** כאשר המשתמש כיבה את ההגדרה "ייבוא אוטומטי של תיקיות חדשות", המערכת המשיכה לסרוק.

**הפתרון:**
- הוספנו פרמטר `forceRun` לפונקציה `scanAndImportNewFolders` ב-`AutoImportService`
- סריקה ידנית (כפתור "סרוק תיקיות חדשות עכשיו") מעבירה `forceRun: true`
- סריקה אוטומטית בודקת את ההגדרה ולא רצה אם היא כבויה

**קבצים שהשתנו:**
- `lib/services/auto_import_service.dart`
- `lib/settings/settings_screen.dart`

---

#### בעיה 2: מחיקת קבצי טקסט
**הבעיה:** לא היה הבדל בין תיקיות שנסרקו אוטומטית (מתוך הספרייה) לתיקיות שיובאו ידנית מבחוץ.

**הפתרון:**
- הוספנו פרמטר `deleteSourceFiles` לפונקציה `importBooksFromFolder`
- תיקיות שנסרקו אוטומטית → `deleteSourceFiles: true` (מוחק קבצי .txt/.text)
- תיקיות שיובאו ידנית → `deleteSourceFiles: false` (שומר את הקבצים)

**לוגיקה:**
```dart
// After successful import
if (deleteSourceFiles && importedFiles.isNotEmpty) {
  // Delete source text files
  for (final file in importedFiles) {
    await file.delete();
  }
}
```

**קבצים שהשתנו:**
- `lib/services/database_import_service.dart`
- `lib/services/auto_import_service.dart`

---

#### בעיה 3: הסרת תיקיות מהמאגר
**הבעיה:** לא הייתה אפשרות להסיר תיקיות שיובאו מבחוץ מהמאגר.

**הפתרון:**
1. **מעקב אחר תיקיות שיובאו:**
   - שמירת רשימה ב-SharedPreferences (`key-imported-categories`)
   - כל תיקייה שמיובאת נוספת לרשימה
   - פונקציות: `getImportedCategories()`, `addImportedCategory()`, `removeImportedCategory()`

2. **UI למחיקה:**
   - כפתור חדש: "הסר תיקיות מהמאגר"
   - דיאלוג עם checkboxes לבחירה מרובה
   - הצגת תיקיות ראשיות בלבד (parentId IS NULL OR parentId = 0)
   - סימון תיקיות שיובאו עם ✓ ירוק
   - מחיקה מרובה עם התקדמות

3. **פונקציית מחיקה:**
   - `removeCategoryFromDatabase()` - מוחקת קטגוריה וכל הספרים שלה
   - מוחקת גם lines, tocEntry, ואת הקטגוריה עצמה
   - מסירה מרשימת הקטגוריות שיובאו

**קבצים שהשתנו:**
- `lib/services/database_import_service.dart` - פונקציות מעקב ומחיקה
- `lib/settings/settings_screen.dart` - UI למחיקה

---

## 2. מצב מערכת SQLite - סקירה מלאה

### 2.1 ארכיטקטורה

```
┌─────────────────────────────────────────┐
│         Application Layer               │
│  (TextBook, Library, Search, etc.)     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│        DataRepository                   │
│  (Facade for all data operations)      │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      FileSystemData                     │
│  (Main data provider with fallback)    │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
┌──────▼─────┐   ┌─────▼──────┐
│  SQLite    │   │ File System│
│  Provider  │   │  (Fallback)│
└────────────┘   └────────────┘
```

### 2.2 מה עובד עם SQLite (✅)

#### קריאת נתונים:
1. **טקסט ספרים** (`getBookText`)
   - קורא מ-SQLite דרך `SqliteDataProvider.getBookText()`
   - Fallback לקבצי טקסט אם לא נמצא ב-DB
   - תמיכה ב-.txt, .text, .docx

2. **תוכן עניינים** (`getBookToc`)
   - קורא מ-SQLite דרך `SqliteDataProvider.getBookToc()`
   - בונה עץ TOC מטבלאות `tocEntry` ו-`tocText`
   - Fallback לפרסור טקסט אם לא נמצא

3. **קישורים** (`getBookLinks`)
   - קורא מטבלת `link` ב-SQLite
   - תמיכה בסוגי קישורים שונים (commentary, reference, etc.)

4. **מטא-דאטה**
   - קטגוריות, מקורות, מידע על ספרים
   - נקרא מטבלאות `category`, `source`, `book`

#### כתיבת נתונים:
1. **ייבוא ספרים** (`importBooksFromFolder`)
   - ממיר קבצי טקסט ל-DB זמני
   - מאחד עם seforim.db הראשי
   - מטפל ב-offsets, foreign keys, transactions

2. **מחיקת קטגוריות** (`removeCategoryFromDatabase`)
   - מוחק קטגוריה וכל הספרים שלה
   - מוחק lines, tocEntry, books
   - Transaction-safe

### 2.3 מה עדיין עובד עם קבצי טקסט (⚠️)

#### עריכת ספרים:
1. **שמירת שינויים** (`saveBookText`)
   - **עדיין שומר לקבצי .txt בלבד**
   - לא מעדכן את ה-DB
   - נמצא ב-`FileSystemDataProvider.saveBookText()`

2. **עריכת קטעים** (`TextSectionEditorDialog`)
   - עורך קבצי טקסט ישירות
   - לא מעדכן DB

#### מבנה ספרייה:
1. **קריאת מבנה תיקיות** (`getLibrary`)
   - עדיין קורא מ-`library.json` ומבנה תיקיות
   - לא משתמש במבנה הקטגוריות מה-DB

2. **metadata.json**
   - עדיין נקרא לקבלת מידע נוסף על ספרים
   - לא משולב עם מטא-דאטה מה-DB

---

## 3. מבנה מאגר הנתונים

### טבלאות עיקריות:

```sql
-- קטגוריות (תיקיות)
CREATE TABLE category (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  level INTEGER,
  parentId INTEGER,
  FOREIGN KEY (parentId) REFERENCES category(id)
);

-- ספרים
CREATE TABLE book (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  categoryId INTEGER,
  sourceId INTEGER,
  orderIndex INTEGER,
  totalLines INTEGER,
  isBaseBook INTEGER,
  hasTargumConnection INTEGER,
  hasReferenceConnection INTEGER,
  hasCommentaryConnection INTEGER,
  hasOtherConnection INTEGER,
  FOREIGN KEY (categoryId) REFERENCES category(id),
  FOREIGN KEY (sourceId) REFERENCES source(id)
);

-- שורות טקסט
CREATE TABLE line (
  id INTEGER PRIMARY KEY,
  bookId INTEGER NOT NULL,
  lineIndex INTEGER NOT NULL,
  content TEXT NOT NULL,
  FOREIGN KEY (bookId) REFERENCES book(id)
);

-- תוכן עניינים - טקסט
CREATE TABLE tocText (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL UNIQUE
);

-- תוכן עניינים - ערכים
CREATE TABLE tocEntry (
  id INTEGER PRIMARY KEY,
  bookId INTEGER NOT NULL,
  parentId INTEGER,
  textId INTEGER NOT NULL,
  level INTEGER NOT NULL,
  isLastChild INTEGER,
  hasChildren INTEGER,
  lineId INTEGER,
  FOREIGN KEY (bookId) REFERENCES book(id),
  FOREIGN KEY (textId) REFERENCES tocText(id),
  FOREIGN KEY (lineId) REFERENCES line(id)
);

-- קישורים
CREATE TABLE link (
  id INTEGER PRIMARY KEY,
  sourceBookId INTEGER NOT NULL,
  targetBookId INTEGER NOT NULL,
  sourceLineId INTEGER NOT NULL,
  targetLineId INTEGER NOT NULL,
  connectionTypeId INTEGER NOT NULL,
  FOREIGN KEY (sourceBookId) REFERENCES book(id),
  FOREIGN KEY (targetBookId) REFERENCES book(id),
  FOREIGN KEY (sourceLineId) REFERENCES line(id),
  FOREIGN KEY (targetLineId) REFERENCES line(id),
  FOREIGN KEY (connectionTypeId) REFERENCES connection_type(id)
);
```

---

## 4. מה חסר / צריך להשלים

### 4.1 עריכת ספרים (Priority: HIGH)
**בעיה:** עריכות נשמרות רק לקבצי טקסט, לא ל-DB

**פתרון נדרש:**
1. יצירת `SqliteDataProvider.updateBookLines()`
2. עדכון `FileSystemDataProvider.saveBookText()` לכתוב גם ל-DB
3. החלטה: האם לשמור גם לקובץ או רק ל-DB?

**השפעה:** ללא זה, עריכות לא ישמרו לספרים שב-DB בלבד

---

### 4.2 מבנה ספרייה (Priority: MEDIUM)
**בעיה:** `getLibrary()` עדיין קורא מ-library.json ולא מה-DB

**פתרון נדרש:**
1. יצירת `SqliteDataProvider.getLibraryStructure()`
2. בניית עץ קטגוריות מטבלת `category`
3. קישור ספרים לקטגוריות

**השפעה:** כרגע הספרייה מציגה מבנה ישן, לא משקף שינויים ב-DB

---

### 4.3 חיפוש (Priority: MEDIUM)
**שאלה:** האם החיפוש משתמש ב-DB או בקבצים?

**צריך לבדוק:**
- `SearchBloc` - איך הוא מחפש?
- האם יש אינדקסים ב-DB לחיפוש מהיר?
- האם FTS (Full Text Search) מופעל?

---

### 4.4 סנכרון (Priority: LOW)
**שאלה:** מה קורה כשיש גם קובץ וגם רשומה ב-DB?

**צריך להחליט:**
- מה המקור האמת?
- האם לסנכרן אוטומטית?
- איך לטפל בקונפליקטים?

---

## 5. המלצות

### 5.1 לטווח קצר (דחוף)
1. ✅ **הושלם:** תיקון מערכת ייבוא ומחיקה
2. ⚠️ **נדרש:** תיקון עריכת ספרים לעבוד עם DB
3. ⚠️ **נדרש:** בדיקת מערכת החיפוש

### 5.2 לטווח בינוני
1. מעבר מלא של `getLibrary()` ל-DB
2. הסרת תלות ב-library.json
3. מיגרציה של metadata.json ל-DB

### 5.3 לטווח ארוך
1. הסרה מלאה של קבצי טקסט (אופציונלי)
2. מערכת גיבוי אוטומטי של DB
3. כלי ניהול DB (vacuum, optimize, etc.)

---

## 6. סטטיסטיקות

### קבצים שהשתנו היום:
- `lib/services/auto_import_service.dart` - 3 שינויים
- `lib/services/database_import_service.dart` - 5 שינויים
- `lib/settings/settings_screen.dart` - 8 שינויים

### שורות קוד שנוספו: ~400
### שורות קוד שהשתנו: ~150

### פיצ'רים חדשים:
1. ✅ מעקב אחר תיקיות שיובאו
2. ✅ מחיקה מרובה של תיקיות
3. ✅ מחיקת קבצי טקסט אוטומטית
4. ✅ בקרה על סריקה אוטומטית

---

## 7. בדיקות שבוצעו

### ✅ עבר בהצלחה:
- ייבוא תיקייה חדשה
- מחיקת תיקייה בודדת
- מחיקת מספר תיקיות
- ביטול סריקה אוטומטית
- סריקה ידנית

### ⚠️ צריך בדיקה:
- עריכת ספר שב-DB
- חיפוש בספרים שב-DB
- ביצועים עם DB גדול (>1GB)

---

## 8. סיכום

המעבר ל-SQLite מתקדם היטב:
- **קריאה:** 95% עובד עם DB + fallback
- **כתיבה:** 70% עובד (ייבוא ומחיקה)
- **עריכה:** 0% - עדיין דורש עבודה

העדיפות הבאה היא תיקון מערכת העריכה לעבוד עם DB.
