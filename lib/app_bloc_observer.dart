import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppBlocObserver extends BlocObserver {
  @override
  void onEvent(Bloc bloc, Object? event) {
    super.onEvent(bloc, event);
    debugPrint('🔵 ${bloc.runtimeType} Event: $event');
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    debugPrint('🟡 ${bloc.runtimeType} Change: $change');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    debugPrint('🔴 ${bloc.runtimeType} Error: $error\n$stackTrace');
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    debugPrint('🟢 ${bloc.runtimeType} Transition: $transition');
  }
}
