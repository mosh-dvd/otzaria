# מסמך דרישות

## מבוא

מערכת הייבוא האוטומטי של ספרים מתיקיות ל-SQLite DB זקוקה לתיקונים ושיפורים. כרגע קיימות שלוש בעיות עיקריות: ביטול הסריקה האוטומטית לא עובד, אין הבחנה בין תיקיות פנימיות לחיצוניות בנוגע למחיקת קבצי טקסט, ואין אפשרות להסיר תיקיות שיובאו מבחוץ.

## מילון מונחים

- **System**: מערכת הייבוא האוטומטי של ספרים
- **AutoImportService**: שירות הסריקה והייבוא האוטומטי
- **Internal Folder**: תיקייה הנמצאת בתוך ספריית הספרייה הראשית
- **External Folder**: תיקייה שיובאה מחוץ לספריית הספרייה הראשית
- **Text File**: קובץ טקסט עם סיומת .txt או .text
- **Database**: מאגר הנתונים seforim.db
- **Auto-Scan Setting**: ההגדרה 'key-auto-import-new-folders'

## דרישות

### דרישה 1: כיבוד הגדרת ביטול סריקה אוטומטית

**User Story:** כמשתמש, אני רוצה שכאשר אני מבטל את הגדרת הסריקה האוטומטית, המערכת תפסיק לסרוק תיקיות חדשות, כדי שאוכל לשלוט מתי מתבצע ייבוא.

#### קריטריוני קבלה

1. WHEN המשתמש מבטל את ההגדרה 'key-auto-import-new-folders', THE System SHALL NOT execute automatic folder scanning
2. WHEN המשתמש מפעיל את ההגדרה 'key-auto-import-new-folders', THE System SHALL execute automatic folder scanning according to configured triggers
3. THE System SHALL verify the Auto-Scan Setting state before initiating any automatic scan operation

### דרישה 2: מחיקת קבצי טקסט מתיקיות פנימיות

**User Story:** כמשתמש, אני רוצה שקבצי טקסט יימחקו אוטומטית רק מתיקיות פנימיות לאחר ייבוא מוצלח, כדי לחסוך מקום ולמנוע כפילות, אך לשמור על קבצים מתיקיות חיצוניות.

#### קריטריוני קבלה

1. WHEN THE System imports books from an Internal Folder, THE System SHALL delete the source Text Files after successful import to Database
2. WHEN THE System imports books from an External Folder, THE System SHALL preserve the source Text Files after import to Database
3. THE System SHALL determine folder type by comparing the folder path with the library path setting
4. IF a Text File deletion fails, THEN THE System SHALL log the error without stopping the import process
5. THE System SHALL only delete Text Files after confirming successful database insertion

### דרישה 3: הסרת תיקיות חיצוניות מהמאגר

**User Story:** כמשתמש, אני רוצה אפשרות להסיר תיקיות שיובאו מבחוץ מהמאגר, כדי לנקות ספרים שאינם רלוונטיים יותר.

#### קריטריוני קבלה

1. THE System SHALL provide a user interface option to remove External Folders from the Database
2. WHEN המשתמש בוחר להסיר תיקייה חיצונית, THE System SHALL display a confirmation dialog with folder details
3. WHEN המשתמש מאשר הסרה, THE System SHALL delete all books associated with that External Folder from the Database
4. THE System SHALL NOT allow removal of books from Internal Folders through this interface
5. AFTER successful removal, THE System SHALL refresh the library display to reflect the changes
6. IF removal fails, THEN THE System SHALL display an error message with details
