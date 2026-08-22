import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SortOrder { name, dateNewest }

/// Holds the current folder/document sort preference and persists it,
/// the same way [ThemeController] handles the theme setting.
class SortController {
  SortController._();

  static const _prefsKey = 'sort_order';
  static final ValueNotifier<SortOrder> order = ValueNotifier(SortOrder.name);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    order.value = switch (prefs.getString(_prefsKey)) {
      'dateNewest' => SortOrder.dateNewest,
      _ => SortOrder.name,
    };
  }

  static Future<void> setOrder(SortOrder value) async {
    order.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.name);
  }
}
