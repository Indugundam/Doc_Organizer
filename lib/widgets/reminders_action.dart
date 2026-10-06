import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../screens/reminders_screen.dart';

/// AppBar action that opens [RemindersScreen], shown next to
/// [settingsAction] on every screen. A bell, so it isn't confused with the
/// calendar icon that sets a single document's reminder.
Widget remindersAction(BuildContext context) {
  return IconButton(
    icon: const Icon(FluentIcons.alert_24_regular),
    tooltip: 'Reminders',
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RemindersScreen()),
    ),
  );
}
