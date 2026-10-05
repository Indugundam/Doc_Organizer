import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/view_mode_controller.dart';

/// AppBar action that switches between list and grid view. The icon shows
/// the view a tap switches to.
Widget viewModeAction() {
  return ValueListenableBuilder<ViewMode>(
    valueListenable: ViewModeController.mode,
    builder: (context, mode, _) {
      final grid = mode == ViewMode.grid;
      return IconButton(
        icon: Icon(
          grid
              ? FluentIcons.text_bullet_list_ltr_24_regular
              : FluentIcons.grid_24_regular,
        ),
        tooltip: grid ? 'List view' : 'Grid view',
        onPressed: ViewModeController.toggle,
      );
    },
  );
}
