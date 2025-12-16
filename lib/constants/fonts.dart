import 'package:flutter/material.dart';

/// רשימת הגופנים הזמינים באפליקציה
class AppFonts {
  AppFonts._();

  /// גופן ברירת מחדל לטקסט ראשי
  static const String defaultFont = 'FrankRuhlCLM';
  
  /// גופן ברירת מחדל למפרשים
  static const String defaultCommentatorsFont = 'NotoRashiHebrew';
  
  /// גופן לעריכת טקסט עם טעמים
  static const String editorFont = 'TaameyAshkenaz';

  /// רשימת כל הגופנים הזמינים לבחירה ב-UI
  static const List<FontInfo> availableFonts = [
    FontInfo(value: 'TaameyDavidCLM', label: 'דוד'),
    FontInfo(value: 'FrankRuhlCLM', label: 'פרנק-רוהל'),
    FontInfo(value: 'TaameyAshkenaz', label: 'טעמי אשכנז'),
    FontInfo(value: 'KeterYG', label: 'כתר'),
    FontInfo(value: 'Shofar', label: 'שופר'),
    FontInfo(value: 'NotoSerifHebrew', label: 'נוטו'),
    FontInfo(value: 'Tinos', label: 'טינוס'),
    FontInfo(value: 'NotoRashiHebrew', label: 'רש"י'),
    FontInfo(value: 'Candara', label: 'קנדרה'),
    FontInfo(value: 'roboto', label: 'רובוטו'),
    FontInfo(value: 'Calibri', label: 'קליברי'),
    FontInfo(value: 'Arial', label: 'אריאל'),
  ];

  /// מיפוי גופנים לנתיבי קבצים (לשימוש בהדפסה)
  static const Map<String, String> fontPaths = {
    'Tinos': 'fonts/Tinos-Regular.ttf',
    'TaameyDavidCLM': 'fonts/TaameyDavidCLM-Medium.ttf',
    'TaameyAshkenaz': 'fonts/TaameyAshkenaz-Medium.ttf',
    'NotoSerifHebrew': 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
    'FrankRuehlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
    'KeterYG': 'fonts/KeterYG-Medium.ttf',
    'Shofar': 'fonts/ShofarRegular.ttf',
    'NotoRashiHebrew': 'fonts/NotoRashiHebrew-VariableFont_wght.ttf',
    'Rubik': 'fonts/Rubik-VariableFont_wght.ttf',
  };

  /// מיפוי גופנים לשמות בעברית (לשימוש בהדפסה)
  static const Map<String, String> fontLabels = {
    'Tinos': 'טינוס',
    'TaameyDavidCLM': 'טעמי דוד',
    'TaameyAshkenaz': 'טעמי אשכנז',
    'NotoSerifHebrew': 'נוטו סריף עברית',
    'FrankRuehlCLM': 'פרנק רוהל',
    'KeterYG': 'כתר',
    'Shofar': 'שופר',
    'NotoRashiHebrew': 'נוטו רש"י עברית',
    'Rubik': 'רוביק',
  };

  /// יצירת רשימת DropdownMenuItem לבחירת גופן
  static List<DropdownMenuItem<String>> buildDropdownItems() {
    return availableFonts.map((font) {
      return DropdownMenuItem<String>(
        value: font.value,
        child: Text(
          font.label,
          style: TextStyle(fontFamily: font.value),
        ),
      );
    }).toList();
  }
}

/// מידע על גופן
class FontInfo {
  final String value;
  final String label;

  const FontInfo({required this.value, required this.label});
}
