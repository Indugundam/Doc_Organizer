import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const DocManagerApp());
}

class DocManagerApp extends StatelessWidget {
  const DocManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doc Manager',
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
