# הוראות התקנה - אינטגרציית SQLite

## שלב 1: קבלת קובץ ה-DB

קובץ `seforim.db` צריך להיות במיקום אחד מהבאים:

### אפשרות 1: שורש הפרויקט (מומלץ לפיתוח)
```
otzaria/
├── seforim.db          ← כאן
├── lib/
├── pubspec.yaml
└── ...
```

### אפשרות 2: תיקיית Documents (מומלץ לייצור)
- **Windows:** `C:\Users\<username>\Documents\seforim.db`
- **Linux:** `~/Documents/seforim.db`
- **macOS:** `~/Documents/seforim.db`

### אפשרות 3: תיקיית Application Support
- **Windows:** `%APPDATA%\otzaria\seforim.db`
- **Linux:** `~/.local/share/otzaria/seforim.db`
- **macOS:** `~/Library/Application Support/otzaria/seforim.db`

## שלב 2: וידוא שהקובץ תקין

פתח טרמינל והרץ:

```bash
# בדיקה שהקובץ קיים
ls -lh seforim.db

# בדיקה שהקובץ תקין
sqlite3 seforim.db "SELECT COUNT(*) FROM book;"
```

אמור להדפיס מספר (כמות הספרים ב-DB).

## שלב 3: הרצת האפליקציה

```bash
# התקנת תלויות (אם עוד לא)
flutter pub get

# הרצה
flutter run
```

## שלב 4: בדיקה שהכל עובד

1. פתח ספר כלשהו
2. בדוק את הלוגים (Console) - אמור לראות:
   ```
   Opening database at: <path>/seforim.db
   Database opened successfully
   Loaded book "<title>" from SQLite (XXXX chars)
   ```

3. הספר אמור להיטען **מהר מאוד** (פחות משנייה)

## בעיות נפוצות

### "Database file seforim.db not found"

**פתרון:**
1. ודא שהקובץ קיים באחד מהמיקומים
2. העתק אותו לשורש הפרויקט
3. הרץ מחדש

### "Error opening database: file is not a database"

**פתרון:**
1. הקובץ פגום או לא שלם
2. הורד/העתק אותו מחדש
3. ודא שההורדה הושלמה (בדוק גודל קובץ)

### הספר לא נטען מ-SQLite (נטען מקובץ)

**זה תקין!** המערכת עובדת עם fallback:
- אם הספר לא ב-DB → נטען מקובץ TXT/DOCX
- אם הספר ב-DB → נטען מ-SQLite (מהיר!)

בדוק בלוגים:
```
SQLite failed for "<title>", trying file system
```

## בדיקת תוכן ה-DB

אם רוצה לראות מה יש ב-DB:

```bash
# פתיחת DB
sqlite3 seforim.db

# רשימת טבלאות
.tables

# כמה ספרים יש
SELECT COUNT(*) FROM book;

# רשימת 10 ספרים ראשונים
SELECT title FROM book LIMIT 10;

# חיפוש ספר ספציפי
SELECT * FROM book WHERE title LIKE '%בראשית%';

# יציאה
.quit
```

## שאלות נפוצות

### האם צריך להמיר את כל הספרים ל-DB?
לא! המערכת עובדת עם שילוב:
- ספרים ב-DB → מהירים מאוד
- ספרים בקבצים → עובדים כרגיל

### מה קורה אם אין DB בכלל?
האפליקציה תמשיך לעבוד רגיל עם קבצים. ה-DB הוא אופציונלי.

### איך מוסיפים ספרים חדשים ל-DB?
כרגע צריך כלי חיצוני. בעתיד נוסיף תמיכה בעדכון אוטומטי.

### האם PDF נתמך?
PDF נשאר ללא שינוי - הוא לא ב-DB ועובד כרגיל.

---

**זקוק לעזרה?** פתח Issue ב-GitHub!
