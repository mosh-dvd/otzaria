import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/settings/settings_bloc.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  final Map<String, LogicalKeySet> shortcuts = {
    'ctrl+a': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyA,
    ),
    'ctrl+b': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyB,
    ),
    'ctrl+c': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyC,
    ),
    'ctrl+d': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyD,
    ),
    'ctrl+e': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyE,
    ),
    'ctrl+f': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyF,
    ),
    'ctrl+g': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyG,
    ),
    'ctrl+h': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyH,
    ),
    'ctrl+i': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyI,
    ),
    'ctrl+j': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyJ,
    ),
    'ctrl+k': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyK,
    ),
    'ctrl+l': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyL,
    ),
    'ctrl+m': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyM,
    ),
    'ctrl+n': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyN,
    ),
    'ctrl+o': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyO,
    ),
    'ctrl+p': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyP,
    ),
    'ctrl+q': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyQ,
    ),
    'ctrl+r': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyR,
    ),
    'ctrl+s': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    ),
    'ctrl+t': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyT,
    ),
    'ctrl+u': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyU,
    ),
    'ctrl+v': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyV,
    ),
    'ctrl+w': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyW,
    ),
    'ctrl+x': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyX,
    ),
    'ctrl+y': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyY,
    ),
    'ctrl+z': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyZ,
    ),
    'ctrl+0': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit0,
    ),
    'ctrl+1': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit1,
    ),
    'ctrl+2': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit2,
    ),
    'ctrl+3': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit3,
    ),
    'ctrl+4': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit4,
    ),
    'ctrl+5': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit5,
    ),
    'ctrl+6': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit6,
    ),
    'ctrl+7': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit7,
    ),
    'ctrl+8': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit8,
    ),
    'ctrl+9': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit9,
    ),
    'ctrl+tab': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.tab,
    ),
    'ctrl+shift+tab': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.shift,
    ),
    'ctrl+comma': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.comma,
    ),
    'ctrl+shift+b': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyB,
    ),
  };

  Map<ShortcutActivator, VoidCallback> _buildShortcutBindings(
      BuildContext context) {
    // קריאת ערכי הקיצורים מההגדרות בכל פעם שהפונקציה נקראת
    // ניווט כללי
    final libraryShortcut =
        Settings.getValue<String>('key-shortcut-open-library-browser') ??
            'ctrl+l';
    final findRefShortcut =
        Settings.getValue<String>('key-shortcut-open-find-ref') ?? 'ctrl+o';
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';
    final closeAllTabsShortcut =
        Settings.getValue<String>('key-shortcut-close-all-tabs') ?? 'ctrl+x';
    final readingScreenShortcut =
        Settings.getValue<String>('key-shortcut-open-reading-screen') ??
            'ctrl+r';
    final newSearchShortcut =
        Settings.getValue<String>('key-shortcut-open-new-search') ?? 'ctrl+q';
    final settingsShortcut =
        Settings.getValue<String>('key-shortcut-open-settings') ?? 'ctrl+comma';
    final moreShortcut =
        Settings.getValue<String>('key-shortcut-open-more') ?? 'ctrl+m';
    final bookmarksShortcut =
        Settings.getValue<String>('key-shortcut-open-bookmarks') ??
            'ctrl+shift+b';
    final historyShortcut =
        Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h';

    return <ShortcutActivator, VoidCallback>{
      shortcuts[libraryShortcut]!: () {
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.library),
            );
        //set focus
        context.read<FocusRepository>().requestLibrarySearchFocus(
              selectAll: true,
            );
      },
      shortcuts[findRefShortcut]!: () {
        showDialog(context: context, builder: (context) => FindRefDialog());
      },
      shortcuts[closeTabShortcut]!: () {
        final tabsBloc = context.read<TabsBloc>();
        final historyBloc = context.read<HistoryBloc>();
        if (tabsBloc.state.tabs.isNotEmpty) {
          final currentTab =
              tabsBloc.state.tabs[tabsBloc.state.currentTabIndex];
          historyBloc.add(AddHistory(currentTab));
        }
        tabsBloc.add(const CloseCurrentTab());
      },
      shortcuts[closeAllTabsShortcut]!: () {
        final tabsBloc = context.read<TabsBloc>();
        final historyBloc = context.read<HistoryBloc>();
        for (final tab in tabsBloc.state.tabs) {
          if (tab is! SearchingTab) {
            historyBloc.add(AddHistory(tab));
          }
        }
        tabsBloc.add(CloseAllTabs());
      },
      shortcuts[readingScreenShortcut]!: () {
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.reading),
            );
      },
      shortcuts[newSearchShortcut]!: () {
        final useFastSearch = context.read<SettingsBloc>().state.useFastSearch;
        if (!useFastSearch) {
          _openLegacySearchTab(context);
          return;
        }

        showDialog(
          context: context,
          builder: (context) => const SearchDialog(existingTab: null),
        );
      },
      shortcuts['ctrl+shift+tab']!: () {
        context.read<TabsBloc>().add(NavigateToPreviousTab());
      },
      shortcuts['ctrl+tab']!: () {
        context.read<TabsBloc>().add(NavigateToNextTab());
      },
      shortcuts[settingsShortcut]!: () {
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.settings),
            );
      },
      shortcuts[moreShortcut]!: () {
        context.read<NavigationBloc>().add(
              const NavigateToScreen(Screen.more),
            );
      },
      shortcuts[bookmarksShortcut]!: () {
        // Open bookmarks dialog using the same dialog as the button
        showDialog(
          context: context,
          builder: (context) => const BookmarksDialog(),
        );
      },
      shortcuts[historyShortcut]!: () {
        // Open history dialog using the same dialog as the button
        showDialog(
          context: context,
          builder: (context) => const HistoryDialog(),
        );
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    // בניית הקיצורים מחדש בכל build כדי לקבל את הערכים המעודכנים
    return CallbackShortcuts(
      bindings: _buildShortcutBindings(context),
      child: widget.child,
    );
  }

  void _openLegacySearchTab(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    final tabsState = tabsBloc.state;
    final hasSearchTab = tabsState.tabs.any(
      (tab) => tab.runtimeType == SearchingTab,
    );

    if (!hasSearchTab) {
      tabsBloc.add(AddTab(SearchingTab("חיפוש", "")));
    } else {
      final currentScreen = navigationBloc.state.currentScreen;
      final isAlreadySearchTab = currentScreen == Screen.search &&
          tabsState.tabs[tabsState.currentTabIndex].runtimeType == SearchingTab;
      if (!isAlreadySearchTab) {
        final searchTabIndex = tabsState.tabs.indexWhere(
          (tab) => tab.runtimeType == SearchingTab,
        );
        if (searchTabIndex != -1) {
          tabsBloc.add(SetCurrentTab(searchTabIndex));
        }
      }
    }

    navigationBloc.add(const NavigateToScreen(Screen.search));
  }
}
