import 'package:shared_preferences/shared_preferences.dart';

/// שירות לניהול הצגת פופאפ פרסומת
class AdPopupService {
  static const String _keyDontShowAgain = 'ad_popup_dont_show_again';
  static const String _keyRemindLater = 'ad_popup_remind_later_timestamp';

  /// בדיקה האם להציג את הפופאפ
  static Future<bool> shouldShowAd() async {
    final prefs = await SharedPreferences.getInstance();

    // אם המשתמש בחר "אל תציג שוב"
    final dontShowAgain = prefs.getBool(_keyDontShowAgain) ?? false;
    if (dontShowAgain) {
      return false;
    }

    // בדיקה אם המשתמש בחר "תזכיר לי מאוחר יותר"
    final remindLaterTimestamp = prefs.getInt(_keyRemindLater);
    if (remindLaterTimestamp != null) {
      final remindLaterDate =
          DateTime.fromMillisecondsSinceEpoch(remindLaterTimestamp);
      final now = DateTime.now();

      // אם עדיין לא עבר הזמן - לא להציג
      if (now.isBefore(remindLaterDate)) {
        return false;
      }
    }

    return true;
  }

  /// סימון "אל תציג שוב"
  static Future<void> setDontShowAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDontShowAgain, true);
  }

  /// סימון "תזכיר לי מאוחר יותר" (ברירת מחדל: 7 ימים)
  static Future<void> setRemindLater({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final remindDate = DateTime.now().add(Duration(days: days));
    await prefs.setInt(_keyRemindLater, remindDate.millisecondsSinceEpoch);
  }

  /// איפוס ההגדרות (לצורך בדיקה)
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDontShowAgain);
    await prefs.remove(_keyRemindLater);
  }
}
