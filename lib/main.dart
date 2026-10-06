import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_navigator.dart';
import 'screens/document_viewer_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_lock_controller.dart';
import 'services/reminder_service.dart';
import 'services/search_index.dart';
import 'services/sort_controller.dart';
import 'services/sync_service.dart';
import 'services/view_mode_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/app_toast.dart';

/// Tapping a reminder notification opens its document.
void _openDocument(File file) {
  appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => DocumentViewerScreen(file: file)),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.load();
  await SortController.load();
  await ViewModeController.load();
  await AppLockController.load();
  // Loads saved reminders; notification setup continues in the background.
  await ReminderService.init();
  ReminderService.onOpenDocument = _openDocument;
  // PDF thumbnails and text extraction use pdfrx's engine directly.
  await pdfrxFlutterInitialize();
  // Not awaited: loads the text index, then reads new documents in the
  // background.
  SearchIndex.load();
  // Not awaited: signing in silently and the first sync run in the background.
  SyncService.init();
  runApp(const DocManagerApp());
  // If a reminder notification launched the app, open its document once the
  // navigator exists.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => ReminderService.openLaunchedDocument(),
  );
}

class DocManagerApp extends StatelessWidget {
  const DocManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [AppToast.navigatorObserver],
        title: 'Doc Manager',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: const HomeScreen(),
        builder: (context, child) => AppLockGate(child: child!),
      ),
    );
  }
}
