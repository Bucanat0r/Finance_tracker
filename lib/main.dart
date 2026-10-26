import 'package:flutter/material.dart';

import 'screens/app_shell.dart';

void main() {
  // Required before using plugins (like the one that finds the database
  // folder) at startup.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // The shell holds the bottom bar and the main screens.
      home: const AppShell(),
    );
  }
}
