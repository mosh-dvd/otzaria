import 'package:hive/hive.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:flutter/foundation.dart';

class TabsRepository {
  static const String _tabsBoxKey = 'key-tabs';
  static const String _currentTabKey = 'key-current-tab';
  static const String _sideBySideModeKey = 'key-side-by-side-mode';

  List<OpenedTab> loadTabs() {
    try {
      final box = Hive.box(name: 'tabs');
      final rawTabs = box.get(_tabsBoxKey, defaultValue: []) as List;
      return List<OpenedTab>.from(
        rawTabs.map((e) => OpenedTab.fromJson(e)).toList(),
      );
    } catch (e) {
      debugPrint('Error loading tabs from disk: $e');
      Hive.box(name: 'tabs').put(_tabsBoxKey, []);
      return [];
    }
  }

  int loadCurrentTabIndex() {
    return Hive.box(name: 'tabs').get(_currentTabKey, defaultValue: 0);
  }

  SideBySideMode? loadSideBySideMode() {
    try {
      final box = Hive.box(name: 'tabs');
      final rawMode = box.get(_sideBySideModeKey);
      if (rawMode == null) return null;
      return SideBySideMode.fromJson(Map<String, dynamic>.from(rawMode));
    } catch (e) {
      debugPrint('Error loading side-by-side mode from disk: $e');
      return null;
    }
  }

  void saveTabs(List<OpenedTab> tabs, int currentTabIndex,
      [SideBySideMode? sideBySideMode]) {
    final box = Hive.box(name: 'tabs');
    box.put(_tabsBoxKey, tabs.map((tab) => tab.toJson()).toList());
    box.put(_currentTabKey, currentTabIndex);
    if (sideBySideMode != null) {
      box.put(_sideBySideModeKey, sideBySideMode.toJson());
    } else {
      box.delete(_sideBySideModeKey);
    }
  }
}
