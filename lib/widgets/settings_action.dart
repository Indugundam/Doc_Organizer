import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// AppBar action that opens [SettingsScreen]. Shared so every screen's
/// AppBar gets the same icon, tooltip, and destination.
Widget settingsAction(BuildContext context) {
  return IconButton(
    icon: const Icon(FluentIcons.settings_24_regular),
    tooltip: 'Settings',
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ),
  );
}
