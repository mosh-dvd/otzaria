import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository _repository;

  TabsBloc({
    required TabsRepository repository,
  })  : _repository = repository,
        super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs);
    on<AddTab>(_onAddTab);
    on<RemoveTab>(_onRemoveTab);
    on<SetCurrentTab>(_onSetCurrentTab);
    on<CloseAllTabs>(_onCloseAllTabs);
    on<CloseOtherTabs>(_onCloseOtherTabs);
    on<CloneTab>(_onCloneTab);
    on<MoveTab>(_onMoveTab);
    on<NavigateToNextTab>(_onNavigateToNextTab);
    on<NavigateToPreviousTab>(_onNavigateToPreviousTab);
    on<CloseCurrentTab>(_onCloseCurrentTab);
    on<SaveTabs>(_onSaveTabs);
  }

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    final tabs = _repository.loadTabs();
    final currentTabIndex = _repository.loadCurrentTabIndex();
    emit(state.copyWith(
      tabs: tabs,
      currentTabIndex: currentTabIndex,
    ));
  }

  void _onSaveTabs(SaveTabs event, Emitter<TabsState> emit) {
    _repository.saveTabs(state.tabs, state.currentTabIndex);
  }

  void _onAddTab(AddTab event, Emitter<TabsState> emit) {
    debugPrint('DEBUG: הוספת טאב חדש - ${event.tab.title}');
    final newTabs = List<OpenedTab>.from(state.tabs);
    final newIndex = min(state.currentTabIndex + 1, newTabs.length);
    newTabs.insert(newIndex, event.tab);

    _repository.saveTabs(newTabs, newIndex);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
    ));
  }

  void _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final removedTabIndex = state.tabs.indexOf(event.tab);
    
    // ניקוי משאבים של הטאב שנסגר
    event.tab.dispose();
    
    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);
    
    // אם אין טאבים נותרים, נשאיר את האינדקס ב-0
    if (newTabs.isEmpty) {
      _repository.saveTabs(newTabs, 0);
      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: 0,
      ));
      return;
    }
    
    // חישוב האינדקס החדש - אם סגרנו טאב לפני או בדיוק על הטאב הפעיל, זזים אינדקס אחד אחורה
    var newIndex = removedTabIndex <= state.currentTabIndex
        ? max(state.currentTabIndex - 1, 0)
        : state.currentTabIndex;
    
    // וידוא שהאינדקס תקין (לא חורג מגבולות הרשימה)
    newIndex = min(newIndex, newTabs.length - 1);
    
    _repository.saveTabs(newTabs, newIndex);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
    ));
  }

  void _onSetCurrentTab(SetCurrentTab event, Emitter<TabsState> emit) {
    if (event.index >= 0 && event.index < state.tabs.length) {
      debugPrint(
          'DEBUG: מעבר לטאב ${event.index} - ${state.tabs[event.index].title}');
      _repository.saveTabs(state.tabs, event.index);
      emit(state.copyWith(currentTabIndex: event.index));
    }
  }

  void _onCloseCurrentTab(CloseCurrentTab event, Emitter<TabsState> emit) {
    add(RemoveTab(state.tabs[state.currentTabIndex]));
  }

  void _onCloseAllTabs(CloseAllTabs event, Emitter<TabsState> emit) {
    // ניקוי משאבים של כל הטאבים
    for (final tab in state.tabs) {
      tab.dispose();
    }
    
    _repository.saveTabs([], 0);
    emit(state.copyWith(
      tabs: [],
      currentTabIndex: 0,
    ));
  }

  void _onCloseOtherTabs(CloseOtherTabs event, Emitter<TabsState> emit) {
    // ניקוי משאבים של כל הטאבים מלבד זה שנשאר
    for (final tab in state.tabs) {
      if (tab != event.keepTab) {
        tab.dispose();
      }
    }
    
    final newTabs = [event.keepTab];
    _repository.saveTabs(newTabs, 0);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: 0,
    ));
  }

  void _onCloneTab(CloneTab event, Emitter<TabsState> emit) {
    add(AddTab(OpenedTab.from(event.tab)));
  }

  void _onMoveTab(MoveTab event, Emitter<TabsState> emit) {
    final newTabs = List<OpenedTab>.from(state.tabs);
    final currentTab = newTabs[state.currentTabIndex];
    newTabs.remove(event.tab);
    newTabs.insert(event.newIndex, event.tab);
    final newIndex = newTabs.indexOf(currentTab);

    _repository.saveTabs(newTabs, state.currentTabIndex);
    emit(state.copyWith(tabs: newTabs, currentTabIndex: newIndex));
  }

  void _onNavigateToNextTab(NavigateToNextTab event, Emitter<TabsState> emit) {
    if (state.currentTabIndex < state.tabs.length - 1) {
      final newIndex = state.currentTabIndex + 1;
      _repository.saveTabs(state.tabs, newIndex);
      emit(state.copyWith(currentTabIndex: newIndex));
    }
  }

  void _onNavigateToPreviousTab(
      NavigateToPreviousTab event, Emitter<TabsState> emit) {
    if (state.currentTabIndex > 0) {
      final newIndex = state.currentTabIndex - 1;
      _repository.saveTabs(state.tabs, newIndex);
      emit(state.copyWith(currentTabIndex: newIndex));
    }
  }
}