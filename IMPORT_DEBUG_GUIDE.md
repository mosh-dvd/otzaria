# מדריך Debug לייבוא ספרים

## איך לבדוק מה קורה

כשמנסים לייבא ספרים, תראה הדפסות בקונסול שמסבירות בדיוק מה קורה:

### 1. תחילת התהליך
```
🚀 Starting import process...
📁 User selected folder: C:\Users\...\Downloads\ספרים_חדשים
📚 Library path from settings: C:\Users\...\Documents\otzaria
📂 Selected folder to import: C:\Users\...\Downloads\ספרים_חדשים
📂 Library path (from settings): C:\Users\...\Documents\otzaria
💾 Looking for seforim.db at: C:\Users\...\Documents\otzaria\seforim.db
✅ seforim.db found!
✅ User confirmed import
```

### 2. המרת הספרים
```
📖 Starting book conversion...
📂 Folder: C:\Users\...\Downloads\ספרים_חדשים
✅ Folder exists
💾 Creating temp database: C:\Users\...\AppData\Local\Temp\temp_books_1234567890.db
✅ Temp database created
```

### 3. מיזוג עם המאגר הראשי
```
🔄 Starting merge process...
📂 Main DB: C:\Users\...\Documents\otzaria\seforim.db
📂 Temp DB: C:\Users\...\AppData\Local\Temp\temp_books_1234567890.db
✅ Main DB file exists
🔓 Attempting to open main database...
✅ WAL mode enabled
✅ Main database opened successfully
💾 Creating backup...
✅ Backup created: C:\Users\...\Documents\otzaria\seforim.db.backup.1234567890
🔢 Calculating offsets...
📚 Max book ID: 22
📝 Max line ID: 44614
📖 Max TOC entry ID: 8318
📑 Max TOC text ID: 1518
📂 Max category ID: 2
➕ Offsets: book=1022, line=54614, toc=9318
🔗 Attaching temp database...
✅ Temp database attached
🔄 Starting transaction...
📂 Copying categories...
✅ Categories copied
📚 Copying books...
✅ Books copied
📑 Copying TOC texts...
✅ TOC texts copied
📝 Copying lines...
✅ Lines copied
📖 Copying TOC entries...
✅ TOC entries copied
💾 Committing transaction...
✅ Transaction committed successfully
🔌 Detaching temp database...
✅ Temp database detached
🔒 Closing main database...
✅ Main database closed
```

## שגיאות נפוצות

### שגיאה: "קובץ מאגר הנתונים לא נמצא"

**הסיבה:** מיקום הספרייה לא מוגדר נכון או seforim.db לא קיים.

**פתרון:**
1. בדוק את ההדפסה: `💾 Looking for seforim.db at: [נתיב]`
2. ודא שהקובץ באמת קיים בנתיב הזה
3. אם לא, הגדר מחדש את "מיקום הספרייה" בהגדרות

### שגיאה: "לא ניתן לפתוח את מאגר הנתונים"

**הסיבה:** seforim.db נעול על ידי האפליקציה.

**פתרון:**
1. בדוק אם תראה: `✅ WAL mode enabled`
   - אם כן, זה אמור לעבוד
   - אם לא, סגור את האפליקציה והרץ מחוץ לה

2. חלופה: השתמש בכלים מחוץ לאפליקציה:
   ```bash
   dart run tools/convert_books_to_db.dart "C:\path\to\folder" temp.db
   dart run tools/merge_databases.dart
   ```

### שגיאה: "There is not enough space on the disk"

**הסיבה:** אין מספיק מקום בדיסק ליצירת גיבוי של seforim.db.

**פתרון:**
1. **בטל את הגיבוי**: בדיאלוג הייבוא, בטל את הסימון של "צור גיבוי לפני הייבוא"
   - המערכת תמשיך בלי ליצור גיבוי
   - ⚠️ אם משהו ישתבש, לא תוכל לשחזר!

2. **פנה מקום בדיסק**: מחק קבצים מיותרים כדי לפנות מקום
   - הגיבוי דורש את אותו גודל כמו seforim.db
   - בדוק את הגודל בדיאלוג הייבוא

3. **שמור גיבוי במקום אחר**: (בעתיד - לא מיושם עדיין)
   - העתק ידנית את seforim.db לכונן אחר לפני הייבוא

### שגיאה במהלך ההמרה

**הסיבה:** קבצים לא תקינים או בעיית קידוד.

**פתרון:**
1. בדוק שהקבצים בקידוד UTF-8
2. ודא שהקבצים הם .txt או .text
3. בדוק את ההדפסות לראות איזה קובץ גרם לבעיה

## הבנת התהליך

### מה קורה בדיוק?

1. **בחירת תיקייה**: אתה בוחר תיקייה עם קבצי טקסט (למשל בהורדות)
2. **מציאת seforim.db**: המערכת מחפשת את seforim.db במיקום הספרייה המוגדר (לא בתיקייה שבחרת!)
3. **המרה**: הקבצים מהתיקייה שבחרת מומרים למאגר נתונים זמני
4. **מיזוג**: המאגר הזמני מתמזג עם seforim.db הראשי
5. **רענון**: הספרייה מתרעננת כדי להציג את הספרים החדשים

### ⚠️ חשוב: מיקום הספרייה לא משתנה!

התהליך **רק מוסיף** ספרים למאגר הקיים. הוא **לא משנה** את מיקום הספרייה.

- ✅ הספרים החדשים נוספים ל-seforim.db
- ✅ הספרייה מתרעננת להציג את השינויים
- ❌ מיקום הספרייה נשאר כמו שהיה
- ❌ התיקייה המקורית (שבחרת) לא משתנה

### למה שני מיקומים?

- **תיקייה לייבוא** (שאתה בוחר): איפה הספרים החדשים נמצאים
- **מיקום הספרייה** (מההגדרות): איפה seforim.db הראשי נמצא

זה מאפשר לך לייבא ספרים מכל מקום (USB, הורדות, וכו') למאגר הראשי שלך **בלי לשנות את מיקום הספרייה**.

## דוגמה מלאה

```
משתמש: לוחץ על "הוסף ספרים למאגר"
מערכת: פותחת דיאלוג בחירת תיקייה
משתמש: בוחר C:\Users\user\Downloads\ספרים_חדשים
מערכת: 
  - קוראת מההגדרות: מיקום הספרייה = C:\Users\user\Documents\otzaria
  - בונה נתיב: C:\Users\user\Documents\otzaria\seforim.db
  - בודקת שהקובץ קיים
  - מציגה דיאלוג אישור עם שני הנתיבים
משתמש: לוחץ "המשך"
מערכת:
  - ממירה את הספרים מ-Downloads\ספרים_חדשים
  - מאחדת עם seforim.db ב-Documents\otzaria
  - מרעננת את הספרייה
```

## טיפים

1. **תמיד בדוק את ההדפסות** - הן מראות בדיוק מה קורה
2. **שמור את הגיבויים** - כל מיזוג יוצר גיבוי אוטומטי
3. **התחל עם תיקייה קטנה** - נסה עם 2-3 ספרים קודם
4. **אם יש בעיה** - העתק את ההדפסות מהקונסול לניתוח
