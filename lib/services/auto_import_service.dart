import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/services/database_import_service.dart';

class AutoImportService {
  static const String _lastScanKey = 'key-last-folder-scan';
  static bool _isScanning = false;

  /// Check for new folders in the library path and import them
  static Future<void> scanAndImportNewFolders({
    void Function(String status)? onProgress,
  }) async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      // Check if auto-import is enabled
      final autoImportEnabled = Settings.getValue<bool>('key-auto-import-new-folders') ?? false;
      if (!autoImportEnabled) return;

      // Get library path
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null) return;

      final libraryDir = Directory(libraryPath);
      if (!await libraryDir.exists()) return;

      // Get seforim.db path
      final dbPath = path.join(libraryPath, 'seforim.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      // Get last scan timestamp
      final lastScan = Settings.getValue<int>(_lastScanKey) ?? 0;
      final lastScanTime = DateTime.fromMillisecondsSinceEpoch(lastScan);

      // Find folders modified after last scan
      final newFolders = <Directory>[];
      await for (final entity in libraryDir.list()) {
        if (entity is Directory) {
          final stat = await entity.stat();
          if (stat.modified.isAfter(lastScanTime)) {
            // Check if folder contains text files
            final hasTextFiles = await entity
                .list()
                .any((file) =>
                    file is File &&
                    (file.path.endsWith('.txt') || file.path.endsWith('.text')));
            
            if (hasTextFiles) {
              newFolders.add(entity);
            }
          }
        }
      }

      // Import new folders
      for (final folder in newFolders) {
        onProgress?.call('מייבא: ${path.basename(folder.path)}');
        
        try {
          await DatabaseImportService.importBooksFromFolder(
            folder.path,
            dbPath,
            (status, {current, total}) {
              onProgress?.call('${path.basename(folder.path)}: $status');
            },
          );
        } catch (e) {
          onProgress?.call('שגיאה בייבוא ${path.basename(folder.path)}: $e');
        }
      }

      // Update last scan timestamp
      await Settings.setValue(_lastScanKey, DateTime.now().millisecondsSinceEpoch);

      if (newFolders.isNotEmpty) {
        onProgress?.call('יובאו ${newFolders.length} תיקיות חדשות');
      }
    } finally {
      _isScanning = false;
    }
  }

  /// Reset the last scan timestamp to force re-scan
  static Future<void> resetLastScan() async {
    await Settings.setValue(_lastScanKey, 0);
  }
}
