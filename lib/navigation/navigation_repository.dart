import 'dart:io';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

class NavigationRepository {
  bool checkLibraryIsEmpty() {
    final libraryPath = Settings.getValue<String>('key-library-path');
    if (libraryPath == null) {
      return true;
    }

    // בדיקה שהתיקייה הראשית קיימת
    final rootDir = Directory(libraryPath);
    if (!rootDir.existsSync()) {
      return true;
    }

    // בדיקה שתיקיית אוצריא קיימת
    final libraryDir = Directory('$libraryPath${Platform.pathSeparator}אוצריא');
    if (!libraryDir.existsSync()) {
      return true;
    }

    // בדיקה שהתיקייה לא ריקה
    try {
      final contents = libraryDir.listSync();
      if (contents.isEmpty) {
        return true;
      }
    } catch (e) {
      // אם יש שגיאה בגישה לתיקייה, נחשיב אותה כריקה
      return true;
    }

    return false;
  }

  Future<void> refreshLibrary() async {
    // This will be implemented when we migrate the library bloc
    // For now, it's a placeholder for the refresh functionality
  }
}
