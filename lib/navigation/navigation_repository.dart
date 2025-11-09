import 'dart:io';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class NavigationRepository {
  bool checkLibraryIsEmpty() {
    final libraryPath = Settings.getValue<String>('key-library-path');
    if (libraryPath == null) {
      return true;
    }

    final libraryDir = Directory('$libraryPath${Platform.pathSeparator}אוצריא');
    
    // Check if directory exists
    if (!libraryDir.existsSync()) {
      return true;
    }
    
    // Check if seforim.db exists - this is the new SQLite-based library
    final dbFile = File('$libraryPath${Platform.pathSeparator}seforim.db');
    if (dbFile.existsSync()) {
      debugPrint('✅ Found seforim.db - library is not empty');
      return false;  // DB exists, library is not empty!
    }
    
    // Fallback: check if there are any files in אוצריא directory (old text-based library)
    if (libraryDir.listSync().isEmpty) {
      return true;
    }

    return false;
  }

  Future<void> refreshLibrary() async {
    // This will be implemented when we migrate the library bloc
    // For now, it's a placeholder for the refresh functionality
  }
}
