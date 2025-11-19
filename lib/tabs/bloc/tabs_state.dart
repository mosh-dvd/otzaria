import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';

class TabsState extends Equatable {
  final List<OpenedTab> tabs;
  final int currentTabIndex;
  final int updateCounter;

  const TabsState({
    required this.tabs,
    required this.currentTabIndex,
    this.updateCounter = 0,
  });

  factory TabsState.initial() {
    return const TabsState(
      tabs: [],
      currentTabIndex: 0,
      updateCounter: 0,
    );
  }

  TabsState copyWith({
    List<OpenedTab>? tabs,
    int? currentTabIndex,
    bool forceUpdate = false,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      updateCounter: forceUpdate ? updateCounter + 1 : updateCounter,
    );
  }

  bool get hasOpenTabs => tabs.isNotEmpty;
  OpenedTab? get currentTab => hasOpenTabs ? tabs[currentTabIndex] : null;

  @override
  List<Object?> get props => [tabs, currentTabIndex, updateCounter];
}
