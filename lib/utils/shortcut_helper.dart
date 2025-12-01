import 'package:flutter/services.dart';

/// Helper functions for keyboard shortcut matching
class ShortcutHelper {
  /// בודק אם הקיצור שנלחץ תואם להגדרה
  static bool matchesShortcut(KeyEvent event, String shortcutSetting) {
    if (event is! KeyDownEvent) return false;

    final parts = shortcutSetting.toLowerCase().split('+');
    final requiresCtrl = parts.contains('ctrl') || parts.contains('control');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');

    // בדיקת modifiers
    if (requiresCtrl != HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (requiresShift != HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    if (requiresAlt != HardwareKeyboard.instance.isAltPressed) return false;

    // מציאת המקש הראשי (לא modifier)
    final mainKey = parts
        .where((p) =>
            p != 'ctrl' &&
            p != 'control' &&
            p != 'shift' &&
            p != 'alt' &&
            p != 'meta')
        .firstOrNull;

    if (mainKey == null) return false;

    // מיפוי שם המקש ל-LogicalKeyboardKey
    final pressedKeyLabel = event.logicalKey.keyLabel.toLowerCase();

    // בדיקת אותיות
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 97 &&
        mainKey.codeUnitAt(0) <= 122) {
      return pressedKeyLabel == mainKey;
    }

    // בדיקת מספרים
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 48 &&
        mainKey.codeUnitAt(0) <= 57) {
      return event.logicalKey == _digitKeyFromChar(mainKey);
    }

    // בדיקת מקשים מיוחדים
    return _matchesSpecialKey(event.logicalKey, mainKey);
  }

  static LogicalKeyboardKey? _digitKeyFromChar(String digit) {
    switch (digit) {
      case '0':
        return LogicalKeyboardKey.digit0;
      case '1':
        return LogicalKeyboardKey.digit1;
      case '2':
        return LogicalKeyboardKey.digit2;
      case '3':
        return LogicalKeyboardKey.digit3;
      case '4':
        return LogicalKeyboardKey.digit4;
      case '5':
        return LogicalKeyboardKey.digit5;
      case '6':
        return LogicalKeyboardKey.digit6;
      case '7':
        return LogicalKeyboardKey.digit7;
      case '8':
        return LogicalKeyboardKey.digit8;
      case '9':
        return LogicalKeyboardKey.digit9;
      default:
        return null;
    }
  }

  static bool _matchesSpecialKey(LogicalKeyboardKey key, String keyName) {
    switch (keyName) {
      case 'comma':
        return key == LogicalKeyboardKey.comma;
      case 'period':
        return key == LogicalKeyboardKey.period;
      case 'slash':
        return key == LogicalKeyboardKey.slash;
      case 'semicolon':
        return key == LogicalKeyboardKey.semicolon;
      case 'quote':
        return key == LogicalKeyboardKey.quote;
      case 'bracketleft':
        return key == LogicalKeyboardKey.bracketLeft;
      case 'bracketright':
        return key == LogicalKeyboardKey.bracketRight;
      case 'minus':
        return key == LogicalKeyboardKey.minus;
      case 'equal':
        return key == LogicalKeyboardKey.equal;
      case 'space':
        return key == LogicalKeyboardKey.space;
      case 'tab':
        return key == LogicalKeyboardKey.tab;
      case 'enter':
        return key == LogicalKeyboardKey.enter;
      case 'escape':
        return key == LogicalKeyboardKey.escape;
      case 'f1':
        return key == LogicalKeyboardKey.f1;
      case 'f2':
        return key == LogicalKeyboardKey.f2;
      case 'f3':
        return key == LogicalKeyboardKey.f3;
      case 'f4':
        return key == LogicalKeyboardKey.f4;
      case 'f5':
        return key == LogicalKeyboardKey.f5;
      case 'f6':
        return key == LogicalKeyboardKey.f6;
      case 'f7':
        return key == LogicalKeyboardKey.f7;
      case 'f8':
        return key == LogicalKeyboardKey.f8;
      case 'f9':
        return key == LogicalKeyboardKey.f9;
      case 'f10':
        return key == LogicalKeyboardKey.f10;
      case 'f11':
        return key == LogicalKeyboardKey.f11;
      case 'f12':
        return key == LogicalKeyboardKey.f12;
      default:
        return false;
    }
  }
}
