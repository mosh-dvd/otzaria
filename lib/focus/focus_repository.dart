import 'package:flutter/widgets.dart';

enum FocusTarget { none, librarySearch, findRefSearch, bookContent }

class FocusRepository {
  static final FocusRepository _instance = FocusRepository._internal();
  factory FocusRepository() => _instance;
  FocusRepository._internal();

  final FocusNode librarySearchFocusNode = FocusNode();
  final FocusNode findRefSearchFocusNode = FocusNode();

  final TextEditingController librarySearchController = TextEditingController();
  final TextEditingController findRefSearchController = TextEditingController();

  // FocusNode לתוכן הספר הנוכחי - מנוהל על ידי TextBookViewerBloc
  FocusNode? _currentBookContentFocusNode;

  FocusTarget _currentFocusTarget = FocusTarget.none;
  FocusTarget get currentFocusTarget => _currentFocusTarget;

  void requestLibrarySearchFocus({bool selectAll = false}) {
    librarySearchFocusNode.requestFocus();
    if (selectAll) {
      librarySearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: librarySearchController.text.length,
      );
    }
    _currentFocusTarget = FocusTarget.librarySearch;
  }

  void requestFindRefSearchFocus({bool selectAll = false}) {
    findRefSearchFocusNode.requestFocus();
    if (selectAll) {
      findRefSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: findRefSearchController.text.length,
      );
    }
    _currentFocusTarget = FocusTarget.findRefSearch;
  }

  /// רישום FocusNode של תוכן ספר (נקרא מ-TextBookViewerBloc)
  void registerBookContentFocusNode(FocusNode focusNode) {
    _currentBookContentFocusNode = focusNode;
  }

  /// ביטול רישום FocusNode של תוכן ספר
  void unregisterBookContentFocusNode(FocusNode focusNode) {
    if (_currentBookContentFocusNode == focusNode) {
      _currentBookContentFocusNode = null;
    }
  }

  /// בקשת focus לתוכן הספר הנוכחי
  void requestBookContentFocus() {
    if (_currentBookContentFocusNode != null) {
      _currentBookContentFocusNode!.requestFocus();
      _currentFocusTarget = FocusTarget.bookContent;
    }
  }

  void dispose() {
    librarySearchFocusNode.dispose();
    findRefSearchFocusNode.dispose();
    librarySearchController.dispose();
    findRefSearchController.dispose();
  }
}
