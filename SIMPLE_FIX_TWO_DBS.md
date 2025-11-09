# פתרון פשוט - 2 מסדי נתונים

## המצב הנוכחי:
- יש לך `seforim.db` עם 6,823 ספרים
- יש לך `my_books.db` עם 11 ספרים
- התוכנה טוענת רק מ-`seforim.db`

## הפתרון הפשוט ביותר:

### אופציה 1: מזג את שני ה-DBs (מומלץ!)

```bash
# 1. פתח את seforim.db
sqlite3 seforim.db

# 2. צרף את my_books.db
ATTACH DATABASE 'my_books.db' AS personal;

# 3. העתק את הספרים
INSERT INTO book SELECT * FROM personal.book;
INSERT INTO line SELECT * FROM personal.line;
INSERT INTO tocEntry SELECT * FROM personal.tocEntry;
INSERT INTO tocText SELECT * FROM personal.tocText WHERE id NOT IN (SELECT id FROM tocText);
INSERT INTO category SELECT * FROM personal.category WHERE id NOT IN (SELECT id FROM category);

# 4. נתק
DETACH DATABASE personal;

# 5. יציאה
.quit
```

**יתרונות:**
- ✅ פשוט מאוד
- ✅ כל הספרים במקום אחד
- ✅ לא צריך שינויים בקוד

---

### אופציה 2: שנה את שם ה-DB הראשי

```bash
# 1. גבה את seforim.db
copy seforim.db seforim.db.backup

# 2. השתמש ב-my_books.db כראשי
copy my_books.db seforim.db

# 3. הרץ את האפליקציה
flutter run
```

**יתרונות:**
- ✅ פשוט מאוד
- ✅ רואה רק את הספרים האישיים

**חסרונות:**
- ❌ מאבד את 6,823 הספרים האחרים

---

### אופציה 3: שנה את הקוד (מורכב)

צריך לשנות את `SqliteDataProvider` לתמוך במספר DBs.

**זה מה שניסינו לעשות - אבל זה מורכב!**

---

## ההמלצה שלי:

**אופציה 1 - מזג את ה-DBs!**

זה הכי פשוט והכי יעיל:
1. כל הספרים במקום אחד
2. לא צריך שינויים בקוד
3. עובד מצוין

---

## איך למזג (מפורט):

```bash
# 1. גבה את seforim.db
copy seforim.db seforim.db.backup

# 2. פתח את seforim.db
sqlite3 seforim.db

# 3. הצג כמה ספרים יש עכשיו
SELECT COUNT(*) FROM book;
-- אמור להראות 6823

# 4. צרף את my_books.db
ATTACH DATABASE 'my_books.db' AS personal;

# 5. בדוק כמה ספרים יש ב-my_books
SELECT COUNT(*) FROM personal.book;
-- אמור להראות 11

# 6. מצא את ה-ID הגבוה ביותר
SELECT MAX(id) FROM book;
-- נניח שזה 6823

# 7. העתק ספרים עם ID חדש
INSERT INTO book (id, categoryId, sourceId, title, heShortDesc, notesContent, orderIndex, totalLines, isBaseBook)
SELECT id + 6823, categoryId, sourceId, title, heShortDesc, notesContent, orderIndex, totalLines, isBaseBook
FROM personal.book;

# 8. העתק שורות
INSERT INTO line (id, bookId, lineIndex, content, tocEntryId)
SELECT id + (SELECT MAX(id) FROM line), bookId + 6823, lineIndex, content, tocEntryId
FROM personal.line;

# 9. בדוק
SELECT COUNT(*) FROM book;
-- אמור להראות 6834 (6823 + 11)

# 10. נתק וסגור
DETACH DATABASE personal;
.quit
```

---

## בדיקה:

```bash
# בדוק שהכל עבד
sqlite3 seforim.db "SELECT COUNT(*) FROM book;"
# אמור להראות 6834

# הרץ את האפליקציה
flutter run

# חפש את הספרים האישיים שלך
# הם אמורים להופיע!
```

---

**רוצה שאעזור לך למזג?**
