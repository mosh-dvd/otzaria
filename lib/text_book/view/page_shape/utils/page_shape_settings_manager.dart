import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מנהל הגדרות צורת הדף - שומר ומטעין את בחירת המפרשים לכל ספר
class PageShapeSettingsManager {
  /// טעינת ההגדרות עבור ספר מסוים
  static Map<String, String?>? loadConfiguration(String bookTitle) {
    final savedConfig = Settings.getValue<String>('page_shape_$bookTitle');

    if (savedConfig == null) {
      return null;
    }

    // פורמט: "left:רשי,right:תוספות,bottom:מהרש"א,bottomRight:null"
    final parts = savedConfig.split(',');
    final config = <String, String?>{};

    for (final part in parts) {
      final keyValue = part.split(':');
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1] == 'null' ? null : keyValue[1];
        config[key] = value;
      }
    }

    return config;
  }

  /// שמירת ההגדרות עבור ספר מסוים
  static Future<void> saveConfiguration(
    String bookTitle,
    Map<String, String?> config,
  ) async {
    // המרה לפורמט: "left:רשי,right:תוספות,bottom:מהרש"א,bottomRight:null"
    final parts = <String>[];

    config.forEach((key, value) {
      parts.add('$key:${value ?? 'null'}');
    });

    final savedConfig = parts.join(',');
    await Settings.setValue<String>('page_shape_$bookTitle', savedConfig);
  }
}
