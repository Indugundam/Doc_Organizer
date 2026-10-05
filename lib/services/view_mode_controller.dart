import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewMode { list, grid }

/// Holds whether folders and documents are shown as a list or a grid and
/// persists it, the same way [SortController] handles the sort setting.
class ViewModeController {
  ViewModeController._();

  static const _prefsKey = 'view_mode';
  static final ValueNotifier<ViewMode> mode = ValueNotifier(ViewMode.list);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = switch (prefs.getString(_prefsKey)) {
      'grid' => ViewMode.grid,
      _ => ViewMode.list,
    };
  }

  static Future<void> toggle() async {
    mode.value = mode.value == ViewMode.list ? ViewMode.grid : ViewMode.list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.value.name);
  }
}
