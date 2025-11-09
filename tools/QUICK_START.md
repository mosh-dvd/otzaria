# 🚀 התחלה מהירה - המרת ספרים ל-DB

## בדיקה ראשונה (5 דקות)

### 1. צור תיקיית בדיקה:
```bash
mkdir test_books
```

### 2. העתק את הקובץ לדוגמה:
```bash
# Windows
copy tools\sample_book.txt test_books\

# Linux/Mac
cp tools/sample_book.txt test_books/
```

### 3. הרץ המרה:
```bash
dart run tools/convert_books_to_db.dart test_books test_output.db
```

### 4. בדוק את התוצאה:
```bash
dart run tools/test_converted_db.dart test_output.db
```

**אמור לראות:**
```
📚 Books:
   Total: 1
   First 10:
      - ספר לדוגמה (12 lines)

📝 Lines:
   Total: 12

📑 TOC Entries:
   Total: 5

✅ All tests passed!
```

---

## המרה אמיתית

### אם יש לך תיקיית ספרים:

```bash
# המר את כל התיקייה
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא" my_books.db

# בדוק
dart run tools/test_converted_db.dart my_books.db

# אם הכל טוב - השתמש בו!
```

---

## שימוש ב-DB החדש באפליקציה

### אופציה 1: החלף את ה-DB הקיים
```bash
# גבה את הישן
copy seforim.db seforim.db.backup

# השתמש בחדש
copy my_books.db seforim.db

# הרץ את האפליקציה
flutter run
```

### אופציה 2: בדוק בנפרד
```bash
# שנה את שם ה-DB בקוד לזמן קצר
# ב-sqlite_data_provider.dart שנה:
# final dbPath = join(libraryPath, 'my_books.db');

# הרץ
flutter run
```

---

## טיפים

### המרה מהירה של תיקייה קטנה:
```bash
# רק תנך
dart run tools/convert_books_to_db.dart "C:\Books\אוצריא\תנך\תורה" torah.db
```

### בדיקה מהירה:
```bash
sqlite3 test_output.db "SELECT title FROM book;"
```

### ניקוי:
```bash
# מחק קבצי בדיקה
del test_output.db
rmdir /s test_books
```

---

## שאלות נפוצות

### כמה זמן לוקחת ההמרה?
- 10 ספרים: ~5 שניות
- 100 ספרים: ~30 שניות
- 1000 ספרים: ~5 דקות
- 6000 ספרים: ~30 דקות

### כמה מקום זה תופס?
- בערך 10-20% מגודל קבצי הטקסט
- דוגמה: 500MB טקסט → 75MB DB

### מה אם יש שגיאות?
- הסקריפט ממשיך עם הספרים האחרים
- בסוף מדפיס כמה נכשלו
- זה תקין - קבצים פגומים קורים

---

**מוכן להתחיל!** 🎉
