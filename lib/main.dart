import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_lock_controller.dart';
import 'services/sort_controller.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.load();
  await SortController.load();
  await AppLockController.load();
  // Not awaited: signing in silently and the first sync run in the background.
  SyncService.init();
  runApp(const DocManagerApp());
}

class DocManagerApp extends StatelessWidget {
  const DocManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
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
