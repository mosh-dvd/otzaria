# 🔧 כלי המרת ספרים ל-SQLite

## תיאור

סקריפט עצמאי שממיר קבצי טקסט (TXT) למסד נתונים SQLite.

הפלט הוא קובץ DB נפרד שאפשר לבדוק ולבחון לפני שמשתמשים בו בתוכנה.

---

## שימוש

### תחביר בסיסי:
```bash
dart run tools/convert_books_to_db.dart <תיקיית_קלט> <קובץ_פלט>
```

### דוגמאות:

#### Windows:
```bash
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא" "output_books.db"
```

#### Linux/Mac:
```bash
dart run tools/convert_books_to_db.dart "/home/user/Books/אוצריא" "output_books.db"
```

#### המרת תיקייה ספציפית:
```bash
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\תנך" "tanach.db"
```

---

## מה הסקריפט עושה?

### שלב 1: יצירת מסד נתונים
```
🔧 Creating database schema...
✅ Database schema created
```

יוצר קובץ DB חדש עם המבנה הבא:
- `category` - קטגוריות
- `source` - מקורות
- `book` - ספרים
- `line` - שורות
- `tocText` - טקסטים של תוכן עניינים
- `tocEntry` - ערכי תוכן עניינים

### שלב 2: סריקת קבצים
```
🔧 Scanning for text files...
✅ Found 150 text files
```

סורק את התיקייה ומוצא את כל קבצי ה-TXT.

### שלב 3: המרה
```
🔧 Converting books...
   Converted 10/150 books...
   Converted 20/150 books...
   ...
✅ Converted 150 books successfully
```

לכל קובץ:
1. קורא את התוכן
2. מפצל לשורות
3. מזהה כותרות (h1, h2, h3...)
4. יוצר ערכי TOC
5. שומר ב-DB

### שלב 4: יצירת אינדקסים
```
🔧 Creating indexes...
✅ Indexes created
```

יוצר אינדקסים לחיפוש מהיר.

### שלב 5: סטטיסטיקות
```
📊 Statistics:
   Books: 150
   Lines: 125,430
   TOC entries: 3,245
   Categories: 12
   Database size: 45.23 MB
```

---

## פורמט קלט

### קבצי טקסט נתמכים:
- ✅ `.txt` - קבצי טקסט רגילים
- ❌ `.docx` - לא נתמך (בינתיים)
- ❌ `.pdf` - לא נתמך

### פורמט תוכן:

הסקריפט מזהה כותרות בפורמט HTML:

```html
<h1>שם הספר</h1>
<h2>פרק א</h2>
(א) טקסט הפסוק הראשון
(ב) טקסט הפסוק השני
<h2>פרק ב</h2>
(א) טקסט הפסוק הראשון
```

**רמות כותרות:**
- `<h1>` - רמה 1 (שם ספר)
- `<h2>` - רמה 2 (פרק)
- `<h3>` - רמה 3 (תת-פרק)
- `<h4>` - רמה 4 (תת-תת-פרק)

---

## בדיקת הפלט

### בדיקה עם sqlite3:
```bash
# פתיחת ה-DB
sqlite3 output_books.db

# כמה ספרים יש?
SELECT COUNT(*) FROM book;

# רשימת ספרים
SELECT title FROM book LIMIT 10;

# כמה שורות יש?
SELECT COUNT(*) FROM line;

# תוכן של ספר ספציפי
SELECT content FROM line WHERE bookId = 1 LIMIT 10;

# יציאה
.quit
```

### בדיקה עם הסקריפט הקיים:
```bash
# שנה את test_sqlite_integration.dart לפתוח את output_books.db
# ואז הרץ:
dart run test_sqlite_integration.dart
```

---

## טיפים ושיפורים

### המרת תיקייה ספציפית:
```bash
# רק תנך
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\תנך" "tanach.db"

# רק משנה
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\משנה" "mishna.db"
```

### המרה בשלבים:
```bash
# שלב 1: המר חלק קטן לבדיקה
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\תנך\תורה" "test.db"

# שלב 2: בדוק שהכל עובד
sqlite3 test.db "SELECT * FROM book;"

# שלב 3: המר הכל
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא" "full.db"
```

---

## פתרון בעיות

### "Error: Missing arguments"
```bash
# ודא שמספקים 2 ארגומנטים:
dart run tools/convert_books_to_db.dart <תיקייה> <קובץ_פלט>
```

### "Error: Input directory does not exist"
```bash
# בדוק שהתיקייה קיימת:
dir "C:\Books\אוצריא"  # Windows
ls "/home/user/Books/אוצריא"  # Linux
```

### "Failed to convert X books"
```bash
# זה תקין - קבצים פגומים או לא תקינים
# הסקריפט ממשיך עם השאר
```

### הקובץ גדול מדי
```bash
# המר תיקיות קטנות יותר:
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\תנך" "tanach.db"
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\משנה" "mishna.db"

# ואז מזג אותם (מתקדם)
```

---

## שיפורים עתידיים

- [ ] תמיכה ב-DOCX
- [ ] תמיכה במטא-דאטה (metadata.json)
- [ ] תמיכה בקישורים (links)
- [ ] מיזוג מספר DB לאחד
- [ ] עדכון DB קיים (במקום יצירה מחדש)
- [ ] ממשק גרפי

---

## דוגמת פלט

```
📚 Book to SQLite Converter
═══════════════════════════════════════

📂 Input directory: C:\Books\אוצריא\תנך
💾 Output database: tanach.db

🔧 Step 1: Creating database schema...
   Deleted existing database
✅ Database schema created

🔧 Step 2: Scanning for text files...
✅ Found 39 text files

🔧 Step 3: Converting books...
   Converted 10/39 books...
   Converted 20/39 books...
   Converted 30/39 books...
✅ Converted 39 books successfully

🔧 Step 4: Creating indexes...
✅ Indexes created

📊 Statistics:
   Books: 39
   Lines: 23,145
   TOC entries: 1,534
   Categories: 3
   Database size: 8.45 MB

═══════════════════════════════════════
✅ Conversion completed successfully!
═══════════════════════════════════════
```

---

**מוכן להמרה!** 🚀
