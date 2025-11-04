import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreFullscreenStatus();
    });
  }

  Future<void> _restoreFullscreenStatus() async {
    if (!mounted) return;
    final settingsState = context.read<SettingsBloc>().state;
    await windowManager.setFullScreen(settingsState.isFullscreen);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => windowManager.minimize(),
              icon: const Icon(FluentIcons.subtract_24_regular),
              tooltip: 'מזער',
            ),
            IconButton(
              onPressed: () async {
                final newFullscreenState = !settingsState.isFullscreen;
                context
                    .read<SettingsBloc>()
                    .add(UpdateIsFullscreen(newFullscreenState));
                await windowManager.setFullScreen(newFullscreenState);
              },
              icon: Icon(settingsState.isFullscreen
                  ? FluentIcons.full_screen_minimize_24_regular
                  : FluentIcons.full_screen_maximize_24_regular),
              tooltip: settingsState.isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
            ),
            IconButton(
              onPressed: () => windowManager.close(),
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'סגור',
            ),
          ],
        );
      },
    );
  }
}
